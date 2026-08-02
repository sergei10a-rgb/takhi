// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../theme/takhi_theme.dart';

/// Side of the box the dot is drawn in. The painted dot is smaller than
/// this; the box only has to be big enough to hold it plus its halo.
const _kMarkSize = 40.0;

/// Diameter of the dot itself -- the mark that says "the phone is here".
///
/// Map geometry rather than layout spacing, so it is a named constant and
/// not a [TakhiSpace] step: it is measured against a street at zoom 16, and
/// would be wrong at whatever the spacing scale happened to say.
///
/// Raised from 14 to 24 in v0.4.0. 14 was chosen so the mark never hid the
/// junction it stood on, and on a desk that reasoning holds; the driver who
/// field-tested it reported «одоо байгаа тэмдэглэгээ нь хэт жижиг цэг
/// байна» — too small to find, in sunlight, from the driver's seat, while
/// moving. A mark that cannot be found does not need to be unobtrusive.
const _kDotSize = 24.0;

/// Width of the pale ring drawn around the dot.
///
/// The halo is what makes one small mark legible over *any* map tile:
/// without it a dark dot vanishes into a park and a light one into a road.
const _kDotHaloWidth = 4.0;

/// How much of the accent's soft tint the accuracy circle keeps. Low: the
/// ring is a statement about uncertainty, and a solid disc over three
/// blocks of the city would hide the very streets it is talking about.
const _kAccuracyFillOpacity = 0.18;

/// And of the deep foreground, for its outline. Stronger than the fill --
/// the edge is the part that carries the meaning ("somewhere inside here").
const _kAccuracyEdgeOpacity = 0.45;

/// Thickness of that outline.
const _kAccuracyEdgeWidth = 1.5;

/// Where the device says it is, drawn honestly: one mark on the exact
/// coordinate, and -- only when the device actually reported one -- a circle
/// showing how much room that coordinate has to be wrong in.
///
/// The circle is the whole reason this widget exists rather than a bare
/// [Marker]. A dot on its own is a claim of certainty, and a GPS fix taken
/// indoors or off a cell tower can be four hundred metres out while looking
/// exactly as confident as one taken under open sky. A rider who cannot see
/// that difference cannot tell "the app has found me" from "the app has
/// guessed"; a rider who can, knows to drag the pin themselves.
///
/// Nothing is drawn for an accuracy the platform did not report
/// ([accuracyMeters] `null`, or zero, which is how geolocator says
/// "unknown"). Inventing a default radius would be the one thing worse than
/// showing none: a precision claim the app cannot back.
///
/// **Colour is pinned to the light palette on purpose.** The OSM tiles under
/// this layer are the same light raster whether the app is in its light or
/// dark theme, so a marker that followed the app theme would resolve to the
/// dark palette's pale blue and disappear into a pale map. The mark has to
/// stay legible against the tiles, not against the app.
class DeviceLocationLayer extends StatelessWidget {
  /// Where the device says it is.
  final ll.LatLng position;

  /// The radius, in metres, the true position lies within -- `null` when
  /// the platform did not say.
  final double? accuracyMeters;

  const DeviceLocationLayer({
    super.key,
    required this.position,
    this.accuracyMeters,
  });

  @override
  Widget build(BuildContext context) {
    // "Sky" is this palette's informational/navigational family, which is
    // exactly what a position readout is -- and it keeps the brand gold for
    // the point being *set* and the steppe green for the ride itself, so
    // three different marks on one map never mean the same thing.
    final accent = takhiAccentColors(TakhiAccent.sky, Brightness.light);
    final accuracy = accuracyMeters;

    return Stack(
      children: [
        if (accuracy != null && accuracy > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: position,
                radius: accuracy,
                // Metres, not pixels: the uncertainty is a distance on the
                // ground, so it has to shrink as the rider zooms out. A
                // pixel radius would claim a different accuracy at every
                // zoom level.
                useRadiusInMeter: true,
                color: accent.tint.withValues(alpha: _kAccuracyFillOpacity),
                borderColor: accent.onTint.withValues(
                  alpha: _kAccuracyEdgeOpacity,
                ),
                borderStrokeWidth: _kAccuracyEdgeWidth,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: position,
              width: _kMarkSize,
              height: _kMarkSize,
              child: _DeviceDot(color: accent.onTint),
            ),
          ],
        ),
      ],
    );
  }
}

/// The mark itself: a filled dot inside a pale ring.
///
/// The ring is not decoration. One flat dot is legible over roughly half the
/// tiles a city map draws and invisible over the rest; a light collar around
/// a dark centre is legible over all of them, which is why every map app
/// ever shipped draws it this way.
class _DeviceDot extends StatelessWidget {
  final Color color;

  const _DeviceDot({required this.color});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: _kDotSize,
      height: _kDotSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: TakhiColors.paper, width: _kDotHaloWidth),
      ),
    ),
  );
}
