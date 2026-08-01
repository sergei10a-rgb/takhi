// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../ride/offer_ranking.dart';
import '../theme/takhi_theme.dart';
import 'map_camera_fit.dart';
import 'offered_drivers_layer.dart';
import 'ride_map.dart';

/// How much city to leave around the outermost car.
///
/// A marker is drawn ABOVE its coordinate, so a fit that put the coordinate
/// on the edge would push the car glyph off screen entirely. Slightly wider
/// than `TripRouteMap`'s inset because a car disc is larger than a route
/// endpoint and several of them cluster at the frame edge.
const _kFitInset = 56.0;

/// The above, as the padding `CameraFit` takes.
const _kFitPadding = EdgeInsets.all(_kFitInset);

/// Where the passenger is waiting, and which cars have offered to come.
///
/// Answers the question a list of names cannot: *which of these is close,
/// and which is across the river.* The offer rows underneath still carry
/// price, reputation and ETA -- those read far better as text -- so this
/// sits above them rather than replacing them, and tapping a car opens the
/// same driver page tapping the row does.
///
/// Every car is drawn from `RideOfferPayload.driverGeohash` (geohash-7,
/// ~±76m). Nothing finer is ever received; see that field for why the
/// precision is what it is and why drivers are not broadcast publicly.
class OffersMap extends StatefulWidget {
  final ll.LatLng pickup;
  final List<RankedRideOffer> offers;

  /// The driver whose row is highlighted, if any, so the car and the row
  /// agree about what is selected.
  final String? highlightedDriverPubkey;

  final ValueChanged<RankedRideOffer> onTapDriver;

  const OffersMap({
    super.key,
    required this.pickup,
    required this.offers,
    required this.onTapDriver,
    this.highlightedDriverPubkey,
  });

  /// Whether there is anything worth drawing.
  ///
  /// Asked by the caller BEFORE building this widget, so a passenger
  /// waiting on their first offer gets the waiting message rather than a
  /// grey rectangle with one pin in it. A map is only worth its height once
  /// it has something to compare.
  static bool hasPlottableOffers(List<RankedRideOffer> offers) =>
      offers.any((o) => (o.offer.payload.driverGeohash ?? '').isNotEmpty);

  @override
  State<OffersMap> createState() => _OffersMapState();
}

class _OffersMapState extends State<OffersMap> with MapCameraFit {
  MapController? _ownController;

  @override
  MapController get mapCameraController => _ownController ??= MapController();

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OffersMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Offers arrive one at a time over several seconds. A camera framed on
    // the first one would leave every later car off screen, which is the
    // failure this feature exists to prevent -- so it re-fits whenever the
    // set of plotted cars changes.
    if (_carPoints.length != _pointsOf(oldWidget.offers).length ||
        widget.pickup != oldWidget.pickup) {
      _fit();
    }
  }

  List<ll.LatLng> _pointsOf(List<RankedRideOffer> offers) => [
    for (final ranked in offers)
      if ((ranked.offer.payload.driverGeohash ?? '').isNotEmpty)
        _centreOf(ranked.offer.payload.driverGeohash!),
  ];

  static ll.LatLng _centreOf(String geohash) {
    final centre = geohashDecodeCenter(geohash);
    return ll.LatLng(centre.lat, centre.lon);
  }

  List<ll.LatLng> get _carPoints => _pointsOf(widget.offers);

  /// The pickup is always in the frame, not only the cars.
  ///
  /// A map showing three taxis and not the place they are coming to tells
  /// the passenger nothing about which is nearest -- near to what?
  void _fit() =>
      fitMapCamera([widget.pickup, ..._carPoints], padding: _kFitPadding);

  @override
  Widget build(BuildContext context) => RideMap(
    controller: mapCameraController,
    initialCenter: widget.pickup,
    onMapReady: () {
      markMapCameraReady();
      _fit();
    },
    layers: [
      MarkerLayer(
        markers: [
          Marker(
            point: widget.pickup,
            width: 36,
            height: 36,
            child: const Icon(
              Icons.trip_origin,
              color: TakhiColors.steppe,
              size: 28,
            ),
          ),
        ],
      ),
      OfferedDriversLayer(
        offers: widget.offers,
        highlightedDriverPubkey: widget.highlightedDriverPubkey,
        onTap: widget.onTapDriver,
      ),
    ],
  );
}
