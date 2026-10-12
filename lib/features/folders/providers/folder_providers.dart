import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/hive/models/folder_model.dart';
import '../../../data/repositories/folder_repository.dart';
import '../../../domain/folder_sort_mode.dart';
import '../../../domain/track.dart';
import '../../library/providers/library_providers.dart';

final folderRepositoryProvider = Provider<FolderRepository>((ref) => FolderRepository());

/// Bumped after any folder-track link mutation (add/remove/reorder/favorite)
/// so dependent providers know to recompute. Hive writes are synchronous
/// local state, so a simple version counter is enough — no need for a
/// separate stream/notifier per relationship.
class _LinksTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final folderLinksTickProvider = NotifierProvider<_LinksTickNotifier, int>(_LinksTickNotifier.new);

final folderListProvider = Provider<List<FolderModel>>((ref) {
  ref.watch(folderLinksTickProvider);
  final repository = ref.watch(folderRepositoryProvider);
  repository.ensureSystemFolders();
  return repository.getAllFolders();
});

final folderByIdProvider = Provider.family<FolderModel?, String>((ref, id) {
  final folders = ref.watch(folderListProvider);
  for (final folder in folders) {
    if (folder.id == id) return folder;
  }
  return null;
});

/// Which user folders each track has been filed into, for labelling rows.
final folderNamesByPathProvider = Provider<Map<String, List<String>>>((ref) {
  ref.watch(folderLinksTickProvider);
  // Renames only invalidate the folder list, so watch that too.
  ref.watch(folderListProvider);
  return ref.watch(folderRepositoryProvider).folderNamesByPath();
});

final isFavoriteProvider = Provider.family<bool, String>((ref, trackPath) {
  ref.watch(folderLinksTickProvider);
  return ref.watch(folderRepositoryProvider).isFavorite(trackPath);
});

/// A folder's contents: the tracks it holds, plus the links that the current
/// scan could not match to a file.
///
/// Unmatched links are reported rather than quietly dropped. A folder that
/// looks empty because its files are missing and a folder the user never
/// filled are completely different situations, and from inside the app they
/// used to be indistinguishable — which is exactly what made a wiped link box
/// impossible to tell apart from a storage problem.
class FolderContents {
  const FolderContents({required this.tracks, required this.unavailablePaths});

  const FolderContents.empty() : tracks = const [], unavailablePaths = const [];

  final List<Track> tracks;
  final List<String> unavailablePaths;

  /// How many links the folder has, found or not.
  int get linkCount => tracks.length + unavailablePaths.length;

  bool get hasUnavailable => unavailablePaths.isNotEmpty;
}

final folderTracksProvider = Provider.family<AsyncValue<FolderContents>, String>((ref, folderId) {
  ref.watch(folderLinksTickProvider);
  // How the folder is ordered lives on the FolderModel, and changing it
  // mutates that object in place. Watching folderByIdProvider would not
  // notice: it hands back the very same instance, which compares equal, so
  // nothing downstream is ever told. The list provider builds a fresh List
  // each time it is invalidated, which is the signal that actually arrives --
  // without it a sort or a reverse only took effect on the next visit to the
  // folder, once this provider had been disposed and rebuilt.
  ref.watch(folderListProvider);
  final tracksAsync = ref.watch(libraryScanProvider);
  final repository = ref.watch(folderRepositoryProvider);
  final folder = repository.getFolder(folderId);
  final sortMode = FolderSortMode.values.firstWhere(
    (mode) => mode.name == folder?.sortMode,
    orElse: () => FolderSortMode.manual,
  );
  final descending = folder?.isSortDescending ?? false;

  return tracksAsync.whenData((allTracks) {
    final byPath = {for (final track in allTracks) track.path: track};
    final orderedPaths = repository.getTrackPaths(folderId);

    var tracks = <Track>[];
    final unavailablePaths = <String>[];
    for (final path in orderedPaths) {
      final track = byPath[path];
      if (track == null) {
        unavailablePaths.add(path);
      } else {
        tracks.add(track);
      }
    }

    // Reversing the list after sorting rather than flipping the comparator
    // is what lets 'descending' also mean something for the custom order,
    // which has no comparator to flip.
    if (sortMode == FolderSortMode.manual) {
      return FolderContents(
        tracks: descending ? tracks.reversed.toList() : tracks,
        unavailablePaths: unavailablePaths,
      );
    }

    tracks.sort((a, b) => switch (sortMode) {
          FolderSortMode.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          FolderSortMode.artist => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
          FolderSortMode.album => a.album.toLowerCase().compareTo(b.album.toLowerCase()),
          FolderSortMode.duration => a.duration.compareTo(b.duration),
          FolderSortMode.addedToFolder => (repository.addedAt(folderId, a.path) ?? DateTime(0))
              .compareTo(repository.addedAt(folderId, b.path) ?? DateTime(0)),
          FolderSortMode.manual => 0,
        });
    if (descending) {
      tracks = tracks.reversed.toList();
    }
    return FolderContents(tracks: tracks, unavailablePaths: unavailablePaths);
  });
});

class FolderActions {
  FolderActions(this._ref);

  final Ref _ref;

  FolderRepository get _repository => _ref.read(folderRepositoryProvider);

  Future<FolderModel> createFolder(String name, {int? colorValue}) async {
    final folder = await _repository.createFolder(name, colorValue: colorValue);
    _ref.invalidate(folderListProvider);
    return folder;
  }

  Future<void> editFolder(String id, String name, {int? colorValue, bool setColor = false}) async {
    await _repository.editFolder(id, name, colorValue: colorValue, setColor: setColor);
    _ref.invalidate(folderListProvider);
  }

  Future<void> deleteFolder(String id) async {
    await _repository.deleteFolder(id);
    _ref.invalidate(folderListProvider);
    _bumpLinks();
  }

  Future<void> setCover(String folderId, String? coverPath) async {
    await _repository.setCover(folderId, coverPath);
    _ref.invalidate(folderListProvider);
  }

  Future<void> setSortMode(String folderId, FolderSortMode mode) async {
    await _repository.setSortMode(folderId, mode.name);
    _ref.invalidate(folderListProvider);
  }

  Future<void> setSortDescending(String folderId, bool descending) async {
    await _repository.setSortDescending(folderId, descending);
    _ref.invalidate(folderListProvider);
  }

  Future<void> addTracks(String folderId, List<String> trackPaths) async {
    await _repository.addTracks(folderId, trackPaths);
    _bumpLinks();
  }

  Future<void> removeTrack(String folderId, String trackPath) async {
    await _repository.removeTrack(folderId, trackPath);
    _bumpLinks();
  }

  Future<void> reorder(String folderId, List<String> orderedPaths) async {
    await _repository.reorder(folderId, orderedPaths);
    _bumpLinks();
  }

  Future<void> toggleFavorite(String trackPath) async {
    await _repository.toggleFavorite(trackPath);
    _bumpLinks();
  }

  /// Lets other features (e.g. cleanup in Settings) tell the folder views
  /// that links changed underneath them.
  void notifyLinksChanged() {
    _ref.invalidate(folderListProvider);
    _bumpLinks();
  }

  void _bumpLinks() => _ref.read(folderLinksTickProvider.notifier).bump();
}

final folderActionsProvider = Provider<FolderActions>((ref) => FolderActions(ref));
