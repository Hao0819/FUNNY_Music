import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/data/repositories/audio_library_repository.dart';
import 'package:music_player/data/repositories/known_tracks_repository.dart';
import 'package:music_player/domain/track.dart';
import 'package:music_player/features/library/providers/library_providers.dart';
import 'package:music_player/services/scanning/media_store_scanner.dart';
import 'package:on_audio_query/on_audio_query.dart';

Track track(String path, {String title = 'Title', int id = 1, String artist = 'Artist'}) => Track(
      id: id,
      title: title,
      artist: artist,
      album: 'Album',
      path: path,
      duration: const Duration(minutes: 3),
      dateAdded: DateTime.utc(2026, 10, 1),
      format: 'MP3',
    );

/// Hands out pre-built scans so a test controls exactly when each pass lands.
/// The superclass's two query objects are never reached, since [startScan] is
/// the only entry point the notifier uses.
class _StubLibrary extends AudioLibraryRepository {
  _StubLibrary() : super(OnAudioQuery(), MediaStoreScanner());

  final List<LibraryScan> _queued = [];
  int startCount = 0;

  void queue(LibraryScan scan) => _queued.add(scan);

  @override
  LibraryScan startScan() {
    startCount++;
    return _queued.removeAt(0);
  }
}

class _RecordingKnownTracks extends KnownTracksRepository {
  final List<Set<String>> reconciled = [];

  @override
  Future<ScanDiff> reconcile(Map<String, int> scannedPathsToIds) async {
    reconciled.add(scannedPathsToIds.keys.toSet());
    return const ScanDiff.empty();
  }
}

class _PermissionDeniedQuery extends OnAudioQuery {
  @override
  Future<List<SongModel>> querySongs({
    SongSortType? sortType,
    OrderType? orderType,
    UriType? uriType,
    bool? ignoreCase,
    String? path,
  }) async {
    throw PlatformException(code: 'MissingPermissions');
  }
}

class _NativeLibrary extends MediaStoreScanner {
  @override
  Future<List<Track>> queryAudioFiles() async => [track('/song.mp3')];
}

void main() {
  test('uses the native library when the plugin rejects audio access', () async {
    final scan = AudioLibraryRepository(
      _PermissionDeniedQuery(),
      _NativeLibrary(),
    ).startScan();

    expect((await scan.firstPass).single.path, '/song.mp3');
    expect(await scan.complete, isNull);
  });

  late _StubLibrary library;
  late _RecordingKnownTracks known;

  setUp(() {
    library = _StubLibrary();
    known = _RecordingKnownTracks();
  });

  ProviderContainer containerWithStubs() {
    final container = ProviderContainer(
      overrides: [
        audioLibraryRepositoryProvider.overrideWithValue(library),
        knownTracksRepositoryProvider.overrideWithValue(known),
      ],
    );
    addTearDown(container.dispose);
    // Keeps the provider alive between reads, since it disposes once nothing
    // is listening.
    container.listen(libraryScanProvider, (_, _) {});
    return container;
  }

  test('paints the plugin rows without waiting for the broader pass', () async {
    final slowPass = Completer<List<Track>?>();
    library.queue(LibraryScan(
      firstPass: Future.value([track('/a.mp3')]),
      complete: slowPass.future,
    ));

    final container = containerWithStubs();
    final shown = await container.read(libraryScanProvider.future);

    expect(shown.map((t) => t.path), ['/a.mp3']);
    expect(slowPass.isCompleted, isFalse, reason: 'the second pass is still running');
  });

  test('merges the broader pass when it finds files the plugin missed', () async {
    final slowPass = Completer<List<Track>?>();
    library.queue(LibraryScan(
      firstPass: Future.value([track('/a.mp3')]),
      complete: slowPass.future,
    ));

    final container = containerWithStubs();
    await container.read(libraryScanProvider.future);

    slowPass.complete([track('/a.mp3'), track('/downloaded.opus', id: 2)]);
    await pumpEventQueue();

    expect(
      container.read(libraryScanProvider).value?.map((t) => t.path),
      ['/a.mp3', '/downloaded.opus'],
    );
  });

  test('leaves the list untouched when the broader pass adds nothing', () async {
    library.queue(LibraryScan(
      firstPass: Future.value([track('/a.mp3')]),
      // Null is the repository's way of saying "no additions".
      complete: Future.value(null),
    ));

    final container = containerWithStubs();
    final first = await container.read(libraryScanProvider.future);
    await pumpEventQueue();

    expect(container.read(libraryScanProvider).value, same(first));
  });

  test('a failing broader pass leaves the working list in place', () async {
    library.queue(LibraryScan(
      firstPass: Future.value([track('/a.mp3')]),
      complete: Future.error(Exception('volume rejected the projection')),
    ));

    final container = containerWithStubs();
    final first = await container.read(libraryScanProvider.future);
    await pumpEventQueue();

    expect(container.read(libraryScanProvider).hasError, isFalse);
    expect(container.read(libraryScanProvider).value, same(first));
  });

  test('records the scan only after the list is on screen', () async {
    final slowPass = Completer<List<Track>?>();
    library.queue(LibraryScan(
      firstPass: Future.value([track('/a.mp3')]),
      complete: slowPass.future,
    ));

    final container = containerWithStubs();
    await container.read(libraryScanProvider.future);

    expect(known.reconciled, isEmpty, reason: 'bookkeeping must not delay the first frame');

    slowPass.complete([track('/a.mp3'), track('/b.mp3', id: 2)]);
    await pumpEventQueue();

    expect(known.reconciled.single, {'/a.mp3', '/b.mp3'});
  });

  group('rescanning', () {
    test('hands back the same Track objects for unchanged files', () async {
      library.queue(LibraryScan(
        firstPass: Future.value([track('/a.mp3', title: '稻香'), track('/b.mp3', id: 2)]),
        complete: Future.value(null),
      ));
      library.queue(LibraryScan(
        firstPass: Future.value([track('/a.mp3', title: '稻香'), track('/b.mp3', id: 2)]),
        complete: Future.value(null),
      ));

      final container = containerWithStubs();
      final before = await container.read(libraryScanProvider.future);
      await container.read(libraryScanProvider.notifier).refresh();
      final after = container.read(libraryScanProvider).value!;

      expect(library.startCount, 2);
      expect(after[0], same(before[0]), reason: 'its sort keys are still valid');
      expect(after[1], same(before[1]));
    });

    test('takes the fresh object when the metadata actually changed', () async {
      library.queue(LibraryScan(
        firstPass: Future.value([track('/a.mp3', title: 'Old title')]),
        complete: Future.value(null),
      ));
      library.queue(LibraryScan(
        firstPass: Future.value([track('/a.mp3', title: 'Corrected title')]),
        complete: Future.value(null),
      ));

      final container = containerWithStubs();
      final before = await container.read(libraryScanProvider.future);
      await container.read(libraryScanProvider.notifier).refresh();
      final after = container.read(libraryScanProvider).value!;

      expect(after.single, isNot(same(before.single)));
      expect(after.single.title, 'Corrected title');
    });
  });

  group('derived keys', () {
    test('are computed once per distinct string, not once per track', () {
      // Same text, different files: the cache hands back the identical String,
      // which is what keeps a library of one artist from romanising that
      // artist's name on every row.
      final a = track('/a.mp3', title: '周杰倫', artist: '周杰倫');
      final b = track('/b.mp3', title: '周杰倫', artist: '周杰倫', id: 2);

      expect(a.artistKey, same(b.artistKey));
      expect(a.titleKey, same(b.titleKey));
      expect(a.indexLetter, same(b.indexLetter));
      expect(a.artistKey, same(a.titleKey), reason: 'one cache, keyed on the text');
    });

    test('still romanise Han text correctly through the cache', () {
      expect(track('/a.mp3', title: '稻香').titleKey, 'dao xiang');
      expect(track('/a.mp3', title: '稻香').indexLetter, 'D');
      expect(track('/a.mp3', title: '[4K] Zebra').titleKey, 'zebra');
    });
  });

  group('Track.matches', () {
    test('is true only when everything a row shows is the same', () {
      final original = track('/a.mp3', title: 'Same');

      expect(original.matches(track('/a.mp3', title: 'Same')), isTrue);
      expect(original.matches(track('/a.mp3', title: 'Different')), isFalse);
      expect(original.matches(track('/a.mp3', title: 'Same', artist: 'Other')), isFalse);
      expect(original.matches(track('/a.mp3', title: 'Same', id: 99)), isFalse);
      expect(original.matches(track('/moved.mp3', title: 'Same')), isFalse);
    });
  });
}
