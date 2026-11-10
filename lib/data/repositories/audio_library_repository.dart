import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../domain/track.dart';
import '../../services/scanning/media_store_scanner.dart';

/// Path fragments whose audio is noise rather than music. Matched
/// case-insensitively against the full file path.
const _excludedPathFragments = [
  '/whatsapp/media/whatsapp audio/',
  '/whatsapp/media/whatsapp voice notes/',
  '/whatsapp business/media/whatsapp business audio/',
  '/whatsapp business/media/whatsapp business voice notes/',
];

/// Two scans in flight, with the quicker one separated out so a caller can
/// show something before the slower one finishes.
class LibraryScan {
  LibraryScan({required this.firstPass, required this.complete});

  /// Rows from the plugin, or the native scan if the plugin rejects access.
  final Future<List<Track>> firstPass;

  /// The union with the broader native query, or null when that query turned
  /// up nothing [firstPass] did not already have — which is the common case,
  /// and lets a caller skip re-sorting an identical list.
  final Future<List<Track>?> complete;
}

class AudioLibraryRepository {
  AudioLibraryRepository(this._query, this._scanner);

  final OnAudioQuery _query;
  final MediaStoreScanner _scanner;

  /// Starts both scans at once and hands back their results separately:
  ///
  /// * `on_audio_query` — well-parsed rows from the audio collection, which
  ///   carry the best metadata.
  /// * our native files-collection query — catches audio MediaStore filed as
  ///   generic files (common for Download folders) and other volumes.
  ///
  /// Plugin rows win on conflict since their metadata is richer.
  ///
  /// They are kept apart rather than awaited together because the native query
  /// walks every volume and is the slower of the two by a long way. Holding the
  /// list back until both returned is what made launch a load screen, even
  /// though the first result alone is usually the entire library.
  LibraryScan startScan() {
    final pluginRows = _queryViaPlugin();
    final nativeRows = _scanner.queryAudioFiles();

    final firstPass = pluginRows.onError<PlatformException>((error, stackTrace) {
      if (error.code != 'MissingPermissions') {
        Error.throwWithStackTrace(error, stackTrace);
      }
      // The plugin checks extra permissions that Android does not require for
      // reading audio. The native scan uses the permission already granted.
      return nativeRows;
    }).then((tracks) => tracks.where(_isWanted).toList());

    return LibraryScan(
      firstPass: firstPass,
      complete: Future(() async {
        final plugin = await firstPass;
        final native = await nativeRows;

        final byPath = {for (final track in plugin) track.path: track};
        var added = false;
        for (final track in native) {
          // Plugin rows win, so a path already present is left alone.
          if (byPath.containsKey(track.path) || !_isWanted(track)) continue;
          byPath[track.path] = track;
          added = true;
        }

        return added ? byPath.values.toList() : null;
      }),
    );
  }

  /// The union of both scans, for callers that only want a final answer.
  Future<List<Track>> fetchTracks() async {
    final scan = startScan();
    return await scan.complete ?? await scan.firstPass;
  }

  Future<List<Track>> _queryViaPlugin() async {
    final songs = await _query.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    return songs.map(Track.fromSongModel).toList();
  }

  bool _isWanted(Track track) {
    if (track.path.isEmpty) return false;

    final path = track.path.toLowerCase();
    return !_excludedPathFragments.any(path.contains);
  }
}
