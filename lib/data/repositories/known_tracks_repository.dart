import 'package:hive/hive.dart';

import '../../domain/app_backup.dart';
import '../../domain/backup_path_resolver.dart';
import '../hive/box_keys.dart';
import '../hive/hive_setup.dart';
import '../hive/models/known_track_record.dart';

/// Result of reconciling a fresh scan against what the app had seen before.
class ScanDiff {
  const ScanDiff({required this.newPaths, required this.missingPaths});

  const ScanDiff.empty() : newPaths = const {}, missingPaths = const {};

  /// Files seen for the first time. Empty on the very first scan — the whole
  /// library isn't "new", it's just the starting point.
  final Set<String> newPaths;

  /// Files known from an earlier scan that have since disappeared.
  final Set<String> missingPaths;
}

/// Tracks which files the app has already seen, so it can point out new
/// arrivals and flag records left behind by deleted files.
class KnownTracksRepository {
  Box<KnownTrackRecord> get _box => Hive.box<KnownTrackRecord>(HiveBoxes.knownTracks);

  /// Records the paths a scan turned up and reports what changed.
  Future<ScanDiff> reconcile(Map<String, int> scannedPathsToIds) async {
    final now = DateTime.now();
    final isFirstScan = _box.isEmpty;
    final scannedPaths = scannedPathsToIds.keys.toSet();

    // Everything that actually changed, written in one batch. Writing per
    // track meant one disk write per song on every scan, which stalls badly
    // on a real library.
    final pending = <String, KnownTrackRecord>{};
    final newPaths = <String>{};

    for (final entry in scannedPathsToIds.entries) {
      final key = trackKey(entry.key);
      final existing = _box.get(key);

      if (existing == null) {
        if (!isFirstScan) newPaths.add(entry.key);
        pending[key] = KnownTrackRecord(
          path: entry.key,
          mediaStoreId: entry.value,
          firstSeenAt: now,
          lastSeenAt: now,
          // Nothing to announce about a library the user already had.
          acknowledged: isFirstScan,
        );
        continue;
      }

      // Only rewrite when something meaningful moved. An unchanged library
      // should cost zero writes.
      if (existing.mediaStoreId == entry.value && !existing.missing) continue;

      pending[key] = KnownTrackRecord(
        path: existing.path,
        mediaStoreId: entry.value,
        firstSeenAt: existing.firstSeenAt,
        lastSeenAt: now,
        acknowledged: existing.acknowledged,
        missing: false,
      );
    }

    final missingPaths = <String>{};
    for (final record in _box.values) {
      if (scannedPaths.contains(record.path)) continue;
      missingPaths.add(record.path);
      if (record.missing) continue;

      pending[trackKey(record.path)] = KnownTrackRecord(
        path: record.path,
        mediaStoreId: record.mediaStoreId,
        firstSeenAt: record.firstSeenAt,
        lastSeenAt: record.lastSeenAt,
        acknowledged: record.acknowledged,
        missing: true,
      );
    }

    if (pending.isNotEmpty) await _box.putAll(pending);

    return ScanDiff(newPaths: newPaths, missingPaths: missingPaths);
  }

  /// Paths the user hasn't acknowledged yet, newest arrivals first.
  List<String> unacknowledgedPaths() {
    final records = _box.values.where((r) => !r.acknowledged && !r.missing).toList()
      ..sort((a, b) => b.firstSeenAt.compareTo(a.firstSeenAt));
    return records.map((record) => record.path).toList();
  }

  Set<String> missingPaths() =>
      _box.values.where((record) => record.missing).map((record) => record.path).toSet();

  Future<void> acknowledge(Iterable<String> paths) =>
      _markAcknowledged(paths.map((path) => _box.get(trackKey(path))).whereType<KnownTrackRecord>());

  Future<void> acknowledgeAll() => _markAcknowledged(_box.values);

  Future<void> _markAcknowledged(Iterable<KnownTrackRecord> records) async {
    final pending = <String, KnownTrackRecord>{};
    for (final record in records) {
      if (record.acknowledged) continue;
      pending[trackKey(record.path)] = KnownTrackRecord(
        path: record.path,
        mediaStoreId: record.mediaStoreId,
        firstSeenAt: record.firstSeenAt,
        lastSeenAt: record.lastSeenAt,
        acknowledged: true,
        missing: record.missing,
      );
    }
    if (pending.isNotEmpty) await _box.putAll(pending);
  }

  Future<void> forget(Iterable<String> paths) => _box.deleteAll(paths.map(trackKey));

  /// When each file was first seen, for a backup. Records for files that have
  /// gone missing are left out — there is nothing useful to carry about a file
  /// the other device will not have either.
  List<BackedUpKnownTrack> exportRecords() => [
        for (final record in _box.values)
          if (!record.missing)
            BackedUpKnownTrack(
              path: record.path,
              firstSeenAt: record.firstSeenAt,
              acknowledged: record.acknowledged,
            ),
      ];

  /// Merges a backup's first-seen dates into the records this device already
  /// has, and returns how many it changed.
  ///
  /// **Only existing records are updated, never created.** A record is this
  /// repository's claim that the file was on the device, and [reconcile] reads
  /// one with no matching file as "it vanished" — so inventing records from a
  /// backup would file every song the new phone does not have under
  /// Settings → Clean up missing files.
  ///
  /// The earlier [KnownTrackRecord.firstSeenAt] wins, because that is the date
  /// the "recently added" filter is about: a track copied onto a new phone
  /// today is not an arrival, it was in the library all along.
  Future<int> importRecords(
    Iterable<BackedUpKnownTrack> records, {
    BackupPathResolver? resolver,
  }) async {
    final resolve = resolver ?? BackupPathResolver.none();
    final pending = <String, KnownTrackRecord>{};

    for (final backedUp in records) {
      final path = resolve.resolve(backedUp.path).path;
      final key = trackKey(path);
      final existing = pending[key] ?? _box.get(key);
      if (existing == null) continue;

      final acknowledged = existing.acknowledged || backedUp.acknowledged;
      if (!existing.firstSeenAt.isAfter(backedUp.firstSeenAt) && existing.acknowledged == acknowledged) {
        continue;
      }

      pending[key] = KnownTrackRecord(
        path: existing.path,
        mediaStoreId: existing.mediaStoreId,
        firstSeenAt: existing.firstSeenAt.isAfter(backedUp.firstSeenAt) ? backedUp.firstSeenAt : existing.firstSeenAt,
        lastSeenAt: existing.lastSeenAt,
        acknowledged: acknowledged,
        missing: existing.missing,
      );
    }

    if (pending.isNotEmpty) await _box.putAll(pending);
    return pending.length;
  }
}
