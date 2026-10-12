import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../domain/backup_path_resolver.dart';
import '../../domain/folder_backup.dart';
import '../hive/box_keys.dart';
import '../hive/hive_setup.dart';
import '../hive/models/folder_model.dart';
import '../hive/models/folder_track_link.dart';

const favoritesFolderId = 'favorites';

/// Owns the folder <-> track relationship, kept entirely decoupled from the
/// filesystem: folders and links only ever reference a track by its stable
/// file path, never duplicate its metadata, and are never touched by a
/// rescan — only [KnownTrackRecord]-based diffing reacts to real file changes.
class FolderRepository {
  static const _uuid = Uuid();

  Box<FolderModel> get _folders => Hive.box<FolderModel>(HiveBoxes.folders);
  Box<FolderTrackLink> get _links => Hive.box<FolderTrackLink>(HiveBoxes.folderTrackLinks);

  void ensureSystemFolders() {
    if (_folders.containsKey(favoritesFolderId)) return;
    _folders.put(
      favoritesFolderId,
      FolderModel(
        id: favoritesFolderId,
        name: 'Favorites',
        createdAt: DateTime.now(),
        isSystem: true,
      ),
    );
  }

  List<FolderModel> getAllFolders() {
    final all = _folders.values.toList()
      ..sort((a, b) {
        if (a.isSystem != b.isSystem) return a.isSystem ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
    return all;
  }

  FolderModel? getFolder(String id) => _folders.get(id);

  Future<FolderModel> createFolder(String name, {int? colorValue}) async {
    final folder = FolderModel(
      id: _uuid.v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
      colorValue: colorValue,
    );
    await _folders.put(folder.id, folder);
    return folder;
  }

  /// Renames a folder and optionally recolours it.
  ///
  /// [colorValue] is only applied when [setColor] is true, because null is a
  /// meaningful value here — it means "go back to the colour picked from the
  /// name" — and so cannot double as "leave this alone".
  Future<void> editFolder(
    String id,
    String newName, {
    int? colorValue,
    bool setColor = false,
  }) async {
    final folder = _folders.get(id);
    if (folder == null || folder.isSystem) return;
    folder.name = newName.trim();
    if (setColor) folder.colorValue = colorValue;
    await folder.save();
  }

  Future<void> deleteFolder(String id) async {
    final folder = _folders.get(id);
    if (folder == null || folder.isSystem) return;
    final keysToRemove = _links.values.where((link) => link.folderId == id).map(_linkKeyFor).toList();
    await _links.deleteAll(keysToRemove);
    await _folders.delete(id);
  }

  /// Points a playlist at a picture of its own, or back at its tracks' artwork
  /// when [coverPath] is null.
  Future<void> setCover(String folderId, String? coverPath) async {
    final folder = _folders.get(folderId);
    if (folder == null) return;
    folder.coverPath = coverPath;
    await folder.save();
  }

  Future<void> setSortMode(String folderId, String sortMode) async {
    final folder = _folders.get(folderId);
    if (folder == null) return;
    folder.sortMode = sortMode;
    await folder.save();
  }

  Future<void> setSortDescending(String folderId, bool descending) async {
    final folder = _folders.get(folderId);
    if (folder == null) return;
    folder.sortDescending = descending;
    await folder.save();
  }

  String _linkKey(String folderId, String trackPath) => folderLinkKey(folderId, trackPath);

  String _linkKeyFor(FolderTrackLink link) => _linkKey(link.folderId, link.trackPath);

  bool isTrackInFolder(String folderId, String trackPath) => _links.containsKey(_linkKey(folderId, trackPath));

  bool isFavorite(String trackPath) => isTrackInFolder(favoritesFolderId, trackPath);

  /// Track paths in a folder, ordered by [FolderTrackLink.manualOrder].
  List<String> getTrackPaths(String folderId) {
    final links = _links.values.where((link) => link.folderId == folderId).toList()
      ..sort((a, b) => a.manualOrder.compareTo(b.manualOrder));
    return links.map((link) => link.trackPath).toList();
  }

  DateTime? addedAt(String folderId, String trackPath) => _links.get(_linkKey(folderId, trackPath))?.addedAt;

  Future<void> addTracks(String folderId, List<String> trackPaths) async {
    final existingOrders = _links.values.where((link) => link.folderId == folderId).map((l) => l.manualOrder);
    var nextOrder = existingOrders.isEmpty ? 0 : existingOrders.reduce((a, b) => a > b ? a : b) + 1;
    for (final path in trackPaths) {
      final key = _linkKey(folderId, path);
      if (_links.containsKey(key)) continue;
      await _links.put(
        key,
        FolderTrackLink(folderId: folderId, trackPath: path, addedAt: DateTime.now(), manualOrder: nextOrder++),
      );
    }
  }

  Future<void> removeTrack(String folderId, String trackPath) async {
    await _links.delete(_linkKey(folderId, trackPath));
  }

  Future<void> toggleFavorite(String trackPath) async {
    if (isFavorite(trackPath)) {
      await removeTrack(favoritesFolderId, trackPath);
    } else {
      await addTracks(favoritesFolderId, [trackPath]);
    }
  }

  /// Applies a new manual order to a folder from a freshly reordered path list.
  /// Only links whose position actually moved are written, in one batch.
  Future<void> reorder(String folderId, List<String> orderedPaths) async {
    final pending = <String, FolderTrackLink>{};
    for (var i = 0; i < orderedPaths.length; i++) {
      final key = _linkKey(folderId, orderedPaths[i]);
      final link = _links.get(key);
      if (link == null || link.manualOrder == i) continue;

      pending[key] = FolderTrackLink(
        folderId: link.folderId,
        trackPath: link.trackPath,
        addedAt: link.addedAt,
        manualOrder: i,
      );
    }
    if (pending.isNotEmpty) await _links.putAll(pending);
  }

  /// Track paths that belong to at least one user-created (non-Favorites)
  /// folder — used by the "uncategorized" filter (module 4).
  Set<String> getCategorizedPaths() {
    return _links.values.where((link) => link.folderId != favoritesFolderId).map((link) => link.trackPath).toSet();
  }

  /// For every track in at least one user folder, the names of those folders,
  /// alphabetically. Favorites is left out — the heart already shows that.
  Map<String, List<String>> folderNamesByPath() {
    final namesById = {
      for (final folder in _folders.values)
        if (!folder.isSystem) folder.id: folder.name,
    };

    final result = <String, List<String>>{};
    for (final link in _links.values) {
      final name = namesById[link.folderId];
      if (name != null) (result[link.trackPath] ??= []).add(name);
    }
    for (final names in result.values) {
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    return result;
  }

  /// How many folder links point at any of [paths].
  int countLinksFor(Set<String> paths) =>
      _links.values.where((link) => paths.contains(link.trackPath)).length;

  /// Drops every folder link for the given paths — used when cleaning up
  /// after files that no longer exist.
  Future<void> removeLinksFor(Set<String> paths) async {
    final keys = _links.values
        .where((link) => paths.contains(link.trackPath))
        .map(_linkKeyFor)
        .toList();
    await _links.deleteAll(keys);
  }

  /// The whole folder structure as a plain snapshot, in display order.
  FolderBackup exportBackup() {
    return FolderBackup(
      createdAt: DateTime.now(),
      folders: [
        for (final folder in getAllFolders())
          BackedUpFolder(
            id: folder.id,
            name: folder.name,
            createdAt: folder.createdAt,
            isSystem: folder.isSystem,
            sortMode: folder.sortMode,
            sortDescending: folder.isSortDescending,
            colorValue: folder.colorValue,
            coverPath: folder.coverPath,
            trackPaths: getTrackPaths(folder.id),
          ),
      ],
    );
  }

  /// Merges a snapshot back in, adding only what is missing.
  ///
  /// Nothing is removed and nothing already on the device is overwritten:
  /// folders the backup knows about are recreated if they are gone, links are
  /// added where they are absent, and a folder that still exists keeps its
  /// current name, colour and order. That makes importing the same file twice
  /// a no-op, which matters because the user restoring a backup usually
  /// cannot tell whether the first attempt did anything.
  ///
  /// [resolver] is how a backup from another device lands on this one: a path
  /// with no file behind it is retried by file name. Left out, paths are taken
  /// literally, which is the right behaviour when restoring onto the device
  /// that wrote the backup.
  Future<FolderImportSummary> importBackup(
    FolderBackup backup, {
    BackupPathResolver? resolver,
  }) async {
    final paths = resolver ?? BackupPathResolver.none();
    var foldersCreated = 0;
    var linksAdded = 0;
    var linksRemapped = 0;
    var linksUnresolved = 0;

    for (final entry in backup.folders) {
      // Favorites is recreated under a fixed id by [ensureSystemFolders], so
      // a backed-up system folder is matched to it by kind, not by id.
      final folderId = entry.isSystem ? favoritesFolderId : entry.id;
      if (folderId.isEmpty) continue;

      if (!_folders.containsKey(folderId)) {
        await _folders.put(
          folderId,
          FolderModel(
            id: folderId,
            name: entry.name,
            createdAt: entry.createdAt,
            isSystem: entry.isSystem,
            sortMode: entry.sortMode,
            sortDescending: entry.sortDescending,
            colorValue: entry.colorValue,
            coverPath: entry.coverPath,
          ),
        );
        foldersCreated++;
      }

      // The two match counts only ever describe links this call actually
      // added, so restoring the same backup a second time reports nothing
      // rather than re-announcing matches it is about to skip.
      final missing = <String>[];
      for (final path in entry.trackPaths) {
        final resolved = paths.resolve(path);
        if (isTrackInFolder(folderId, resolved.path)) continue;
        missing.add(resolved.path);
        switch (resolved.match) {
          case PathMatch.renamed:
            linksRemapped++;
          case PathMatch.unresolved:
            linksUnresolved++;
          case PathMatch.exact:
            break;
        }
      }
      if (missing.isEmpty) continue;

      await addTracks(folderId, missing);
      linksAdded += missing.length;
    }

    return FolderImportSummary(
      foldersCreated: foldersCreated,
      linksAdded: linksAdded,
      linksRemapped: linksRemapped,
      linksUnresolved: linksUnresolved,
    );
  }
}
