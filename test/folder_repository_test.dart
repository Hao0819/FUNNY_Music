import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:music_player/data/hive/hive_setup.dart';
import 'package:music_player/data/hive/models/folder_model.dart';
import 'package:music_player/data/hive/models/folder_track_link.dart';
import 'package:music_player/data/repositories/folder_repository.dart';
import 'package:music_player/domain/backup_path_resolver.dart';
import 'package:music_player/domain/folder_backup.dart';

/// Exercises the real boxes against a temporary directory — the import path
/// is about what ends up on disk, so a fake would prove nothing.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('folder_repository_test');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(FolderModelAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(FolderTrackLinkAdapter());
    await Hive.openBox<FolderModel>(HiveBoxes.folders);
    await Hive.openBox<FolderTrackLink>(HiveBoxes.folderTrackLinks);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  FolderRepository repository() => FolderRepository()..ensureSystemFolders();

  test('exports folders with their tracks in manual order', () async {
    final repo = repository();
    final folder = await repo.createFolder('Night drive', colorValue: 0xFF00897B);
    await repo.addTracks(folder.id, ['/a.mp3', '/b.mp3', '/c.mp3']);
    await repo.toggleFavorite('/b.mp3');

    final backup = repo.exportBackup();

    expect(backup.folders.first.isSystem, isTrue, reason: 'Favorites sorts first');
    expect(backup.folders.first.trackPaths, ['/b.mp3']);

    final exported = backup.folders.firstWhere((entry) => entry.name == 'Night drive');
    expect(exported.id, folder.id);
    expect(exported.colorValue, 0xFF00897B);
    expect(exported.trackPaths, ['/a.mp3', '/b.mp3', '/c.mp3']);
    expect(backup.trackCount, 4);
  });

  test('restores folders and links that are gone', () async {
    final repo = repository();
    final folder = await repo.createFolder('Night drive');
    await repo.addTracks(folder.id, ['/a.mp3', '/b.mp3']);
    await repo.toggleFavorite('/a.mp3');
    final backup = repo.exportBackup();

    // Stand in for the failure this exists for: the links box replaced by an
    // empty one, with the folders box intact.
    await Hive.box<FolderTrackLink>(HiveBoxes.folderTrackLinks).clear();
    await Hive.box<FolderModel>(HiveBoxes.folders).delete(folder.id);
    expect(repo.getTrackPaths(folder.id), isEmpty);

    final summary = await repo.importBackup(backup);

    expect(summary.foldersCreated, 1);
    expect(summary.linksAdded, 3);
    expect(repo.getFolder(folder.id)?.name, 'Night drive');
    expect(repo.getTrackPaths(folder.id), ['/a.mp3', '/b.mp3']);
    expect(repo.isFavorite('/a.mp3'), isTrue);
  });

  test('restoring the same backup twice changes nothing the second time', () async {
    final repo = repository();
    final folder = await repo.createFolder('Night drive');
    await repo.addTracks(folder.id, ['/a.mp3', '/b.mp3']);
    final backup = repo.exportBackup();

    await Hive.box<FolderTrackLink>(HiveBoxes.folderTrackLinks).clear();
    await repo.importBackup(backup);
    final second = await repo.importBackup(backup);

    expect(second.changedNothing, isTrue);
    expect(repo.getTrackPaths(folder.id), ['/a.mp3', '/b.mp3']);
  });

  test('never removes or renames what is already there', () async {
    final repo = repository();
    final folder = await repo.createFolder('Night drive');
    await repo.addTracks(folder.id, ['/a.mp3']);
    final backup = repo.exportBackup();

    await repo.editFolder(folder.id, 'Renamed since');
    await repo.addTracks(folder.id, ['/added-later.mp3']);

    final summary = await repo.importBackup(backup);

    expect(summary.changedNothing, isTrue);
    expect(repo.getFolder(folder.id)?.name, 'Renamed since');
    expect(repo.getTrackPaths(folder.id), ['/a.mp3', '/added-later.mp3']);
  });

  test('matches a backed-up Favorites to this device\'s Favorites by kind', () async {
    final repo = repository();
    await repo.toggleFavorite('/a.mp3');

    // A backup from an install where Favorites had been created under some
    // other id still has to land in the Favorites folder here.
    final transplanted = FolderBackup(
      createdAt: DateTime.utc(2026, 10, 6),
      folders: [
        BackedUpFolder(
          id: 'some-other-id',
          name: 'Favorites',
          createdAt: DateTime.utc(2026, 9, 1),
          isSystem: true,
          trackPaths: const ['/b.mp3'],
        ),
      ],
    );

    final summary = await repo.importBackup(transplanted);

    expect(summary.foldersCreated, 0);
    expect(repo.getFolder('some-other-id'), isNull);
    expect(repo.getTrackPaths(favoritesFolderId), ['/a.mp3', '/b.mp3']);
  });

  test('skips an entry with no id rather than inventing one', () async {
    final repo = repository();

    final summary = await repo.importBackup(
      FolderBackup(
        createdAt: DateTime.utc(2026, 10, 6),
        folders: [
          BackedUpFolder(
            id: '',
            name: 'Nameless id',
            createdAt: DateTime.utc(2026, 9, 1),
            trackPaths: const ['/a.mp3'],
          ),
        ],
      ),
    );

    expect(summary.changedNothing, isTrue);
    expect(repo.getAllFolders().where((folder) => !folder.isSystem), isEmpty);
  });

  test('a backup from another phone relinks to the files this one has', () async {
    final repo = repository();
    final folder = await repo.createFolder('Night drive');
    await repo.addTracks(folder.id, [
      '/storage/emulated/0/Music/a.mp3',
      '/storage/emulated/0/Music/b.mp3',
    ]);
    final backup = repo.exportBackup();

    await Hive.box<FolderTrackLink>(HiveBoxes.folderTrackLinks).clear();

    // The new device has the same songs under a different volume id, which is
    // what copying a library to a phone with an SD card looks like.
    final summary = await repo.importBackup(
      backup,
      resolver: BackupPathResolver(const [
        '/storage/1A2B-3C4D/Music/a.mp3',
        '/storage/1A2B-3C4D/Music/b.mp3',
      ]),
    );

    expect(summary.linksAdded, 2);
    expect(summary.linksRemapped, 2);
    expect(summary.linksUnresolved, 0);
    expect(repo.getTrackPaths(folder.id), [
      '/storage/1A2B-3C4D/Music/a.mp3',
      '/storage/1A2B-3C4D/Music/b.mp3',
    ]);
  });

  test('a track the new device does not have keeps its path and is counted', () async {
    final repo = repository();
    final folder = await repo.createFolder('Night drive');
    await repo.addTracks(folder.id, ['/old/a.mp3', '/old/missing.mp3']);
    final backup = repo.exportBackup();

    await Hive.box<FolderTrackLink>(HiveBoxes.folderTrackLinks).clear();

    final summary = await repo.importBackup(
      backup,
      resolver: BackupPathResolver(const ['/new/a.mp3']),
    );

    expect(summary.linksAdded, 2);
    expect(summary.linksRemapped, 1);
    expect(summary.linksUnresolved, 1);
    // Kept, not dropped: the link comes back on its own if the file turns up.
    expect(repo.getTrackPaths(folder.id), ['/new/a.mp3', '/old/missing.mp3']);
  });

  test('a relinked backup imported twice reports nothing the second time', () async {
    final repo = repository();
    final folder = await repo.createFolder('Night drive');
    await repo.addTracks(folder.id, ['/old/a.mp3']);
    final backup = repo.exportBackup();

    await Hive.box<FolderTrackLink>(HiveBoxes.folderTrackLinks).clear();
    final resolver = BackupPathResolver(const ['/new/a.mp3']);

    await repo.importBackup(backup, resolver: resolver);
    final second = await repo.importBackup(backup, resolver: resolver);

    expect(second.changedNothing, isTrue);
    expect(second.linksRemapped, 0, reason: 'the counts describe what this restore added');
    expect(repo.getTrackPaths(folder.id), ['/new/a.mp3']);
  });
}
