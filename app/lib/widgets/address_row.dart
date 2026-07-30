// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';
import 'accent_dot.dart';

/// The two-line row that states where something is.
///
/// "Суух хаяг" over "Одоогийн байршил" -- a small muted label naming the
/// *kind* of place, and the place itself underneath in the primary weight.
/// The order matters and is fixed here rather than left to call sites: the
/// label is the thing a rider scans for, the value is the thing they read
/// once they have found the right row.
///
/// [value] is always the *human* name of the place, and [detail] is where a
/// machine form of it goes. That split is the whole reason the row has three
/// tiers rather than two: this app derives a Plus Code from coordinates and
/// never asks a geocoding service what is standing there (spec §6 -- sending
/// a rider's exact position to a third-party server is the one thing the
/// privacy design forbids), so the precise string it *can* produce is
/// "8PV8WW99+C2X", which nobody reads as a place. Leading with a name and
/// keeping the code underneath gets both: a row a rider understands at a
/// glance and the exact point SOS and trip sharing actually transmit.
///
/// The row exists as its own component, rather than as a [PillField] with a
/// second line, because these two do different jobs. A pill field is an
/// input the user is about to change; an address row is a statement of what
/// the trip currently is. Tapping one is optional ([onTap]); tapping the
/// other is the whole point.
class AddressRow extends StatelessWidget {
  /// Diameter of the leading marker. Smaller than [PillField]'s dot: a list
  /// of these stacks vertically, and a heavier mark would read as a column
  /// of buttons.
  ///
  /// Public because a caller that stacks two rows draws the rail between
  /// their markers itself, and that rail has to sit on the same axis the
  /// markers do.
  static const dotSize = 20.0;

  /// The glyph in the leading marker -- an origin dot, a destination pin, a
  /// waypoint.
  final IconData icon;

  /// The small muted line above the value, naming what kind of address this
  /// is. User-visible: pass a localised string.
  final String label;

  /// The address itself, in the primary weight. User-visible: pass a
  /// localised string (or a name the user typed).
  final String value;

  /// The smaller, muted line under [value]: the same place stated precisely
  /// rather than readably -- a Plus Code, a grid reference, a distance.
  ///
  /// Optional, and left out entirely when null or empty rather than
  /// rendered as a blank line, so a row with nothing to add underneath
  /// keeps the two-tier rhythm of every other row beside it.
  final String? detail;

  /// Colour family of the marker. Conventionally [TakhiAccent.steppe] for
  /// where the trip starts and [TakhiAccent.gold] for where it ends, so the
  /// two are told apart by colour as well as by position.
  final TakhiAccent accent;

  /// Makes the whole row tappable -- for "change this address". When null
  /// the row is a static statement and takes no gesture target.
  final VoidCallback? onTap;

  /// Optional widget at the right edge: a chevron, a distance, an edit
  /// affordance.
  final Widget? trailing;

  /// Announced instead of the row's own two lines, for a tappable row whose
  /// label and value do not say what tapping it does ("Очих газар" /
  /// "Хаашаа явах вэ?" does not say that tapping opens the ride flow).
  ///
  /// User-visible: pass a localised string. Ignored by the static variant,
  /// which is a statement and not a control.
  final String? semanticsLabel;

  const AddressRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.accent = TakhiAccent.gold,
    this.onTap,
    this.trailing,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final detailText = detail;
    final row = ConstrainedBox(
      // A floor even when the row is not tappable, so a mixed list of
      // tappable and static addresses keeps one rhythm.
      constraints: const BoxConstraints(minHeight: TakhiTouch.minTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TakhiSpace.xs),
        child: Row(
          children: [
            AccentDot(icon: icon, accent: accent, size: dotSize),
            const SizedBox(width: TakhiSpace.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TakhiType.micro.copyWith(color: surfaces.muted),
                  ),
                  const SizedBox(height: TakhiSpace.xxs / 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TakhiType.title.copyWith(color: surfaces.onSheet),
                  ),
                  if (detailText != null && detailText.isNotEmpty) ...[
                    const SizedBox(height: TakhiSpace.xxs / 2),
                    Text(
                      detailText,
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
    final tappable = Material(
      color: Colors.transparent,
      borderRadius: TakhiRadius.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: TakhiRadius.cardAll,
        child: row,
      ),
    );

    if (semanticsLabel == null) return tappable;
    return Semantics(button: true, label: semanticsLabel, child: tappable);
  }
}
