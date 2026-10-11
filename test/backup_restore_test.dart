import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:music_player/data/hive/hive_setup.dart';
import 'package:music_player/data/hive/models/known_track_record.dart';
import 'package:music_player/data/hive/models/play_history_entry.dart';
import 'package:music_player/data/repositories/history_repository.dart';
import 'package:music_player/data/repositories/known_tracks_repository.dart';
import 'package:music_player/domain/app_backup.dart';
import 'package:music_player/domain/backup_path_resolver.dart';

/// The boxes a restore writes to besides the folders: the play log, which is
/// the only source of "recently played", "most played" and every play count,
/// and the first-seen record behind the "recently added" filter.
///
/// Real boxes against a temporary directory — a restore is about what ends up
/// on disk, so a fake would prove nothing.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup_restore_test');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(KnownTrackRecordAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(PlayHistoryEntryAdapter());
    await Hive.openBox<KnownTrackRecord>(HiveBoxes.knownTracks);
    await Hive.openBox<PlayHistoryEntry>(HiveBoxes.playHistory);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  group('play log', () {
    test('round trips through a backup, play counts and all', () async {
      final repository = HistoryRepository();
      await repository.recordPlay('/music/a.mp3');
      await repository.recordPlay('/music/a.mp3');
      await repository.recordPlay('/music/b.mp3');

      final exported = repository.exportEntries();
      await repository.clear();
      final added = await repository.importEntries(exported);

      expect(added, 3);
      expect(repository.playCounts(), {'/music/a.mp3': 2, '/music/b.mp3': 1});
      expect(repository.mostPlayedPaths().first, '/music/a.mp3');
    });

    test('lands on the paths this device uses', () async {
      final added = await HistoryRepository().importEntries(
        [BackedUpPlay(trackPath: '/old-phone/a.mp3', playedAt: DateTime.utc(2026, 10, 10))],
        resolver: BackupPathResolver(const ['/storage/emulated/0/Music/a.mp3']),
      );

      expect(added, 1);
      expect(HistoryRepository().playCounts().keys, ['/storage/emulated/0/Music/a.mp3']);
    });

    test('importing the same backup twice does not double every play count', () async {
      final repository = HistoryRepository();
      final plays = [
        BackedUpPlay(trackPath: '/music/a.mp3', playedAt: DateTime.utc(2026, 10, 10, 20)),
        BackedUpPlay(trackPath: '/music/a.mp3', playedAt: DateTime.utc(2026, 10, 11, 8)),
      ];

      await repository.importEntries(plays);
      final second = await repository.importEntries(plays);

      expect(second, 0);
      expect(repository.playCounts(), {'/music/a.mp3': 2});
    });

    test('a full log keeps the newest plays, not the first ones written', () async {
      // An import appends entries that are older than what is already there,
      // so trimming by insertion order would throw away this device's most
      // recent listening to make room for the other phone's oldest.
      final repository = HistoryRepository();
      for (var i = 0; i < 500; i++) {
        await repository.recordPlay('/music/recent-$i.mp3');
      }

      await repository.importEntries([
        BackedUpPlay(trackPath: '/music/ancient.mp3', playedAt: DateTime.utc(2020)),
      ]);

      expect(Hive.box<PlayHistoryEntry>(HiveBoxes.playHistory).length, 500);
      expect(repository.playCounts().containsKey('/music/ancient.mp3'), isFalse);
      expect(repository.playCounts().containsKey('/music/recent-499.mp3'), isTrue);
    });
  });

  group('first-seen dates', () {
    Future<void> seed(String path, DateTime firstSeenAt) =>
        Hive.box<KnownTrackRecord>(HiveBoxes.knownTracks).put(
          'seeded-$path',
          KnownTrackRecord(
            path: path,
            mediaStoreId: 1,
            firstSeenAt: firstSeenAt,
            lastSeenAt: firstSeenAt,
            acknowledged: true,
          ),
        );

    test('the earlier date wins, so a migrated library is not all brand new', () async {
      final repository = KnownTracksRepository();
      // What the new phone's first scan recorded: everything seen today.
      await repository.reconcile({'/music/a.mp3': 1});

      final changed = await repository.importRecords([
        BackedUpKnownTrack(path: '/music/a.mp3', firstSeenAt: DateTime.utc(2025, 4, 2)),
      ]);

      expect(changed, 1);
      expect(repository.exportRecords().single.firstSeenAt, DateTime.utc(2025, 4, 2));
    });

    test('a later date is ignored rather than aging a record forward', () async {
      await seed('/music/a.mp3', DateTime.utc(2025));

      final changed = await KnownTracksRepository().importRecords([
        BackedUpKnownTrack(path: '/music/a.mp3', firstSeenAt: DateTime.utc(2026)),
      ]);

      expect(changed, 0);
      expect(KnownTracksRepository().exportRecords().single.firstSeenAt, DateTime.utc(2025));
    });

    test('a file this device does not have gets no record invented for it', () async {
      // A record with no file behind it reads as "it vanished", which would
      // file the other phone's whole library under Clean up missing files.
      final changed = await KnownTracksRepository().importRecords([
        BackedUpKnownTrack(path: '/music/not-here.mp3', firstSeenAt: DateTime.utc(2025)),
      ]);

      expect(changed, 0);
      expect(KnownTracksRepository().missingPaths(), isEmpty);
      expect(KnownTracksRepository().exportRecords(), isEmpty);
    });
  });
}
