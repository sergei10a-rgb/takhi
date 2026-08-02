// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import 'device_location_layer.dart';
import 'map_camera_fit.dart';
import 'ride_map.dart';

/// Height of the counterparty glyph, and the side of the box it lives in.
///
/// Map geometry rather than layout spacing, so a named constant and not a
/// [TakhiSpace] step -- it is measured against the streets under it, and
/// matches the mark `NearbyRequestsLayer` already drops on a driver's map so
/// the same fact reads at the same weight on every screen it appears on.
/// Raised from 36 in v0.4.0, for the reason the device dot was: the driver
/// who field-tested it could not pick the marks out at a glance in a moving
/// car. A passenger watching a car approach and a driver watching a route
/// are both reading this from arm's length in daylight.
const _kCounterpartyMarkSize = 52.0;

/// Left/right/top margin kept clear of the two marks when the camera is
/// fitted to them. Generous because a marker is drawn above its coordinate:
/// a fit that put the coordinate on the top edge would push the glyph off
/// screen entirely.
/// Glyph on the "follow me again" control.
const _kFollowGlyphSize = 18.0;

const _kTrackFitEdgeInset = 48.0;

/// Bottom margin for the same fit. Far larger than the others, and not a
/// spacing token, because it is not spacing: the trip sheet is anchored over
/// the bottom of this map, so this is roughly how much of the map that sheet
/// hides. Fitting without it would centre the marks in the map's
/// *rectangle* and park the rider's own dot behind the fare. Same value, and
/// the same reasoning, as the running taximeter's own fit.
const _kTrackFitSheetInset = 300.0;

/// The two above, as the padding `CameraFit` takes.
const _kTrackFitPadding = EdgeInsets.fromLTRB(
  _kTrackFitEdgeInset,
  _kTrackFitEdgeInset,
  _kTrackFitEdgeInset,
  _kTrackFitSheetInset,
);

/// The map a rider and a driver stare at for the whole trip: where I am,
/// where the other one is, and a camera that keeps both of us on screen.
///
/// It replaces a `RideMap` that was given `initialCenter: selfPosition ??
/// cityCentre` and nothing else. That expression reads as "follow me" and
/// does the opposite: `MapOptions.initialCenter` is honoured on the single
/// frame the map is created, which on this screen is the frame *before* the
/// first GPS fix arrives -- so the camera locked onto the city centre and
/// stayed there while the rider's own mark drove off the edge. A trip that
/// starts two kilometres from Sükhbaatar Square was photographed, tested and
/// shipped with no mark on the map at all, and nobody could see it, because
/// the only screenshot of this screen was taken with the marks off-frame.
///
/// Three rules it keeps:
///
/// 1. **Both marks are always framed.** Every rebuild re-fits the camera to
///    whichever positions are known, through the app's one
///    [MapCameraFit] behaviour, with the trip sheet's own height padded out
///    of the bottom so nothing lands behind it.
/// 2. **"Where am I" looks the same here as everywhere else.** The rider's
///    own position is [DeviceLocationLayer] -- the same sky-blue dot in the
///    same pale collar, with the same accuracy ring, that the booking
///    wizard's map and the location pickers draw. It used to be a flat gold
///    `my_location` cross unique to this screen, which meant one fact had
///    two glyphs and gold meant two different things.
/// 3. **The other person is drawn as what they are.** A car when the
///    counterparty is the driver, a person-pin when it is the passenger --
///    both in the app's steppe green, which is what "the other side of this
///    ride" is coloured everywhere else. Two marks that differ only in hue
///    are one mark to anyone glancing at a phone in daylight.
class TripTrackingMap extends StatefulWidget {
  /// Where this device says it is, and how much room that answer has to be
  /// wrong in. Both `null` until the first fix lands.
  final ll.LatLng? selfPosition;
  final double? selfAccuracyMeters;

  /// The other side's last reported position, or `null` until one arrives
  /// over the live-location channel. Nothing is drawn for a position that
  /// does not exist -- a mark at a guessed point is worse than no mark.
  final ll.LatLng? counterpartyPosition;

  /// True when the person on the other side is the driver (i.e. this device
  /// is the passenger's). Chooses the counterparty glyph, and only that.
  final bool counterpartyIsDriver;

  /// Where to look while nothing at all is known yet -- the city centre, in
  /// practice. Never a stand-in for a position: no mark is drawn here.
  final ll.LatLng fallbackCenter;

  /// Supplied by tests that need to read the camera back. Production callers
  /// leave it null and this widget owns one.
  final MapController? controller;

  const TripTrackingMap({
    super.key,
    required this.selfPosition,
    required this.counterpartyPosition,
    required this.counterpartyIsDriver,
    required this.fallbackCenter,
    this.selfAccuracyMeters,
    this.controller,
  });

  @override
  State<TripTrackingMap> createState() => _TripTrackingMapState();
}

class _TripTrackingMapState extends State<TripTrackingMap>
    with MapCameraFit<TripTrackingMap> {
  /// Only set when this widget made the controller itself -- disposing one
  /// the caller owns would break the next screen that uses it.
  MapController? _ownController;

  @override
  MapController get mapCameraController =>
      widget.controller ?? (_ownController ??= MapController());

  /// Every point the camera has to hold: whichever of the two are known.
  List<ll.LatLng> get _trackedPoints => [
    ?widget.selfPosition,
    ?widget.counterpartyPosition,
  ];

  @override
  void didUpdateWidget(covariant TripTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) forgetMapCamera();
    // A trip is a stream of positions, so this fires on most rebuilds --
    // which is the point. The guard is only against the rebuilds that are
    // *not* movement (the fare tick, a voice note arriving, a theme change),
    // since re-issuing an identical fit fights the user's own panning.
    if (widget.selfPosition == oldWidget.selfPosition &&
        widget.counterpartyPosition == oldWidget.counterpartyPosition) {
      return;
    }
    fitMapCamera(_trackedPoints, padding: _kTrackFitPadding);
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final self = widget.selfPosition;
    final counterparty = widget.counterpartyPosition;

    return Stack(
      children: [
        Positioned.fill(child: _buildMap(self, counterparty)),
        if (isMapFollowingSuspended)
          Positioned(
            top: TakhiSpace.sm,
            right: TakhiSpace.sm,
            child: _FollowMeButton(
              onPressed: () {
                resumeMapFollowing();
                fitMapCamera(_trackedPoints, padding: _kTrackFitPadding);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMap(ll.LatLng? self, ll.LatLng? counterparty) {
    return RideMap(
      controller: mapCameraController,
      // A passenger watching a car approach zooms in on the street it is
      // turning into, and the app must not drag them back on the next
      // ping. Reported from the field on the driver's own map; the same
      // rule applies to both ends of a trip.
      onUserPanned: suspendMapFollowing,
      // Honoured for exactly one frame, until the fit below lands -- and
      // only ever actually seen on the frames before any position is known
      // at all.
      initialCenter: self ?? counterparty ?? widget.fallbackCenter,
      onMapReady: () {
        markMapCameraReady();
        // Both halves matter. The flag alone would leave the camera on
        // `initialCenter` until the *next* position arrives, which on a
        // stationary phone with a settled fix is never.
        fitMapCamera(_trackedPoints, padding: _kTrackFitPadding);
      },
      layers: [
        if (counterparty != null)
          MarkerLayer(
            markers: [
              Marker(
                point: counterparty,
                width: _kCounterpartyMarkSize,
                height: _kCounterpartyMarkSize,
                child: _CounterpartyMark(isDriver: widget.counterpartyIsDriver),
              ),
            ],
          ),
        // Last, so it is drawn over the other mark: this device's own
        // position is the thing its owner orients by, and it must never end
        // up underneath anything.
        if (self != null)
          DeviceLocationLayer(
            position: self,
            accuracyMeters: widget.selfAccuracyMeters,
          ),
      ],
    );
  }
}

/// The other side of the ride, as one mark.
///
/// Steppe green either way -- the app's "this is the ride" colour, the same
/// one the phase chip turns while a trip is running and the same one a
/// driver's nearby-calls map drops on a waiting passenger. The *shape* is
/// what says which of the two is out there.
/// "Follow me again", shown only while the camera is in the user's hands.
class _FollowMeButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _FollowMeButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    return Semantics(
      button: true,
      label: l.mapRecentreSemanticsLabel,
      child: Material(
        color: surfaces.sheet,
        shape: const RoundedRectangleBorder(
          borderRadius: TakhiRadius.pillAll,
        ),
        elevation: 2,
        child: InkWell(
          borderRadius: TakhiRadius.pillAll,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TakhiSpace.sm,
              vertical: TakhiSpace.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location,
                  size: _kFollowGlyphSize,
                  color: surfaces.onSheet,
                ),
                const SizedBox(width: TakhiSpace.xxs),
                Text(
                  l.mapRecentreAction,
                  style: TakhiType.label.copyWith(color: surfaces.onSheet),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterpartyMark extends StatelessWidget {
  final bool isDriver;

  const _CounterpartyMark({required this.isDriver});

  @override
  Widget build(BuildContext context) => Icon(
    isDriver ? Icons.directions_car : Icons.person_pin_circle,
    color: TakhiColors.steppe,
    size: _kCounterpartyMarkSize,
    // A white outline under the glyph, so it stays findable over a park,
    // a motorway and a block of flats alike. Steppe green on an OSM tile
    // is legible in three of those four cases, which is not enough for the
    // mark somebody is looking for while driving.
    shadows: const [
      Shadow(color: TakhiColors.paper, blurRadius: 6),
      Shadow(color: TakhiColors.paper, blurRadius: 3),
    ],
  );
}
