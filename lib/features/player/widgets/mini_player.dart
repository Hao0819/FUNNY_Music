import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_format.dart';
import '../../../widgets/artwork_image.dart';
import '../../library/providers/library_providers.dart';
import '../providers/player_providers.dart';
import '../screens/now_playing_screen.dart';

/// A single line across the bottom of the screen, with the position drawn as a
/// hairline along its top edge. Renders nothing until something is playing.
///
/// Flush rather than a floating rounded card: the card had a shadow, a radius
/// and a gap on three sides, which made the most persistent element in the app
/// also one of the loudest. Flush, it reads as part of the frame, and the
/// progress hairline doubles as the rule that separates it from the list.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.isBottomMost = false});

  /// True where the bar is the last thing on screen (folder, history and
  /// new-audio pages). In the tab shell the navigation bar sits below it and
  /// already clears the system bar; on its own, the bar must pad itself or its
  /// buttons land inside Android's gesture area and taps get swallowed.
  final bool isBottomMost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();

    // Scoped to this bar's own route, so the four screens that show a mini
    // player never share a tag — see nowPlayingRoute for why that matters.
    // The route object is the identity; records compare field-wise and Route
    // does not override ==, so this is unique per route instance.
    final heroTag = ('mini-player-artwork', ModalRoute.of(context));

    final bar = _Bar(item: item, heroTag: heroTag);
    // The bar paints its own background to the edge, so SafeArea only has to
    // keep the controls out of Android's gesture strip.
    return isBottomMost ? SafeArea(top: false, child: bar) : bar;
  }
}

class _Bar extends ConsumerWidget {
  const _Bar({required this.item, required this.heroTag});

  final MediaItem item;
  final Object heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateProvider).value;
    final playing = state?.playing ?? false;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = item.duration ?? Duration.zero;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(playerControllerProvider);

    // The card inverts: near-black on a paper screen, white on an ink one. It
    // is the one element that has to stay findable while the list scrolls
    // under it, and with no accent colour in the palette, flipping the
    // greyscale is the strongest move available.
    final card = scheme.onSurface;
    final onCard = scheme.surface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(nowPlayingRoute(heroTag: heroTag)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    Hero(tag: heroTag, child: _MiniArtwork(mediaItemId: item.id)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: onCard,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${formatDuration(position)} / ${formatDuration(duration)}'
                            '${item.artist == null || item.artist!.isEmpty ? '' : '  ·  ${item.artist}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: onCard.withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous',
                      icon: const Icon(Icons.skip_previous_rounded),
                      color: onCard.withValues(alpha: 0.75),
                      onPressed: controller.previous,
                    ),
                    _PlayButton(
                      playing: playing,
                      background: onCard,
                      foreground: card,
                      onTap: controller.togglePlayPause,
                    ),
                    IconButton(
                      tooltip: 'Next',
                      icon: const Icon(Icons.skip_next_rounded),
                      color: onCard.withValues(alpha: 0.75),
                      onPressed: controller.next,
                    ),
                  ],
                ),
              ),
              // A hairline along the bottom edge of the card, inside the
              // rounding. The reference has no progress here at all; this is
              // two pixels of it, which is enough to glance at and not enough
              // to add a row.
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  color: onCard,
                  backgroundColor: onCard.withValues(alpha: 0.22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Matches the big button on Now Playing so the two read as the same control.
///
/// Both are now drawn in plain greys rather than from the artwork: with a
/// monochrome palette, a disc that takes its colour from the current cover is
/// the only coloured thing on the screen, and it looked like a mistake.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final bool playing;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: background),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: foreground,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork lookup needs the MediaStore id, which the queue doesn't carry, so
/// resolve it from the library by path.
class _MiniArtwork extends ConsumerWidget {
  const _MiniArtwork({required this.mediaItemId});

  final String mediaItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(trackByPathProvider(mediaItemId));
    return ArtworkImage(track: track, size: 44, borderRadius: 10, iconSize: 18);
  }
}
