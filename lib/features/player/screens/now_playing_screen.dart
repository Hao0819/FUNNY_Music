import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_format.dart';
import '../../../domain/track.dart';
import '../../../widgets/artwork_image.dart';
import '../../../widgets/empty_state.dart';
import '../../folders/providers/folder_providers.dart';
import '../../library/providers/library_providers.dart';
import '../providers/player_providers.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/waveform_seek_bar.dart';

/// Raises Now Playing as a sheet from the bottom.
///
/// The screen is a detail view of the bar you tapped, directly above it — a
/// horizontal push would imply you had moved sideways in a hierarchy.
///
/// [heroTag] is supplied by the mini player that opened this screen rather
/// than being a constant, because a mini player sits on four different routes
/// and two of them are alive at once whenever one is pushed over another. A
/// shared tag would make Flutter fly the thumbnail between those two bars —
/// which sit at different heights, since only the bottom-most one pads itself
/// past the gesture area — on every unrelated push.
Route<void> nowPlayingRoute({required Object heroTag}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) => NowPlayingScreen(heroTag: heroTag),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
        ),
        child: child,
      );
    },
  );
}

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key, this.heroTag});

  /// Matches the tag of the mini player that opened this screen. Null when
  /// the screen is reached some other way, which simply means no hero flight.
  final Object? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.music_note_outlined,
          title: 'Nothing playing',
          message: 'Pick a track from your library to start.',
        ),
      );
    }

    // Everything below reads its colour from the theme, so re-theming here is
    // what makes the whole screen follow the cover art.
    return _NowPlayingBody(item: item, heroTag: heroTag);
  }
}

class _NowPlayingBody extends ConsumerWidget {
  const _NowPlayingBody({required this.item, required this.heroTag});

  final MediaItem item;
  final Object? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final state = ref.watch(playbackStateProvider).value;
    final playing = state?.playing ?? false;
    final repeatMode = state?.repeatMode ?? AudioServiceRepeatMode.all;
    final shuffleOn = (state?.shuffleMode ?? AudioServiceShuffleMode.none) != AudioServiceShuffleMode.none;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = item.duration ?? Duration.zero;
    final track = ref.watch(trackByPathProvider(item.id));
    final isFavorite = ref.watch(isFavoriteProvider(item.id));
    // The transport is plain emphasis ink: black on paper, white on ink. It
    // used to take the playing cover's colour, which in a palette with no
    // other hue in it read as a bug rather than as a flourish.
    final accent = scheme.onSurface;
    final controller = ref.read(playerControllerProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      // Opaque. It was transparent so the blurred-cover backdrop could show
      // through from the bottom of the stack; with that gone there was nothing
      // behind it but the route's own black, which is what light mode showed.
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Now playing', style: theme.textTheme.labelLarge),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Artwork takes what's left after the controls, so short
                // screens shrink the cover instead of overflowing.
                final artworkSize = (constraints.maxHeight - 356).clamp(140.0, constraints.maxWidth - 48);

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: _MaybeHero(
                          tag: heroTag,
                          // Both ends are square now, so nothing is animated
                          // but the size. The shuttle is still custom because
                          // of the sizing problem below.
                          flightShuttleBuilder: (context, animation, direction, from, to) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                // The shuttle must take its size from the
                                // flight rect, not from a constant: ArtworkImage
                                // needs an explicit size, and passing the final
                                // one made the cover paint full size for the
                                // whole flight — it overflowed the rect and the
                                // cover simply appeared already-large instead of
                                // growing out of the mini player.
                                return LayoutBuilder(
                                  builder: (context, constraints) {
                                    final side = constraints.biggest.shortestSide;
                                    return ArtworkImage(
                                      track: track,
                                      size: side,
                                      borderRadius: AppTheme.radiusMedium,
                                      iconSize: side * 0.3,
                                    );
                                  },
                                );
                              },
                            );
                          },
                          child: _ArtworkCard(
                            track: track,
                            size: artworkSize,
                            glow: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: AppTheme.displayTitle(theme.textTheme, item.title),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item.artist ?? 'Unknown artist',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Sits on the title's baseline rather than centred
                          // under it: it acts on this track, so it belongs
                          // beside the track's name.
                          IconButton(
                            tooltip: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                            iconSize: 26,
                            color: isFavorite ? scheme.primary : scheme.onSurfaceVariant,
                            onPressed: () => ref.read(folderActionsProvider).toggleFavorite(item.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      WaveformSeekBar(
                        seed: item.id,
                        position: position,
                        duration: duration,
                        onSeek: controller.seek,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatDuration(position), style: theme.textTheme.labelSmall),
                          Text(formatDuration(duration), style: theme.textTheme.labelSmall),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            tooltip: shuffleOn ? 'Shuffle on' : 'Shuffle off',
                            icon: const Icon(Icons.shuffle),
                            color: shuffleOn ? scheme.primary : scheme.onSurfaceVariant,
                            onPressed: controller.toggleShuffle,
                          ),
                          IconButton(
                            iconSize: 38,
                            icon: const Icon(Icons.skip_previous),
                            onPressed: controller.previous,
                          ),
                          _PlayButton(
                            playing: playing,
                            accent: accent,
                            onPressed: controller.togglePlayPause,
                          ),
                          IconButton(
                            iconSize: 38,
                            icon: const Icon(Icons.skip_next),
                            onPressed: controller.next,
                          ),
                          IconButton(
                            tooltip: switch (repeatMode) {
                              AudioServiceRepeatMode.one => 'Repeat one',
                              AudioServiceRepeatMode.none => 'Repeat off',
                              _ => 'Repeat all',
                            },
                            icon: Icon(
                              repeatMode == AudioServiceRepeatMode.one ? Icons.repeat_one : Icons.repeat,
                            ),
                            color: repeatMode == AudioServiceRepeatMode.none
                                ? scheme.onSurfaceVariant
                                : scheme.primary,
                            onPressed: controller.cycleRepeatMode,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A [Hero] when there is a tag to fly to, and the bare child otherwise —
/// a Hero with no counterpart on the route below would still lift its child
/// into the overlay for the length of the transition.
class _MaybeHero extends StatelessWidget {
  const _MaybeHero({
    required this.tag,
    required this.flightShuttleBuilder,
    required this.child,
  });

  final Object? tag;
  final HeroFlightShuttleBuilder flightShuttleBuilder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tag = this.tag;
    if (tag == null) return child;

    return Hero(
      tag: tag,
      flightShuttleBuilder: flightShuttleBuilder,
      child: child,
    );
  }
}

// A _Backdrop widget lived here: the playing cover, blurred to fill the
// screen behind the controls, with a scrim and a wash of the sampled accent
// over it. The screen is a plain surface now — the reference puts the cover
// on a flat ground, and with the artwork palette gone there was nothing left
// to sample the wash from.


/// Artwork plus the glow beneath it. Split out so the [Hero] has a single
/// child whose shape the flight builder can mirror.
class _ArtworkCard extends StatelessWidget {
  const _ArtworkCard({required this.track, required this.size, required this.glow});

  final Track? track;
  final double size;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return ArtworkImage(
      track: track,
      size: size,
      borderRadius: AppTheme.radiusMedium,
      iconSize: size * 0.3,
      placeholderTint: 0.20,
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.accent, required this.onPressed});

  final bool playing;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            playing ? Icons.pause : Icons.play_arrow,
            key: ValueKey(playing),
            size: 40,
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
      ),
    );
  }
}
