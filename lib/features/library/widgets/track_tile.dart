import 'package:flutter/material.dart';

import '../../../core/utils/duration_format.dart';
import '../../../domain/track.dart';
import '../../../widgets/artwork_image.dart';
import '../../player/widgets/playing_indicator.dart';

/// One track: cover, title, and a metadata line under it.
///
/// The playing row says so by sitting on a raised rounded block with a level
/// meter over its cover — not by turning a colour. There is no accent hue in
/// this palette at all, so state is drawn with contrast and shape, which is
/// also what keeps a list of a thousand rows from looking lit up.
///
/// What the row does not do is let a title's leading `[4K 60fps]` tag push the
/// name of the song off the end: that goes to the metadata line instead.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.selectionMode = false,
    this.selected = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
    this.folderNames = const [],
    this.isCurrent = false,
  });

  /// Every row is this tall, in every list.
  ///
  /// Fixed rather than intrinsic because the Library's A-Z index jumps
  /// straight to `index * height` without measuring anything.
  static const height = 68.0;

  /// Marks the row as the track the player is on, so it stands out in a list.
  final bool isCurrent;

  /// User folders this track is filed in, named on the metadata line.
  final List<String> folderNames;

  final Track track;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool selectionMode;
  final bool selected;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final raised = isCurrent || selected;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
        child: Material(
          // The raised block is the whole marker. It is inset from the screen
          // edge so the rounding is visible, which is what makes it read as a
          // block rather than as a stripe of lighter background.
          color: raised ? scheme.surfaceContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  if (selectionMode)
                    _SelectionBox(selected: selected)
                  else
                    _Cover(track: track, isCurrent: isCurrent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Two parts, not one string: these artists are often a
                        // whole YouTube channel name, and as one ellipsised
                        // line that ate the duration every time.
                        DefaultTextStyle(
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(_lead(), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              Text('  ·  ${formatDuration(track.duration)}'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing ??
                      (onFavoriteToggle == null
                          ? const SizedBox(width: 4)
                          : IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                              icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, size: 19),
                              color: isFavorite ? scheme.onSurface : scheme.outline,
                              onPressed: onFavoriteToggle,
                            )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The part of the metadata line that may be truncated: the artist, and any
  /// folders the track is filed in. The duration is appended separately so it
  /// always survives.
  ///
  /// The title's leading tag is deliberately not repeated here. It is already
  /// off the title, which was the point, and on a row this size it was the
  /// third thing competing for a line that only reads well with two.
  String _lead() => [track.artist, ...folderNames].join('  ·  ');
}

/// The cover, with a level meter over it while this is the playing track.
class _Cover extends StatelessWidget {
  const _Cover({required this.track, required this.isCurrent});

  final Track track;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final cover = ArtworkImage(track: track, size: 48, borderRadius: 8, iconSize: 20);
    if (!isCurrent) return cover;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        fit: StackFit.expand,
        children: [
          cover,
          // Dimmed, because the meter has to stay legible over artwork that
          // might be anything from a black silhouette to a white sleeve.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          const Center(child: PlayingIndicator(color: Colors.white)),
        ],
      ),
    );
  }
}

class _SelectionBox extends StatelessWidget {
  const _SelectionBox({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: selected ? scheme.onSurface : scheme.surfaceContainerHigh,
      ),
      child: Icon(
        selected ? Icons.check : Icons.music_note,
        size: 20,
        color: selected ? scheme.surface : scheme.onSurfaceVariant,
      ),
    );
  }
}
