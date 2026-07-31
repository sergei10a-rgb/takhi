// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// Glyph size inside a chip. Matched to [TakhiType.label]'s cap height so
/// the icon and the word sit on one optical line.
const _kGlyphSize = 13.0;

/// The small capsule that carries one fact.
///
/// "3кг · Жижиг", "12 мин", "Бэлнээр" -- the metadata that qualifies
/// something without being the thing itself. Chips are read in clusters, so
/// they are deliberately quiet: small text, soft fill, no shadow, no border
/// in the tinted variant. Anything loud enough to compete with the row it
/// annotates is a badge, not a chip.
///
/// Two variants, chosen by [tinted]:
///
/// * tinted (default) -- a soft accent fill with the accent's own deep
///   foreground on it. Both halves come from [takhiAccentColors], so the
///   pair clears WCAG AA in either brightness;
/// * outlined -- no fill, a hairline edge, muted text. For a cluster where
///   several chips would otherwise turn a row into a colour chart.
///
/// This is a *label*, not a control: it takes no tap handler. A tappable
/// capsule that filters or toggles is a different component with a different
/// touch-target contract, and conflating the two is how 28dp-tall buttons
/// end up shipping.
class InfoChip extends StatelessWidget {
  /// The text. Short -- a chip that wraps has stopped being a chip.
  ///
  /// User-visible: pass a localised string.
  final String label;

  /// Optional glyph before the text.
  final IconData? icon;

  /// Colour family. [TakhiAccent.neutral] is the right default for plain
  /// metadata; reach for a colour only when it means something.
  final TakhiAccent accent;

  /// False swaps the accent fill for a hairline outline and muted text.
  final bool tinted;

  const InfoChip({
    super.key,
    required this.label,
    this.icon,
    this.accent = TakhiAccent.neutral,
    this.tinted = true,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final colors = takhiAccentColors(accent, Theme.of(context).brightness);
    final foreground = tinted ? colors.onTint : surfaces.muted;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TakhiSpace.xs,
        vertical: TakhiSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: tinted ? colors.tint : null,
        borderRadius: TakhiRadius.pillAll,
        border: tinted ? null : Border.all(color: surfaces.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: _kGlyphSize, color: foreground),
            const SizedBox(width: TakhiSpace.xxs),
          ],
          // Flexible so the `maxLines`/`ellipsis` above can actually fire:
          // a bare `Text` in a `Row` is laid out unbounded and would run
          // off the edge instead of eliding. Loose fit, so a short label
          // still makes the chip hug its own text.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TakhiType.label.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
