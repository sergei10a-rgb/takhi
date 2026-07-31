// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:latlong2/latlong.dart' as ll;

import '../geo/gps_track.dart';
import '../meter/routing_client.dart';

/// How long the router gets before the app draws the straight line instead.
///
/// Not a spacing token and not arbitrary: the passenger is standing on a
/// step waiting for this, and a mobile connection that accepts the socket
/// and then goes quiet is the ordinary failure -- so the ceiling is set at
/// "long enough for a slow but working connection, short enough that a dead
/// one does not read as a frozen screen". Matches the order of magnitude
/// `estimateTripFare` already uses for the same public endpoint.
const _kRouteTimeout = Duration(seconds: 6);

/// What the map draws between the two ends of a trip, and the two measured
/// facts the screen states about it -- from the same answer, so the line and
/// the figures can never disagree about which route they describe.
///
/// ## Why there is no money on this object
///
/// There used to be a `fareMnt` here, computed from a city "reference"
/// km-rate that lived as a literal in `CityConfig`. Nothing measured it and
/// nobody stood behind it -- its own comment admitted as much -- and the
/// rounder it was made, the more it looked like a figure somebody had
/// checked. A price a passenger reads before naming their own price is not
/// decoration: it anchors the number they type, and an anchor with no source
/// is the app quietly setting the market rate for a city it invented a rate
/// for.
///
/// So the preview carries only what the routing service actually measured:
/// how far the road runs and how long it takes. Both are facts about the
/// *trip*; the price is a fact about a *driver*, and in this app it arrives
/// the only way it honestly can -- as an offer, from a driver, with that
/// driver's own tariff attached.
class TripRoutePreview {
  /// The line to draw, start to finish. Always at least two points, so a
  /// caller never has to handle "there is nothing to draw": offline, it is
  /// the pickup and the destination and nothing between them.
  final List<ll.LatLng> points;

  final int distanceMeters;

  /// How long the router says the drive takes, in seconds, or `null` when
  /// nobody measured it -- which is every offline (straight-line) preview,
  /// and any host that answered without a `duration`.
  ///
  /// Never estimated from the distance. A minutes figure derived from a
  /// straight line and an assumed speed is exactly the kind of invented
  /// number this class exists to keep off the screen.
  final int? durationSeconds;

  /// True when [points] is the straight line rather than a road, and the
  /// distance is therefore the as-the-crow-flies one.
  ///
  /// The UI is *required* to say so -- "ойролцоогоор" -- and to draw the
  /// line broken rather than solid. A confident gold line across a city
  /// block is a claim about which streets a car will take, and offline the
  /// app does not know that.
  final bool isApproximate;

  const TripRoutePreview({
    required this.points,
    required this.distanceMeters,
    required this.isApproximate,
    this.durationSeconds,
  });
}

/// Asks [pathClient] for the road between two points, and falls back to the
/// straight line -- clearly labelled -- on any failure.
///
/// The fallback is the whole design. Every arm of it (no network, a router
/// that finds no route, a host that never answers, an answer with no usable
/// geometry) lands on the same honest place: a broken line between the two
/// ends, a distance from the haversine, no duration at all, and
/// [TripRoutePreview.isApproximate] true. There is no "are we online" check
/// first, for the reason `estimateTripFare` already documents: on a mobile
/// network, attempting the call and catching its failure is the only
/// reliable signal.
Future<TripRoutePreview> loadTripRoutePreview({
  required RoutePathClient pathClient,
  required ll.LatLng pickup,
  required ll.LatLng destination,
  Duration timeout = _kRouteTimeout,
}) async {
  try {
    final routed = await pathClient
        .routePath(
          fromLat: pickup.latitude,
          fromLon: pickup.longitude,
          toLat: destination.latitude,
          toLon: destination.longitude,
        )
        .timeout(timeout);
    // A one-point "route" is not a route. Drawing it would be a line with
    // no length and a distance with nothing behind it, so it is treated as
    // no answer at all rather than passed on to the map.
    if (routed != null && routed.points.length >= 2) {
      final duration = routed.durationSeconds;
      return TripRoutePreview(
        points: routed.points,
        distanceMeters: routed.distanceMeters.round(),
        durationSeconds: duration?.round(),
        isApproximate: false,
      );
    }
  } on Exception {
    // Network error, timeout, or a malformed response -- fall through to
    // the straight line below, which is what the rider gets to see.
  }

  final straightLine = haversineMeters(
    pickup.latitude,
    pickup.longitude,
    destination.latitude,
    destination.longitude,
  );
  return TripRoutePreview(
    points: [pickup, destination],
    distanceMeters: straightLine.round(),
    isApproximate: true,
  );
}
