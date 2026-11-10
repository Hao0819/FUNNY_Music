import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/domain/track.dart';
import 'package:music_player/services/audio/track_artwork.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

class _ArtworkQuery extends OnAudioQuery {
  @override
  Future<Uint8List?> queryArtwork(
    int id,
    ArtworkType type, {
    ArtworkFormat? format,
    int? size,
    int? quality,
  }) async {
    if (id == 2) throw PlatformException(code: 'MissingPermissions');
    return Uint8List.fromList([2]);
  }
}

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const music = '/storage/emulated/0/Music/MusicPlayer';

  test(
    'uses the download cover by path and falls back when it is absent',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'track_artwork_test',
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(paths, null);
        debugDefaultTargetPlatformOverride = null;
        await support.delete(recursive: true);
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(paths, (call) async {
        expect(call.method, 'getApplicationSupportDirectory');
        return support.path;
      });

      const key =
          'aeafb7108f990036c19443ae3673ce3fa55eac576ddb53ece0c73b05ff6cad0c';
      final cover = await File(
        p.join(support.path, 'download_artwork', '$key.jpg'),
      ).create(recursive: true);
      await cover.writeAsBytes([1]);

      final download = Track.fromMediaStoreMap({
        'id': 1,
        'path': '$music/测试.opus',
      });
      final other = Track.fromMediaStoreMap({
        'id': 1,
        'path': '$music/another.m4a',
      });
      final unreadable = Track.fromMediaStoreMap({
        'id': 2,
        'path': '$music/another.mp3',
      });
      final query = _ArtworkQuery();

      expect(await readTrackArtwork(query, download, size: 400), [1]);
      expect(await readTrackArtwork(query, other, size: 400), [2]);
      expect(await readTrackArtwork(query, unreadable, size: 400), isNull);
    },
  );
}
