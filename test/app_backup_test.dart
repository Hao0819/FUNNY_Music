import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/domain/app_backup.dart';
import 'package:music_player/domain/folder_backup.dart';

void main() {
  AppBackup sample() => AppBackup(
        createdAt: DateTime.utc(2026, 10, 11, 9, 30),
        folders: FolderBackup(
          createdAt: DateTime.utc(2026, 10, 11, 9, 30),
          folders: [
            BackedUpFolder(
              id: 'favorites',
              name: 'Favorites',
              createdAt: DateTime.utc(2026, 9, 1),
              isSystem: true,
              trackPaths: const ['/storage/emulated/0/Music/a.mp3'],
            ),
            BackedUpFolder(
              id: 'abc-123',
              name: '夜曲',
              createdAt: DateTime.utc(2026, 9, 2),
              sortMode: 'title',
              colorValue: 0xFF00897B,
              trackPaths: const ['/storage/emulated/0/Music/b.flac'],
            ),
          ],
        ),
        hiddenTrackPaths: const ['/storage/emulated/0/Music/skip-me.mp3'],
        playHistory: [
          BackedUpPlay(trackPath: '/storage/emulated/0/Music/a.mp3', playedAt: DateTime.utc(2026, 10, 10, 20)),
          BackedUpPlay(trackPath: '/storage/emulated/0/Music/a.mp3', playedAt: DateTime.utc(2026, 10, 11, 8)),
        ],
        knownTracks: [
          BackedUpKnownTrack(path: '/storage/emulated/0/Music/a.mp3', firstSeenAt: DateTime.utc(2025, 4, 2)),
        ],
        settings: const BackedUpSettings(
          themeMode: 'dark',
          librarySortField: 'dateAdded',
          librarySortAscending: false,
          repeatMode: 'one',
          downloadHistoryHidden: true,
          recentDownloadSearches: ['周杰伦'],
        ),
      );

  test('survives a round trip through its file format', () {
    final restored = AppBackup.decode(sample().encode());

    expect(restored.version, AppBackup.currentVersion);
    expect(restored.createdAt, DateTime.utc(2026, 10, 11, 9, 30));
    expect(restored.folderCount, 2);
    expect(restored.trackCount, 2);
    expect(restored.folders.folders[1].name, '夜曲');
    expect(restored.hiddenTrackPaths, ['/storage/emulated/0/Music/skip-me.mp3']);
    expect(restored.playHistory.length, 2);
    expect(restored.playHistory.first.playedAt, DateTime.utc(2026, 10, 10, 20));
    expect(restored.knownTracks.single.firstSeenAt, DateTime.utc(2025, 4, 2));
    expect(restored.settings?.themeMode, 'dark');
    expect(restored.settings?.librarySortAscending, isFalse);
    expect(restored.settings?.repeatMode, 'one');
    expect(restored.settings?.recentDownloadSearches, ['周杰伦']);
  });

  test('every path it references is reported for matching against the library', () {
    expect(sample().allTrackPaths, {
      '/storage/emulated/0/Music/a.mp3',
      '/storage/emulated/0/Music/b.flac',
      '/storage/emulated/0/Music/skip-me.mp3',
    });
  });

  test('a v1 file reads as a backup with the new sections empty', () {
    const v1 = '''
{
  "version": 1,
  "createdAt": "2026-10-06T15:30:00.000Z",
  "folders": [
    {"id": "abc-123", "name": "Night drive", "createdAt": "2026-09-02T00:00:00.000Z",
     "trackPaths": ["/storage/emulated/0/Music/b.flac"]}
  ]
}
''';

    final restored = AppBackup.decode(v1);

    expect(restored.version, 1);
    expect(restored.folders.folders.single.name, 'Night drive');
    expect(restored.hiddenTrackPaths, isEmpty);
    expect(restored.playHistory, isEmpty);
    expect(restored.knownTracks, isEmpty);
    expect(restored.settings, isNull);
  });

  test('a v2 file still reads as a v1 folder backup', () {
    // The property that lets an older build restore a backup written by a
    // newer one: the folders section never moves.
    final folders = FolderBackup.decode(sample().encode());

    expect(folders.folders.length, 2);
    expect(folders.trackCount, 2);
    expect(folders.folders[1].trackPaths, ['/storage/emulated/0/Music/b.flac']);
  });

  test('a play entry with no usable date is dropped, not fatal', () {
    final json = jsonDecode(sample().encode()) as Map<String, Object?>;
    json['playHistory'] = [
      {'path': '/a.mp3', 'playedAt': 'not a date'},
      {'path': '', 'playedAt': '2026-10-11T08:00:00.000Z'},
      {'path': '/b.mp3', 'playedAt': '2026-10-11T08:00:00.000Z'},
    ];

    final restored = AppBackup.decode(jsonEncode(json));

    expect(restored.playHistory.single.trackPath, '/b.mp3');
  });

  test('a known-track record defaults to acknowledged, so a restore announces nothing', () {
    final json = jsonDecode(sample().encode()) as Map<String, Object?>;
    json['knownTracks'] = [
      {'path': '/a.mp3', 'firstSeenAt': '2025-04-02T00:00:00.000Z'},
    ];

    expect(AppBackup.decode(jsonEncode(json)).knownTracks.single.acknowledged, isTrue);
  });

  test('anything that is not a backup is a FormatException, not a crash', () {
    expect(() => AppBackup.decode('nonsense'), throwsA(isA<FormatException>()));
    expect(() => AppBackup.decode('[]'), throwsA(isA<FormatException>()));
    expect(() => AppBackup.decode('{"version": 2}'), throwsA(isA<FormatException>()));
  });
}
