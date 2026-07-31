// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// A map shown as an *object on a page* rather than as the page itself.
///
/// Home, the driver's inbox and the running meter all give the map the whole
/// screen with a sheet floating over it. The booking wizard cannot: its
/// steps have a heading above the map and an action below it, and a map that
/// bled to the edges there would read as a screen the step is trapped
/// inside. So on those steps it becomes what every other block on them is --
/// rounded, hairlined, clipped to its corners.
///
/// One widget rather than the frame written out at each site, because the
/// two places that need it (the point picker and the trip preview) sit two
/// taps apart in the same flow, and a rider walking between them must not
/// see the same map wearing two slightly different frames.
class MapCard extends StatelessWidget {
  /// How tall the window onto the map is.
  ///
  /// The caller's decision, not this widget's: how much city has to be
  /// visible at once depends on whether the map is showing one point or a
  /// whole trip.
  final double height;

  final Widget child;

  const MapCard({super.key, required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return DecoratedBox(
      // Painted over the clipped map rather than behind it: a border on an
      // ancestor of a `ClipRRect` is covered by the tiles it clips.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: ClipRRect(
        borderRadius: TakhiRadius.cardAll,
        child: SizedBox(height: height, child: child),
      ),
    );
  }
}
