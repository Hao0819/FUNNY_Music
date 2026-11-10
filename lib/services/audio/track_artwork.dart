import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/track.dart';

// Matches the cover file written by YtdlpBridge.saveThumbnail.
String artworkFileKey(String audioPath) =>
    sha256.convert(utf8.encode(audioPath)).toString();

Future<Uint8List?> readTrackArtwork(
  OnAudioQuery query,
  Track track, {
  required int size,
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final directory = await getApplicationSupportDirectory();
      final key = artworkFileKey(track.path);
      final cover = File(
        p.join(directory.path, 'download_artwork', '$key.jpg'),
      );
      if (await cover.exists()) {
        final bytes = await cover.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } on Exception catch (error) {
      debugPrint('Could not read downloaded artwork: $error');
    }
  }

  try {
    return await query.queryArtwork(track.id, ArtworkType.AUDIO, size: size);
  } on PlatformException catch (error) {
    debugPrint('Could not read embedded artwork: ${error.code}');
    return null;
  } on MissingPluginException {
    return null;
  }
}
