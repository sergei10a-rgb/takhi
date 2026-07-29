// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';
import 'accent_dot.dart';

/// Diameter of the leading marker. Smaller than [PillField]'s dot: a list of
/// these stacks vertically, and a heavier mark would read as a column of
/// buttons.
const _kDotSize = 20.0;

/// The two-line row that states where something is.
///
/// "Суух хаяг" over "Одоогийн байршил" -- a small muted label naming the
/// *kind* of place, and the place itself underneath in the primary weight.
/// The order matters and is fixed here rather than left to call sites: the
/// label is the thing a rider scans for, the value is the thing they read
/// once they have found the right row.
///
/// The row exists as its own component, rather than as a [PillField] with a
/// second line, because these two do different jobs. A pill field is an
/// input the user is about to change; an address row is a statement of what
/// the trip currently is. Tapping one is optional ([onTap]); tapping the
/// other is the whole point.
class AddressRow extends StatelessWidget {
  /// The glyph in the leading marker -- an origin dot, a destination pin, a
  /// waypoint.
  final IconData icon;

  /// The small muted line above the value, naming what kind of address this
  /// is. User-visible: pass a localised string.
  final String label;

  /// The address itself, in the primary weight. User-visible: pass a
  /// localised string (or a name the user typed).
  final String value;

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

  const AddressRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accent = TakhiAccent.gold,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final row = ConstrainedBox(
      // A floor even when the row is not tappable, so a mixed list of
      // tappable and static addresses keeps one rhythm.
      constraints: const BoxConstraints(minHeight: TakhiTouch.minTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TakhiSpace.xs),
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
}
