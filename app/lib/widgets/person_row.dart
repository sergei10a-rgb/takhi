// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';
import 'accent_dot.dart';

/// Diameter of the avatar.
const _kAvatarSize = 44.0;

/// Size of the rating star. Matched to [TakhiType.support]'s cap height.
const _kStarSize = 14.0;

/// The row that shows who the other person in a trip is.
///
/// A round portrait, the name in the primary weight, a star rating beside
/// it, and room on the right for the action that belongs to that person --
/// call, message, view profile. It is the one place in the app where a
/// human, rather than a place or a price, is the subject of a row.
///
/// The rating sits on the *same line* as the name rather than under it. A
/// rider glancing at a car pulling up needs both facts in one saccade, and
/// stacking them turns a two-line row into a three-line one that pushes the
/// primary action off a short screen.
///
/// Avatars degrade rather than break: a missing [avatar] falls back to
/// [initials], and missing initials fall back to the first character of
/// [name], so a driver with no photo still gets a proper mark instead of a
/// grey blank.
class PersonRow extends StatelessWidget {
  /// The person's display name. User-supplied text, not a localised string.
  final String name;

  /// Portrait. Null falls back to [initials].
  final ImageProvider? avatar;

  /// Letters for the fallback avatar. Null derives them from [name].
  final String? initials;

  /// 0-5 star rating. Null hides the star entirely -- a rating of zero and
  /// "not rated yet" are different facts and must not render the same.
  final double? rating;

  /// Optional muted second line: a plate number, a car model, an ETA.
  /// User-visible if it is a phrase: pass a localised string.
  final String? subtitle;

  /// Optional widget at the right edge -- typically a [CircleIconButton] for
  /// calling, or a chevron.
  final Widget? trailing;

  /// Makes the whole row tappable, for opening a profile. The [trailing]
  /// widget keeps its own gestures.
  final VoidCallback? onTap;

  /// Colour family of the fallback avatar.
  final TakhiAccent accent;

  const PersonRow({
    super.key,
    required this.name,
    this.avatar,
    this.initials,
    this.rating,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.accent = TakhiAccent.gold,
  });

  /// What the fallback avatar shows: [initials] if the caller supplied any,
  /// otherwise the first character of [name], uppercased. Never empty --
  /// [AccentDot] rejects a blank mark, and an assertion in front of a rider
  /// waiting for their driver is the wrong way to report a missing name.
  String get _initialsMark {
    final given = initials?.trim() ?? '';
    if (given.isNotEmpty) return given;
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TakhiTouch.minTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TakhiSpace.xs),
        child: Row(
          children: [
            _avatar(),
            const SizedBox(width: TakhiSpace.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TakhiType.title.copyWith(
                            color: surfaces.onSheet,
                          ),
                        ),
                      ),
                      if (rating != null) ...[
                        const SizedBox(width: TakhiSpace.xs),
                        Icon(
                          Icons.star_rounded,
                          size: _kStarSize,
                          // The one place flat gold is correct as a
                          // foreground: a star is a shape, not text, and it
                          // is read as a symbol beside the number that
                          // carries the actual value.
                          color: TakhiColors.gold,
                        ),
                        const SizedBox(width: TakhiSpace.xxs / 2),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: TakhiType.support.copyWith(
                            color: surfaces.onSheet,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: TakhiSpace.xxs / 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TakhiType.support.copyWith(color: surfaces.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: TakhiSpace.xs),
              trailing!,
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      borderRadius: TakhiRadius.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: TakhiRadius.cardAll,
        child: row,
      ),
    );
  }

  Widget _avatar() {
    final fallback = AccentDot(
      label: _initialsMark,
      accent: accent,
      size: _kAvatarSize,
    );
    if (avatar == null) return fallback;
    return ClipOval(
      child: Image(
        image: avatar!,
        width: _kAvatarSize,
        height: _kAvatarSize,
        fit: BoxFit.cover,
        // A portrait that fails to decode must not take the row down with
        // it -- fall back to the same mark a photo-less person gets.
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
