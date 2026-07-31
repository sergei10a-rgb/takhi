// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// Fraction of the disc's diameter the glyph inside it occupies. Tuned once
/// here so a 22dp dot and a 40dp avatar hold the same optical weight.
const _kGlyphRatio = 0.58;

/// The small tinted disc that marks the start of a row.
///
/// Every leading mark in the app is one of these -- the dot in front of a
/// [PillField], the origin/destination markers of an address list, the
/// fallback avatar of a person with no photo. Having one primitive is what
/// keeps them optically identical: the same disc, the same glyph-to-disc
/// ratio, the same tint/foreground pair from [takhiAccentColors], so a row
/// never looks subtly heavier than the row above it.
///
/// It is decoration, never a control: it has no gesture handling and is
/// hidden from the semantics tree, because the row that contains it already
/// announces what it is. Wrapping it in a tap handler is a mistake -- a 22dp
/// disc is far below [TakhiTouch.minTarget].
class AccentDot extends StatelessWidget {
  /// The glyph inside the disc. Mutually exclusive with [label]; if both are
  /// given, the icon wins.
  final IconData? icon;

  /// Text inside the disc instead of a glyph -- initials, in practice.
  /// Scaled with the disc so it never overflows.
  final String? label;

  /// Which colour family the disc takes. Both halves of the pair move with
  /// the theme's brightness.
  final TakhiAccent accent;

  /// Diameter. 22-24 for a row marker, 40 for an avatar.
  final double size;

  const AccentDot({
    super.key,
    this.icon,
    this.label,
    this.accent = TakhiAccent.gold,
    this.size = 24,
  }) : assert(
         icon != null || label != null,
         'an AccentDot with neither an icon nor a label is an empty circle',
       );

  @override
  Widget build(BuildContext context) {
    final colors = takhiAccentColors(accent, Theme.of(context).brightness);
    final glyphSize = size * _kGlyphRatio;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors.tint, shape: BoxShape.circle),
        child: icon != null
            ? Icon(icon, size: glyphSize, color: colors.onTint)
            : Text(
                label!,
                maxLines: 1,
                style: TakhiType.label.copyWith(
                  fontSize: glyphSize,
                  height: 1,
                  color: colors.onTint,
                ),
              ),
      ),
    );
  }
}
