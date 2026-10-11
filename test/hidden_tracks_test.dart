import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:music_player/data/hive/hive_setup.dart';
import 'package:music_player/data/repositories/hidden_tracks_repository.dart';
import 'package:music_player/domain/backup_path_resolver.dart';
import 'package:music_player/features/library/providers/library_providers.dart';

/// Hiding is the one Library action that outlives the app run without touching
/// a file, so what matters is that it survives a restart, that it is a
/// complete undo, and that it holds up for the long non-ASCII paths this
/// library is actually full of.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hidden_tracks_test');
    Hive.init(directory.path);
    await Hive.openBox<String>(HiveBoxes.hiddenTracks);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  HiddenTracksNotifier notifierIn(ProviderContainer container) =>
      container.read(hiddenTracksProvider.notifier);

  ProviderContainer freshContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('starts with nothing hidden', () {
    expect(freshContainer().read(hiddenTracksProvider), isEmpty);
  });

  test('hides a batch and survives a restart', () async {
    await notifierIn(freshContainer()).hide(['/music/a.mp3', '/music/b.mp3']);

    // A second container reads the box back the way a fresh launch would.
    expect(
      freshContainer().read(hiddenTracksProvider),
      {'/music/a.mp3', '/music/b.mp3'},
    );
  });

  test('unhiding restores exactly what was asked for', () async {
    final container = freshContainer();
    await notifierIn(container).hide(['/music/a.mp3', '/music/b.mp3']);
    await notifierIn(container).unhide(['/music/a.mp3']);

    expect(container.read(hiddenTracksProvider), {'/music/b.mp3'});
    expect(freshContainer().read(hiddenTracksProvider), {'/music/b.mp3'});
  });

  test('restore all empties the box', () async {
    final container = freshContainer();
    await notifierIn(container).hide(['/music/a.mp3', '/music/b.mp3']);
    await notifierIn(container).unhideAll();

    expect(container.read(hiddenTracksProvider), isEmpty);
    expect(freshContainer().read(hiddenTracksProvider), isEmpty);
  });

  test('hiding the same file twice leaves one entry', () async {
    final container = freshContainer();
    await notifierIn(container).hide(['/music/a.mp3']);
    await notifierIn(container).hide(['/music/a.mp3']);

    expect(container.read(hiddenTracksProvider), {'/music/a.mp3'});
    expect(Hive.box<String>(HiveBoxes.hiddenTracks).length, 1);
  });

  test('hiding nothing writes nothing', () async {
    await notifierIn(freshContainer()).hide(const []);
    expect(Hive.box<String>(HiveBoxes.hiddenTracks).length, 0);
  });

  test('survives a path far past Hive\'s 255-byte key limit', () async {
    // The real failure this guards: these files come off YouTube, and a title
    // in Han characters costs three bytes a glyph, so a path long enough to
    // corrupt the box is an ordinary song rather than a contrived case.
    final long = '/storage/emulated/0/Music/${'歌' * 200}.mp3';
    // Hive measures the key in UTF-8 bytes, not UTF-16 units, and that gap is
    // the whole reason these paths overflow sooner than their length suggests.
    expect(utf8.encode(long).length, greaterThan(255));

    final container = freshContainer();
    await notifierIn(container).hide([long]);

    expect(freshContainer().read(hiddenTracksProvider), {long});

    await notifierIn(container).unhide([long]);
    expect(freshContainer().read(hiddenTracksProvider), isEmpty);
  });

  test('the repository reads back whatever the notifier wrote', () async {
    await notifierIn(freshContainer()).hide(['/music/a.mp3']);
    expect(HiddenTracksRepository().paths, {'/music/a.mp3'});
  });

  test('a restore hides what the backup had hidden, at the paths this device uses', () async {
    final repository = HiddenTracksRepository();

    final hidden = await repository.importHidden(
      const ['/old-phone/Music/skip-me.mp3'],
      resolver: BackupPathResolver(const ['/storage/emulated/0/Music/skip-me.mp3']),
    );

    expect(hidden, 1);
    expect(repository.paths, {'/storage/emulated/0/Music/skip-me.mp3'});
  });

  test('a restore never unhides, and adds nothing the second time', () async {
    final repository = HiddenTracksRepository();
    await repository.hide(['/music/a.mp3', '/music/kept.mp3']);

    final first = await repository.importHidden(const ['/music/a.mp3', '/music/b.mp3']);
    final second = await repository.importHidden(const ['/music/a.mp3', '/music/b.mp3']);

    expect(first, 1, reason: 'only b.mp3 was missing');
    expect(second, 0);
    // The backup said nothing about kept.mp3, and a restore only ever adds.
    expect(repository.paths, {'/music/a.mp3', '/music/b.mp3', '/music/kept.mp3'});
  });
}
