// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// Side of the coloured square. Small on purpose: a row of four of these is
/// a menu, not four buttons, and the caption underneath is doing half the
/// identifying work.
const _kTileSize = 34.0;

/// Glyph size inside the square.
const _kGlyphSize = 19.0;

/// Thickness of the ring drawn around the selected tile.
const _kSelectedRing = 2.0;

/// One entry in the service row along the top of the home sheet.
///
/// A rounded square of soft colour with a deep glyph in it, and a short
/// caption underneath. Four of them sit side by side and are the app's
/// top-level "what do you want to do" menu.
///
/// The colour is the point. A row of grey line icons is the single most
/// template-looking thing a taxi app can put on its home screen, and it also
/// makes every service look the same at a glance; here each one carries its
/// own [TakhiAccent], so riders learn "the green one is a ride" rather than
/// having to read four captions every time. The tint/glyph pair always comes
/// from [takhiAccentColors] rather than from the call site, which is what
/// keeps every one of them legible in both brightnesses.
///
/// The painted square is 34dp but the tile as a whole never presents a
/// target smaller than [TakhiTouch.minTarget] in either axis.
class CategoryTile extends StatelessWidget {
  /// The glyph in the coloured square.
  final IconData icon;

  /// The caption underneath. Short -- one or two Cyrillic words; longer
  /// labels wrap to a second line rather than truncating, because a
  /// half-word service name is worse than a taller row.
  ///
  /// User-visible: pass a localised string.
  final String label;

  /// Which colour family this service owns. Keep it stable for a given
  /// service across every screen it appears on.
  final TakhiAccent accent;

  /// Tapped. Null renders the tile visibly present but inert -- for a
  /// service that exists but is unavailable right now, which is more
  /// informative than removing it from the row.
  final VoidCallback? onTap;

  /// Draws a ring in the accent's own foreground colour around the square.
  /// For a row that behaves as a picker rather than as navigation.
  final bool selected;

  const CategoryTile({
    super.key,
    required this.icon,
    required this.label,
    this.accent = TakhiAccent.gold,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final colors = takhiAccentColors(accent, Theme.of(context).brightness);
    final enabled = onTap != null;

    final tile = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _kTileSize,
          height: _kTileSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.tint,
            borderRadius: TakhiRadius.tileAll,
            border: selected
                ? Border.all(color: colors.onTint, width: _kSelectedRing)
                : null,
          ),
          child: Icon(icon, size: _kGlyphSize, color: colors.onTint),
        ),
        const SizedBox(height: TakhiSpace.xs),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TakhiType.label.copyWith(
            color: selected ? surfaces.onSheet : surfaces.muted,
          ),
        ),
      ],
    );

    return Semantics(
      button: enabled,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: TakhiTouch.minTarget,
          minHeight: TakhiTouch.minTarget,
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: Colors.transparent,
            borderRadius: TakhiRadius.cardAll,
            child: InkWell(
              onTap: onTap,
              borderRadius: TakhiRadius.cardAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TakhiSpace.xxs,
                  vertical: TakhiSpace.xs,
                ),
                child: tile,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
