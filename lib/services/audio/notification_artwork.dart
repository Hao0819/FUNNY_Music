import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:on_audio_query/on_audio_query.dart' show ArtworkType, OnAudioQuery;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/track.dart';
import '../../widgets/fallback_cover.dart';

/// Covers for the notification and the lock screen, written out as files.
///
/// `audio_service` takes artwork as a URI and only ever reads it from a file
/// or a `content://` provider, so the picture a row draws from memory has to
/// be put on disk before the media session can show the same thing. With no
/// URI at all the session falls back to the launcher icon — the same image for
/// every track, which is what the lock screen used to show.
///
/// Reads the bundled stand-in sleeve for a track with no embedded picture,
/// because that is what the list and Now Playing show for it; the notification
/// should not be the one place a track looks like something else.
class NotificationArtwork {
  NotificationArtwork({OnAudioQuery? query}) : _query = query ?? OnAudioQuery();

  final OnAudioQuery _query;

  /// One resolved URI per MediaStore id, misses included: a query that came
  /// back empty would otherwise cross the platform channel again every time
  /// that track came round in the queue.
  final Map<int, Uri?> _resolved = {};

  Future<Directory>? _directory;

  /// The cover for [track] as a `file://` URI, or null when it couldn't be
  /// written — in which case the session just shows no artwork.
  Future<Uri?> uriFor(Track track) async {
    if (_resolved.containsKey(track.id)) return _resolved[track.id];

    final uri = await _resolve(track);
    _resolved[track.id] = uri;
    return uri;
  }

  Future<Uri?> _resolve(Track track) async {
    try {
      final directory = await (_directory ??= _openDirectory());

      final embedded = await _query.queryArtwork(track.id, ArtworkType.AUDIO, size: 500);
      if (embedded != null && embedded.isNotEmpty) {
        return await _write(p.join(directory.path, 'track-${track.id}.jpg'), embedded);
      }

      final asset = fallbackCoverAsset(track.id);
      final bytes = await rootBundle.load(asset);
      return await _write(
        p.join(directory.path, p.basename(asset)),
        bytes.buffer.asUint8List(),
      );
    } catch (error) {
      // Artwork is decoration: a track whose cover can't be written still
      // plays, and still shows its title and artist in the notification.
      debugPrint('Could not prepare notification artwork for ${track.path}: $error');
      return null;
    }
  }

  Future<Uri> _write(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
    return Uri.file(path);
  }

  /// Emptied once per app run rather than left to accumulate: every track that
  /// plays leaves a copy of its cover here, and whatever is needed is written
  /// again anyway. Memoised as a future so two tracks resolving at once can't
  /// have one of them clear the directory under the other.
  Future<Directory> _openDirectory() async {
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'notification_artwork'),
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    return directory.create(recursive: true);
  }
}
