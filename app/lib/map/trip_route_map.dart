// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../theme/takhi_theme.dart';
import 'device_location_layer.dart';
import 'map_camera_fit.dart';
import 'ride_map.dart';
import 'trip_route_preview.dart';

/// Height of the pickup pin glyph, and the side of the box it lives in.
///
/// Map geometry rather than layout spacing, so a named constant and not a
/// [TakhiSpace] step -- it is measured against the streets under it. Matches
/// the picker's centre pin so the same trip reads at the same weight on
/// every screen it appears on.
const _kEndMarkSize = 34.0;

/// Width of the line joining the two ends.
const _kRouteStrokeWidth = 4.0;

/// Length of one dash, and of the gap after it, when the line is only the
/// straight-line guess. A ratio rather than two independent numbers: a dash
/// as long as its gap is the pattern that reads as "provisional" instead of
/// as "a road with markings".
const _kGuessDashLength = 10.0;
const _kGuessDashGap = 8.0;

/// The broken line an offline, straight-line guess is drawn with.
///
/// `final` rather than `const` because `StrokePattern.dashed` validates its
/// own segment list at construction, which a constant expression cannot do.
final _guessedLinePattern = StrokePattern.dashed(
  segments: const [_kGuessDashLength, _kGuessDashGap],
);

/// Margin kept clear around the trip when the camera is fitted to it.
///
/// Generous, and for one specific reason: a marker is drawn *above* its
/// coordinate, so a fit that put the coordinate exactly on the top edge
/// would push the glyph off screen and leave the rider looking at a route
/// that ends in nothing.
const _kFitInset = 48.0;

/// The above, as the padding `CameraFit` takes.
const _kFitPadding = EdgeInsets.all(_kFitInset);

/// The trip, as a picture: where it starts, where it ends, the road between
/// them, and -- once the device says so -- where the rider is standing while
/// they look at it.
///
/// This is the thing the flow was missing. A passenger who had picked two
/// points had, until this widget, never seen either of them together: the
/// pickers show one point at a time under a fixed centre pin, and the step
/// that asks for a price showed two lines of text. There was nothing on
/// screen that could answer "is that the right side of the river", which is
/// the question a wrong destination gets caught by.
///
/// Three rules it keeps:
///
/// 1. **Both ends are always framed.** The camera is fitted to the two
///    points (plus the route once there is one), so no zoom the caller
///    picks can hide half the trip. Through [MapCameraFit], deliberately --
///    one camera-following behaviour in this app, not one per screen.
/// 2. **The ends look different.** Same shapes the rest of the app already
///    uses for the same two facts: the steppe-green ring `AddressRow` draws
///    beside a pickup, the gold pin `LocationPickerField` sets a point with.
/// 3. **A guessed line says it is a guess.** [TripRoutePreview.isApproximate]
///    draws the line broken instead of solid; the caller states it in words
///    as well. A solid line is a claim about which streets the car takes,
///    and offline the app does not have one.
class TripRouteMap extends StatefulWidget {
  final ll.LatLng pickup;
  final ll.LatLng destination;

  /// The route and its cost, or `null` while the router is still being
  /// asked. Null draws the two ends and no line -- rather than a
  /// placeholder line, which would be a road the app has not been told
  /// about.
  final TripRoutePreview? preview;

  /// Where the device says it is, once a fix exists, and how much room that
  /// answer has to be wrong in. See [DeviceLocationLayer].
  final ll.LatLng? devicePosition;
  final double? deviceAccuracyMeters;

  /// Supplied by tests that need to read the camera back. Production
  /// callers leave it null and this widget owns one.
  final MapController? controller;

  const TripRouteMap({
    super.key,
    required this.pickup,
    required this.destination,
    this.preview,
    this.devicePosition,
    this.deviceAccuracyMeters,
    this.controller,
  });

  @override
  State<TripRouteMap> createState() => _TripRouteMapState();
}

class _TripRouteMapState extends State<TripRouteMap>
    with MapCameraFit<TripRouteMap> {
  /// Only set when this widget made the controller itself -- disposing one
  /// the caller owns would break the next screen that uses it.
  MapController? _ownController;

  @override
  MapController get mapCameraController =>
      widget.controller ?? (_ownController ??= MapController());

  @override
  void didUpdateWidget(covariant TripRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) forgetMapCamera();
    // The route arriving a second after the step opened is the normal case,
    // and it usually extends well past the straight line between the two
    // ends -- so the fit has to be redone rather than left where the two
    // bare points put it.
    if (widget.pickup == oldWidget.pickup &&
        widget.destination == oldWidget.destination &&
        identical(widget.preview, oldWidget.preview)) {
      return;
    }
    _fitToTrip();
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  /// Every point the camera has to hold.
  ///
  /// The two ends are listed explicitly even when a route exists: a routed
  /// geometry starts at the nearest *road*, which on a big block can be a
  /// hundred metres from the pin the rider actually set, and it is the pin
  /// they are checking.
  List<ll.LatLng> get _fitPoints => [
    widget.pickup,
    widget.destination,
    ...?widget.preview?.points,
  ];

  /// Frames the whole trip, through the app's one camera-following
  /// behaviour ([MapCameraFit]) -- including its answer for the case a
  /// rider who has not moved the destination map yet is in, where both ends
  /// are the same point and there is no extent to fit.
  void _fitToTrip() => fitMapCamera(_fitPoints, padding: _kFitPadding);

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final device = widget.devicePosition;

    return RideMap(
      controller: mapCameraController,
      // Honoured for exactly one frame, until the fit below lands. The
      // midpoint rather than either end, so that single frame is already
      // looking at the right part of the city instead of jumping across it.
      initialCenter: _midpoint,
      onMapReady: () {
        markMapCameraReady();
        // Both halves matter. The flag alone would leave the camera on
        // `initialCenter` forever whenever the trip never changes again --
        // which is the common case here, since both ends are already picked
        // by the time this map is built.
        _fitToTrip();
      },
      layers: [
        if (preview != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: preview.points,
                color: TakhiColors.gold,
                strokeWidth: _kRouteStrokeWidth,
                // The honesty signal, and the reason it is the *pattern*
                // rather than the colour: a broken line reads as
                // provisional to everyone, in every culture, without a
                // legend -- while a second colour would just look like a
                // second kind of road.
                pattern: preview.isApproximate
                    ? _guessedLinePattern
                    : const StrokePattern.solid(),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.pickup,
              width: _kEndMarkSize,
              height: _kEndMarkSize,
              child: const _PickupMark(),
            ),
            Marker(
              point: widget.destination,
              width: _kEndMarkSize,
              height: _kEndMarkSize,
              // The glyph stands ON the point rather than centred over it:
              // a pin's tip is its measurement, and centring it would put
              // the drawn point some seventeen pixels north of the one the
              // rider actually picked -- at street zoom, the wrong side of
              // a building entrance.
              alignment: Alignment.topCenter,
              child: const _DestinationMark(),
            ),
          ],
        ),
        // Last, so it is drawn over the route: the rider's own position is
        // the thing they orient by, and a line crossing it would break the
        // one mark on the map that answers "where am I".
        if (device != null)
          DeviceLocationLayer(
            position: device,
            accuracyMeters: widget.deviceAccuracyMeters,
          ),
      ],
    );
  }

  /// Halfway between the two ends -- good enough for the one frame before
  /// the camera is fitted properly.
  ll.LatLng get _midpoint => ll.LatLng(
    (widget.pickup.latitude + widget.destination.latitude) / 2,
    (widget.pickup.longitude + widget.destination.longitude) / 2,
  );
}

/// Where the rider gets in: the same steppe-green ring `AddressRow` draws
/// beside a pickup everywhere else in the app.
class _PickupMark extends StatelessWidget {
  const _PickupMark();

  @override
  Widget build(BuildContext context) => const Icon(
    Icons.trip_origin,
    color: TakhiColors.steppe,
    size: _kEndMarkSize,
  );
}

/// Where they get out: the gold pin the pickers set a point with. A
/// different shape *and* a different colour from [_PickupMark] -- two marks
/// that differ only in hue are one mark to anyone glancing at a phone in
/// daylight.
class _DestinationMark extends StatelessWidget {
  const _DestinationMark();

  @override
  Widget build(BuildContext context) => const Icon(
    Icons.location_pin,
    color: TakhiColors.gold,
    size: _kEndMarkSize,
  );
}
