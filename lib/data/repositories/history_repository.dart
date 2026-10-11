import 'package:hive/hive.dart';

import '../../domain/app_backup.dart';
import '../../domain/backup_path_resolver.dart';
import '../hive/hive_setup.dart';
import '../hive/models/play_history_entry.dart';

/// Append-only play log. "Recently played" and "most played" are both derived
/// by reading this back, so there's no separate counter to keep in sync.
class HistoryRepository {
  static const _maxEntries = 500;

  Box<PlayHistoryEntry> get _box => Hive.box<PlayHistoryEntry>(HiveBoxes.playHistory);

  Future<void> recordPlay(String trackPath) async {
    await _box.add(PlayHistoryEntry(trackPath: trackPath, playedAt: DateTime.now()));
    await _trim();
  }

  Set<String> recentlyPlayedPaths({required Duration within}) {
    final cutoff = DateTime.now().subtract(within);
    return _box.values.where((entry) => entry.playedAt.isAfter(cutoff)).map((entry) => entry.trackPath).toSet();
  }

  /// Distinct track paths, most recently played first.
  List<String> recentPaths({int limit = 50}) {
    final entries = _box.values.toList()..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final seen = <String>{};
    for (final entry in entries) {
      seen.add(entry.trackPath);
      if (seen.length >= limit) break;
    }
    return seen.toList();
  }

  List<String> mostPlayedPaths({int limit = 50}) {
    final sorted = playCounts().entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((entry) => entry.key).toList();
  }

  /// How many times each track has been played, across the whole log.
  Map<String, int> playCounts() {
    final counts = <String, int>{};
    for (final entry in _box.values) {
      counts[entry.trackPath] = (counts[entry.trackPath] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> clear() => _box.clear();

  int countEntriesFor(Set<String> paths) =>
      _box.values.where((entry) => paths.contains(entry.trackPath)).length;

  Future<void> removeEntriesFor(Set<String> paths) async {
    final keys = <dynamic>[];
    for (final key in _box.keys) {
      final entry = _box.get(key);
      if (entry != null && paths.contains(entry.trackPath)) keys.add(key);
    }
    await _box.deleteAll(keys);
  }

  /// The whole log, for a backup. Play counts are not exported as counts: they
  /// are derived from this, and sending the entries keeps "recently played"
  /// working on the other device too.
  List<BackedUpPlay> exportEntries() =>
      [for (final entry in _box.values) BackedUpPlay(trackPath: entry.trackPath, playedAt: entry.playedAt)];

  /// Appends a backup's entries, skipping any already in the log, and returns
  /// how many were added.
  ///
  /// Identity is the path and the timestamp together, which is what makes
  /// importing the same backup twice add nothing: two plays of one track a
  /// millisecond apart are not a thing a person can produce.
  Future<int> importEntries(Iterable<BackedUpPlay> plays, {BackupPathResolver? resolver}) async {
    final resolve = resolver ?? BackupPathResolver.none();
    final existing = {for (final entry in _box.values) _identity(entry.trackPath, entry.playedAt)};

    final additions = <PlayHistoryEntry>[];
    for (final play in plays) {
      final path = resolve.resolve(play.trackPath).path;
      if (!existing.add(_identity(path, play.playedAt))) continue;
      additions.add(PlayHistoryEntry(trackPath: path, playedAt: play.playedAt));
    }

    if (additions.isEmpty) return 0;
    await _box.addAll(additions);
    await _trim();
    return additions.length;
  }

  String _identity(String path, DateTime playedAt) => '$path|${playedAt.toIso8601String()}';

  /// Keeps the newest [_maxEntries] by timestamp rather than by insertion
  /// order: an import appends plays that are older than what is already in the
  /// box, so dropping the first-inserted keys would throw away the device's
  /// most recent listening.
  Future<void> _trim() async {
    if (_box.length <= _maxEntries) return;

    final keys = _box.keys.toList()
      ..sort((a, b) {
        final left = _box.get(a)?.playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = _box.get(b)?.playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
    await _box.deleteAll(keys.skip(_maxEntries));
  }
}
