import 'package:hive/hive.dart';

import '../../domain/backup_path_resolver.dart';
import '../hive/box_keys.dart';
import '../hive/hive_setup.dart';

/// The files the user has told the Library not to list.
///
/// Hiding is deliberately not deleting. The premise of this app is that
/// organizing music never touches the user's files, so a track they are tired
/// of scrolling past is dropped from one view and nothing else: the file stays
/// on the device, and every playlist link, favorite and history entry pointing
/// at it survives. That is what makes unhiding a complete undo instead of a
/// partial one, and it is why this is reversible from Settings rather than
/// guarded by a confirmation dialog.
class HiddenTracksRepository {
  /// The value is the real path; the key is a digest of it, because a path
  /// over 255 bytes used directly as a Hive key silently corrupts the box —
  /// see [trackKey]. This box has been digest-keyed since it was added, so
  /// unlike the older path-keyed boxes there is nothing here for
  /// `key_migration.dart` to rewrite.
  Box<String> get _box => Hive.box<String>(HiveBoxes.hiddenTracks);

  Set<String> get paths => _box.values.toSet();

  Future<void> hide(Iterable<String> paths) async {
    final entries = {for (final path in paths) trackKey(path): path};
    if (entries.isEmpty) return;
    await _box.putAll(entries);
  }

  Future<void> unhide(Iterable<String> paths) async {
    final keys = [for (final path in paths) trackKey(path)];
    if (keys.isEmpty) return;
    await _box.deleteAll(keys);
  }

  Future<void> unhideAll() => _box.clear();

  /// Hides what a backup had hidden, reporting how many rows that newly took
  /// out of the Library.
  ///
  /// Additive like every other part of a restore: a track the user has since
  /// unhidden on this device is hidden again, but nothing is ever unhidden
  /// here — a restore must not put back a row the user has already dealt with.
  Future<int> importHidden(Iterable<String> paths, {BackupPathResolver? resolver}) async {
    final resolve = resolver ?? BackupPathResolver.none();
    final existing = _box.keys.toSet();
    final entries = <String, String>{};

    for (final path in paths) {
      final resolved = resolve.resolve(path).path;
      final key = trackKey(resolved);
      if (existing.contains(key)) continue;
      entries[key] = resolved;
    }

    if (entries.isEmpty) return 0;
    await _box.putAll(entries);
    return entries.length;
  }
}
