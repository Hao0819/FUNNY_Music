import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../domain/track.dart';
import '../../../services/audio/audio_player_handler.dart';
import '../../library/providers/library_providers.dart';

/// Overridden in `main()` once [AudioService.init] has produced the handler.
final audioHandlerProvider = Provider<AudioPlayerHandler>((ref) {
  throw StateError('audioHandlerProvider must be overridden in main()');
});

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(audioHandlerProvider).playbackState;
});

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return ref.watch(audioHandlerProvider).mediaItem;
});

final queueProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(audioHandlerProvider).queue;
});

final playbackPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(audioHandlerProvider).positionStream;
});

/// Everything the UI needs to drive playback, so screens never touch
/// just_audio or audio_service directly.
class PlayerController {
  PlayerController(this._ref) {
    // Every time the current item changes — tapping a track, skipping, or the
    // queue advancing on its own — log it so "recently played" and "most
    // played" have something to read back.
    // skip(1): the subject replays its current item to new listeners. After a
    // restored session that item was only loaded, not played, so it mustn't
    // be logged as a play.
    _mediaItemSubscription = _handler.mediaItem.skip(1).listen((item) async {
      if (item == null) return;
      // The same track is published more than once — again as soon as its
      // cover has been written out for the notification — and one track
      // coming on is one play however many times the session republishes it.
      if (item.id == _lastLoggedPath) return;
      _lastLoggedPath = item.id;

      await _ref.read(historyRepositoryProvider).recordPlay(item.id);
      _ref.read(historyTickProvider.notifier).bump();
    });
    _ref.onDispose(() => _mediaItemSubscription.cancel());
  }

  final Ref _ref;
  late final StreamSubscription<MediaItem?> _mediaItemSubscription;

  /// The last track written to the play log, so republishing the same one
  /// doesn't count twice.
  String? _lastLoggedPath;

  AudioPlayerHandler get _handler => _ref.read(audioHandlerProvider);

  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) {
    return _handler.playTracks(tracks, initialIndex: initialIndex);
  }

  /// Starts a list on a random track with shuffle turned on.
  ///
  /// This is the only thing that turns shuffle on by itself: [playTracks]
  /// turns it back off, so picking a track out of a list always plays that
  /// list in its own order.
  Future<void> shufflePlay(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    await _handler.playTracks(
      tracks,
      initialIndex: Random().nextInt(tracks.length),
      shuffle: true,
    );
  }

  Future<void> togglePlayPause() {
    final playing = _ref.read(playbackStateProvider).value?.playing ?? false;
    return playing ? _handler.pause() : _handler.play();
  }

  Future<void> next() => _handler.skipToNext();

  Future<void> previous() => _handler.skipToPrevious();

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> skipToQueueItem(int index) => _handler.skipToQueueItem(index);

  Future<void> moveQueueItem(int oldIndex, int newIndex) => _handler.moveQueueItem(oldIndex, newIndex);

  Future<void> removeQueueItemAt(int index) => _handler.removeQueueItemAt(index);

  /// Cycles all -> one -> none -> all, matching the button's three icons, and
  /// remembers the choice across launches.
  Future<void> cycleRepeatMode() async {
    final current = _ref.read(playbackStateProvider).value?.repeatMode ?? AudioServiceRepeatMode.all;
    final next = switch (current) {
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
      _ => AudioServiceRepeatMode.all,
    };
    await _handler.setRepeatMode(next);
    await _ref.read(settingsRepositoryProvider).updateRepeatMode(switch (next) {
      AudioServiceRepeatMode.one => 'one',
      AudioServiceRepeatMode.none => 'none',
      _ => 'all',
    });
  }

  Future<void> toggleShuffle() {
    final enabled = (_ref.read(playbackStateProvider).value?.shuffleMode ?? AudioServiceShuffleMode.none) !=
        AudioServiceShuffleMode.none;
    return _handler.setShuffleMode(
      enabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
    );
  }
}

final playerControllerProvider = Provider<PlayerController>((ref) => PlayerController(ref));
