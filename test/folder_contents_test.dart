import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:music_player/data/hive/hive_setup.dart';
import 'package:music_player/data/hive/models/folder_model.dart';
import 'package:music_player/data/hive/models/folder_track_link.dart';
import 'package:music_player/data/repositories/folder_repository.dart';
import 'package:music_player/domain/folder_sort_mode.dart';
import 'package:music_player/domain/track.dart';
import 'package:music_player/features/folders/providers/folder_providers.dart';
import 'package:music_player/features/library/providers/library_providers.dart';

/// A scan with a fixed result, so a folder's links can be checked against a
/// library that deliberately does not contain all of them.
class _StubScan extends LibraryScanNotifier {
  _StubScan(this.tracks);

  final List<Track> tracks;

  @override
  Future<List<Track>> build() async => tracks;
}

Track track(String path, {String title = 'Title'}) => Track(
      id: path.hashCode,
      title: title,
      artist: 'Artist',
      album: 'Album',
      path: path,
      duration: const Duration(minutes: 3),
      dateAdded: DateTime.utc(2026, 10, 1),
      format: 'MP3',
    );

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('folder_contents_test');
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

  Future<ProviderContainer> containerWith(List<Track> scanned) async {
    final container = ProviderContainer(
      overrides: [libraryScanProvider.overrideWith(() => _StubScan(scanned))],
    );
    addTearDown(container.dispose);
    await container.read(libraryScanProvider.future);
    return container;
  }

  test('reports links the scan could not match instead of dropping them', () async {
    final repository = FolderRepository()..ensureSystemFolders();
    final folder = await repository.createFolder('Night drive');
    await repository.addTracks(folder.id, ['/a.mp3', '/gone.mp3', '/b.mp3']);

    final container = await containerWith([track('/a.mp3'), track('/b.mp3')]);
    final contents = container.read(folderTracksProvider(folder.id)).value!;

    expect(contents.tracks.map((t) => t.path), ['/a.mp3', '/b.mp3']);
    expect(contents.unavailablePaths, ['/gone.mp3']);
    expect(contents.hasUnavailable, isTrue);
    expect(contents.linkCount, 3, reason: 'the folder still holds three entries');
  });

  test('a folder whose files are all missing is not the same as an empty one', () async {
    final repository = FolderRepository()..ensureSystemFolders();
    final empty = await repository.createFolder('Empty');
    final orphaned = await repository.createFolder('Orphaned');
    await repository.addTracks(orphaned.id, ['/gone.mp3', '/also-gone.mp3']);

    final container = await containerWith([track('/a.mp3')]);

    final emptyContents = container.read(folderTracksProvider(empty.id)).value!;
    expect(emptyContents.linkCount, 0);
    expect(emptyContents.hasUnavailable, isFalse);

    final orphanedContents = container.read(folderTracksProvider(orphaned.id)).value!;
    expect(orphanedContents.tracks, isEmpty);
    expect(orphanedContents.hasUnavailable, isTrue);
    expect(orphanedContents.unavailablePaths, ['/gone.mp3', '/also-gone.mp3']);
  });

  test('keeps reporting unmatched links when the folder is sorted', () async {
    final repository = FolderRepository()..ensureSystemFolders();
    final folder = await repository.createFolder('Night drive');
    await repository.addTracks(folder.id, ['/z.mp3', '/gone.mp3', '/a.mp3']);
    await repository.setSortMode(folder.id, FolderSortMode.title.name);

    final container = await containerWith([
      track('/z.mp3', title: 'Zebra'),
      track('/a.mp3', title: 'Apple'),
    ]);
    final contents = container.read(folderTracksProvider(folder.id)).value!;

    expect(contents.tracks.map((t) => t.title), ['Apple', 'Zebra']);
    expect(contents.unavailablePaths, ['/gone.mp3']);
  });

  test('reversing a folder flips its custom order, which has no comparator', () async {
    final repository = FolderRepository()..ensureSystemFolders();
    final folder = await repository.createFolder('Night drive');
    await repository.addTracks(folder.id, ['/a.mp3', '/b.mp3', '/c.mp3']);
    await repository.setSortDescending(folder.id, true);

    final container = await containerWith([track('/a.mp3'), track('/b.mp3'), track('/c.mp3')]);
    final contents = container.read(folderTracksProvider(folder.id)).value!;

    expect(contents.tracks.map((t) => t.path), ['/c.mp3', '/b.mp3', '/a.mp3']);
  });

  test('reversing a sorted folder reads the sort back to front', () async {
    final repository = FolderRepository()..ensureSystemFolders();
    final folder = await repository.createFolder('Night drive');
    await repository.addTracks(folder.id, ['/z.mp3', '/gone.mp3', '/a.mp3']);
    await repository.setSortMode(folder.id, FolderSortMode.title.name);
    await repository.setSortDescending(folder.id, true);

    final container = await containerWith([
      track('/z.mp3', title: 'Zebra'),
      track('/a.mp3', title: 'Apple'),
    ]);
    final contents = container.read(folderTracksProvider(folder.id)).value!;

    expect(contents.tracks.map((t) => t.title), ['Zebra', 'Apple']);
    expect(
      contents.unavailablePaths,
      ['/gone.mp3'],
      reason: 'reversing what is shown does not lose what could not be found',
    );
  });

  test('toggling the direction updates a folder the screen is already watching', () async {
    final repository = FolderRepository()..ensureSystemFolders();
    final folder = await repository.createFolder('Night drive');
    await repository.addTracks(folder.id, ['/a.mp3', '/b.mp3', '/c.mp3']);

    final container = await containerWith([track('/a.mp3'), track('/b.mp3'), track('/c.mp3')]);
    // Listened to, not just read: the screen holds a subscription the whole
    // time, so the provider stays alive and a stale cache stays on screen.
    container.listen(folderTracksProvider(folder.id), (_, _) {});
    expect(
      container.read(folderTracksProvider(folder.id)).value!.tracks.map((t) => t.path),
      ['/a.mp3', '/b.mp3', '/c.mp3'],
    );

    await container.read(folderActionsProvider).setSortDescending(folder.id, true);

    expect(
      container.read(folderTracksProvider(folder.id)).value!.tracks.map((t) => t.path),
      ['/c.mp3', '/b.mp3', '/a.mp3'],
    );
  });

  test('switching sort mode updates a folder the screen is already watching', () async {
    final repository = FolderRepository()..ensureSystemFolders();
    final folder = await repository.createFolder('Night drive');
    await repository.addTracks(folder.id, ['/z.mp3', '/a.mp3']);

    final container = await containerWith([
      track('/z.mp3', title: 'Zebra'),
      track('/a.mp3', title: 'Apple'),
    ]);
    container.listen(folderTracksProvider(folder.id), (_, _) {});
    expect(
      container.read(folderTracksProvider(folder.id)).value!.tracks.map((t) => t.title),
      ['Zebra', 'Apple'],
    );

    await container.read(folderActionsProvider).setSortMode(folder.id, FolderSortMode.title);

    expect(
      container.read(folderTracksProvider(folder.id)).value!.tracks.map((t) => t.title),
      ['Apple', 'Zebra'],
    );
  });
}
