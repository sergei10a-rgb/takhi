// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';
import 'accent_dot.dart';

/// Diameter of the leading disc. Larger than [AddressRow]'s marker and
/// smaller than [PersonRow]'s avatar: a menu row is scanned by its colour
/// before its words, so the disc has to carry weight, but it is still a mark
/// and not a portrait.
const _kDotSize = 36.0;

/// The row that takes you somewhere else.
///
/// A tinted disc, a heavy line naming the destination, a muted line saying
/// what is behind it, and a chevron. It exists because two screens in this
/// app are lists of destinations -- the settings menu and the SOS sheet --
/// and both had been built out of bare `ListTile`s: grey outline glyphs,
/// no second line, no chevron, and nothing but a ripple to say the row was
/// tappable at all.
///
/// Three rules it enforces that a `ListTile` does not:
///
/// 1. **the row says what tapping it does.** [subtitle] is not decoration;
///    a menu whose rows are single nouns ("Утасны дугаар") makes the user
///    open each one to find out which is which. It is optional only for the
///    row whose label genuinely is the whole answer;
/// 2. **it looks tappable when it is.** A recessed fill, a hairline edge
///    and a chevron -- an [onTap] of `null` drops the chevron and the fill
///    rather than leaving a row that looks live and does nothing;
/// 3. **the glyph carries colour.** A column of grey line icons is the
///    template look the direction rules out, and colour is also what lets
///    someone find the row they want without reading four labels.
class MenuRow extends StatelessWidget {
  /// The glyph in the leading disc.
  final IconData icon;

  /// The heavy line -- what this row leads to. User-visible: pass a
  /// localised string.
  final String label;

  /// The muted line under it: what the destination is *for*, in the user's
  /// terms. User-visible: pass a localised string.
  ///
  /// Leave it out only when the label alone answers "what is behind this?"
  /// -- a row with a subtitle that merely restates its label is noise.
  final String? subtitle;

  /// Colour family of the disc. Keep it stable for a given destination
  /// across every screen that lists it.
  ///
  /// **Never [TakhiAccent.neutral] here.** That family's tint is the same
  /// value as [TakhiSurfaces.field], which is exactly what a tappable row
  /// paints itself with -- so the disc vanishes and the row ends up with a
  /// bare glyph beside neighbours that all have coloured marks. It is a
  /// defect only a rendered screenshot shows, since the glyph is still
  /// perfectly legible; it is the *set* that stops being scannable. Pick the
  /// family that says what kind of destination this is instead --
  /// [TakhiAccent.sky] is the right answer for "somewhere informational or
  /// navigational" and is what neutral usually wanted to mean.
  final TakhiAccent accent;

  /// Tapped. `null` renders the row as a statement rather than a control:
  /// no fill, no chevron, no gesture target.
  final VoidCallback? onTap;

  /// Replaces the default chevron -- a value, a switch, a count. The row's
  /// own gesture still covers it unless the widget handles its own taps.
  final Widget? trailing;

  const MenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.accent = TakhiAccent.gold,
    this.onTap,
    this.trailing,
  }) : assert(
         accent != TakhiAccent.neutral,
         'TakhiAccent.neutral tints the disc with the same colour a MenuRow '
         'fills itself with, so the mark disappears. Pick the family that '
         'says what kind of destination this is -- sky for informational '
         'or navigational.',
       );

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final tappable = onTap != null;
    final detail = subtitle;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TakhiTouch.minTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TakhiSpace.sm,
          vertical: TakhiSpace.sm,
        ),
        child: Row(
          children: [
            AccentDot(icon: icon, accent: accent, size: _kDotSize),
            const SizedBox(width: TakhiSpace.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TakhiType.title.copyWith(color: surfaces.onSheet),
                  ),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: TakhiSpace.xxs / 2),
                    Text(
                      detail,
                      style: TakhiType.support.copyWith(color: surfaces.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: TakhiSpace.xs),
              trailing!,
            ] else if (tappable) ...[
              const SizedBox(width: TakhiSpace.xs),
              Icon(Icons.chevron_right, color: surfaces.muted),
            ],
          ],
        ),
      ),
    );

    final card = DecoratedBox(
      decoration: BoxDecoration(
        // The recessed plane, the same one a tappable row takes on home:
        // "this is a thing you operate" is said by sinking it into the
        // page, not by drawing a box around a label.
        color: tappable ? surfaces.field : null,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(
          color: tappable ? surfaces.hairline : Colors.transparent,
        ),
      ),
      child: content,
    );

    if (!tappable) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: TakhiRadius.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: TakhiRadius.cardAll,
        child: card,
      ),
    );
  }
}
