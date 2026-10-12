import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/domain/folder_backup.dart';

void main() {
  FolderBackup sample() => FolderBackup(
        createdAt: DateTime.utc(2026, 10, 6, 15, 30),
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
            sortDescending: true,
            colorValue: 0xFF00897B,
            trackPaths: const [
              '/storage/emulated/0/Music/b.flac',
              '/storage/emulated/0/Music/c.m4a',
            ],
          ),
        ],
      );

  test('survives a round trip through its file format', () {
    final restored = FolderBackup.decode(sample().encode());

    expect(restored.version, FolderBackup.currentVersion);
    expect(restored.createdAt, DateTime.utc(2026, 10, 6, 15, 30));
    expect(restored.folders.length, 2);
    expect(restored.trackCount, 3);

    final folder = restored.folders[1];
    expect(folder.id, 'abc-123');
    expect(folder.name, '夜曲');
    expect(folder.isSystem, isFalse);
    expect(folder.sortMode, 'title');
    expect(folder.sortDescending, isTrue);
    expect(folder.colorValue, 0xFF00897B);
    expect(folder.trackPaths, [
      '/storage/emulated/0/Music/b.flac',
      '/storage/emulated/0/Music/c.m4a',
    ]);
  });

  test('keeps the path order it was given, since folders have a manual order', () {
    final paths = ['/z.mp3', '/a.mp3', '/m.mp3'];
    final restored = FolderBackup.decode(
      FolderBackup(
        createdAt: DateTime.utc(2026, 10, 6),
        folders: [
          BackedUpFolder(id: 'f', name: 'F', createdAt: DateTime.utc(2026, 10, 6), trackPaths: paths),
        ],
      ).encode(),
    );

    expect(restored.folders.single.trackPaths, paths);
  });

  group('reading a file the user picked', () {
    test('rejects something that is not a backup at all', () {
      expect(() => FolderBackup.decode('[]'), throwsFormatException);
      expect(() => FolderBackup.decode('{"hello": "world"}'), throwsFormatException);
      expect(() => FolderBackup.decode('not json'), throwsA(isA<FormatException>()));
    });

    test('rejects a folder with no name, which would restore as unidentifiable', () {
      final json = jsonEncode({
        'version': 1,
        'createdAt': '2026-10-06T00:00:00.000Z',
        'folders': [
          {'id': 'x', 'trackPaths': <String>[]},
        ],
      });

      expect(() => FolderBackup.decode(json), throwsFormatException);
    });

    test('drops unusable paths instead of rejecting the whole file', () {
      final json = jsonEncode({
        'createdAt': '2026-10-06T00:00:00.000Z',
        'folders': [
          {
            'id': 'x',
            'name': 'Mixed',
            'trackPaths': ['/good.mp3', '', 42, null, '/also-good.mp3'],
          },
        ],
      });

      final restored = FolderBackup.decode(json);
      expect(restored.folders.single.trackPaths, ['/good.mp3', '/also-good.mp3']);
    });

    test('tolerates a missing date and missing optional fields', () {
      final json = jsonEncode({
        'folders': [
          {'name': 'Bare', 'trackPaths': <String>[]},
        ],
      });

      final restored = FolderBackup.decode(json);
      final folder = restored.folders.single;
      expect(folder.id, isEmpty);
      expect(folder.sortMode, 'manual');
      expect(folder.sortDescending, isFalse);
      expect(folder.colorValue, isNull);
      expect(folder.isSystem, isFalse);
      expect(restored.createdAt.millisecondsSinceEpoch, 0);
    });
  });
}
