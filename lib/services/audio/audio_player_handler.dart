import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../domain/track.dart';
import 'notification_artwork.dart';

/// Bridges [just_audio] (playback) and [audio_service] (notification, lock
/// screen, media buttons, background execution). The rest of the app talks to
/// this through `PlayerController` rather than touching either package.
class AudioPlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  AudioPlayerHandler({NotificationArtwork? artwork})
      : _artwork = artwork ?? NotificationArtwork() {
    // Forwarded with listen() rather than pipe(): pipe() holds the subject in
    // addStream mode, where any other add() throws "Bad state". Repeat and
    // shuffle need to push an updated state straight away, so the handler has
    // to own the subject.
    _player.playbackEventStream.listen((event) => playbackState.add(_transformEvent(event)));

    _player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index != null && index >= 0 && index < items.length) {
        mediaItem.add(items[index]);
        // Resolved one track at a time, as it comes round, rather than for
        // the whole queue up front: the session only ever displays the
        // current item, so a thousand-track queue would mean a thousand
        // artwork queries for pictures nothing is going to show.
        unawaited(_publishArtwork(index));
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final NotificationArtwork _artwork;

  /// The tracks behind the current queue, in the same order, so a queue index
  /// can be turned back into the MediaStore id artwork is looked up by.
  List<Track> _tracks = const [];

  AudioPlayer get player => _player;

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<SequenceState> get sequenceStateStream => _player.sequenceStateStream;

  /// Replaces the queue with [tracks] and starts playing at [initialIndex].
  ///
  /// [shuffle] is applied explicitly rather than left as whatever it happened
  /// to be, because just_audio draws a *fresh random order* for every list it
  /// loads. With shuffle still enabled from an earlier Shuffle all, picking a
  /// track in a playlist then walked that playlist in an order nobody asked
  /// for — and since shuffle isn't remembered across launches, restarting the
  /// app looked like the only cure. Loading a queue now always states which
  /// of the two it wants.
  Future<void> playTracks(
    List<Track> tracks, {
    int initialIndex = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    await _loadQueue(tracks, initialIndex: initialIndex);
    await setShuffleMode(
      shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    await _player.play();
  }

  /// Puts a previous session back — same queue, same track, same position —
  /// but paused, so opening the app never starts making noise on its own.
  Future<void> restoreTracks(List<Track> tracks, {required int initialIndex, Duration position = Duration.zero}) {
    if (tracks.isEmpty) return Future.value();
    return _loadQueue(tracks, initialIndex: initialIndex, position: position);
  }

  Future<void> _loadQueue(List<Track> tracks, {required int initialIndex, Duration position = Duration.zero}) async {
    final index = initialIndex.clamp(0, tracks.length - 1);
    final items = tracks.map(_toMediaItem).toList();
    _tracks = tracks;
    queue.add(items);
    mediaItem.add(items[index]);
    unawaited(_publishArtwork(index));

    await _player.setAudioSources(
      [for (final track in tracks) AudioSource.file(track.path)],
      initialIndex: index,
      initialPosition: position,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  // Skipping starts playback rather than just moving the marker. Pressing
  // next on a paused player — after a restored session, say — should play the
  // track you skipped to, not sit there silently on it.
  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
    await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
    await _player.play();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  /// Swiping the app out of Recents means "I'm done" — unless something is
  /// actually playing, in which case the whole point of the media session is
  /// that it keeps going.
  ///
  /// Without this the session stays registered and its service stays started
  /// after the window is gone: no notification, nothing on screen, and the
  /// app still listed as running with Force stop the only way out of it.
  @override
  Future<void> onTaskRemoved() async {
    if (_player.playing) return;
    await stop();
  }

  /// Puts [index]'s cover on the media session once it has been written out.
  ///
  /// Published as a second update to the same item rather than by holding the
  /// item back until its picture is ready: writing the file crosses a platform
  /// channel, and the title and artist should be up the moment the track
  /// changes, not a few hundred milliseconds later.
  Future<void> _publishArtwork(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    final track = _tracks[index];

    final uri = await _artwork.uriFor(track);
    if (uri == null) return;

    // The queue may have been replaced, or the track skipped past, while the
    // cover was being written — in which case this is no longer the artwork
    // for what is playing.
    final current = mediaItem.value;
    if (current == null || current.id != track.path) return;
    if (current.artUri == uri) return;

    mediaItem.add(current.copyWith(artUri: uri));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.none => LoopMode.off,
      _ => LoopMode.all,
    });
    // Changing loop mode doesn't emit a playback event, so publish the new
    // state now instead of waiting for the next one.
    playbackState.add(_transformEvent(_player.playbackEvent));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(_transformEvent(_player.playbackEvent));
  }

  /// Reorders the queue, keeping the player's playlist and the media session's
  /// queue in step.
  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    final items = [...queue.value];
    if (oldIndex < 0 || oldIndex >= items.length || newIndex < 0 || newIndex >= items.length) return;

    await _player.moveAudioSource(oldIndex, newIndex);
    items.insert(newIndex, items.removeAt(oldIndex));
    queue.add(items);
    // Moved the same way as the queue itself: this list is how an index is
    // turned back into the track whose cover the session shows.
    if (_tracks.length == items.length) {
      final tracks = [..._tracks];
      tracks.insert(newIndex, tracks.removeAt(oldIndex));
      _tracks = tracks;
    }
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final items = [...queue.value];
    if (index < 0 || index >= items.length) return;

    await _player.removeAudioSourceAt(index);
    items.removeAt(index);
    queue.add(items);
    if (_tracks.length == items.length + 1) {
      _tracks = [..._tracks]..removeAt(index);
    }
  }

  Future<void> dispose() => _player.dispose();

  MediaItem _toMediaItem(Track track) => MediaItem(
        id: track.path,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
      );

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
      repeatMode: switch (_player.loopMode) {
        LoopMode.one => AudioServiceRepeatMode.one,
        LoopMode.all => AudioServiceRepeatMode.all,
        LoopMode.off => AudioServiceRepeatMode.none,
      },
      shuffleMode:
          _player.shuffleModeEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }
}
