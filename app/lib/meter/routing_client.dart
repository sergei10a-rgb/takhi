// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

/// Fetches a real driving-route distance from a public OSRM/Valhalla-
/// compatible routing service (spec §7.4 step 2: "нийтийн routing
/// үйлчилгээгээр ... жинхэнэ маршрутын зай"), when the device is online.
/// Abstracted so [estimateTripFare] (`fare_estimate.dart`) is testable
/// without a real HTTP call.
abstract interface class RoutingClient {
  /// Returns the routed driving distance in meters, or `null` if the
  /// service could not compute a route (e.g. no road connectivity between
  /// the two points) — distinct from throwing, which signals the service
  /// itself was unreachable or returned a malformed response.
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  });
}

/// A driving route as a shape on the map, not just a length: how far it
/// runs, how long it takes, and the ordered points it runs through.
class RoutedPath {
  final double distanceMeters;

  /// How long the router thinks the drive takes, in seconds, or `null` when
  /// the service did not say.
  ///
  /// Carried because it is the *other* measured fact about a trip, and the
  /// one a rider actually weighs a price against: five kilometres across
  /// open road and five kilometres through Peace Avenue at six in the
  /// evening are the same distance and not remotely the same journey. It is
  /// nullable rather than defaulted for the same reason `GpsFix
  /// .accuracyMeters` is -- a routing host that omits `duration` has told
  /// us nothing, and a made-up number would be indistinguishable on screen
  /// from a measured one.
  final double? durationSeconds;

  /// The road, start to finish. Always at least two points -- a "route"
  /// with one point is a rendering fault waiting to happen, so
  /// [OsrmRoutingClient.routePath] rejects one rather than passing it on.
  final List<ll.LatLng> points;

  const RoutedPath({
    required this.distanceMeters,
    required this.points,
    this.durationSeconds,
  });
}

/// Companion to [RoutingClient] for callers that need the *shape* of a
/// route rather than only its length -- i.e. anything that draws it.
///
/// Deliberately a second interface instead of a second method on
/// [RoutingClient]. The fare estimator only ever wants a number, and every
/// test double that stands in for it would have to grow a geometry method
/// it has no use for; splitting them keeps "how much will this cost" and
/// "which streets is it" as the two separate questions they are.
abstract interface class RoutePathClient {
  /// The driving route between two points, or `null` when the service
  /// could not produce one (no connectivity between the points, no
  /// geometry in the answer, or a malformed response). Throws only when
  /// the service itself could not be reached -- callers treat both as "draw
  /// the straight line and say so".
  Future<RoutedPath?> routePath({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  });
}

/// Default public routing endpoints (OSRM demo-server-compatible
/// `/route/v1/driving/{lon},{lat};{lon},{lat}` REST shape) — same public-
/// infrastructure category as the default relay/tile URLs (spec §11: "OSM
/// tile/relay-тэй ижил зарчмаар"), user-editable, never author-run.
/// Finalizing this list is an open protocol question (spec §16.7); this is
/// the working MVP default.
const List<String> defaultRoutingEndpoints = [
  'https://router.project-osrm.org',
];

/// Calls an OSRM-compatible `/route/v1/driving/...` endpoint.
class OsrmRoutingClient implements RoutingClient, RoutePathClient {
  final String baseUrl;
  final http.Client _http;

  OsrmRoutingClient(this.baseUrl, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/$fromLon,$fromLat;$toLon,$toLat'
      '?overview=false',
    );
    final response = await _http.get(uri);
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['code'] != 'Ok') return null;
    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final first = routes.first;
    if (first is! Map<String, dynamic>) return null;
    final distance = first['distance'];
    if (distance is! num) return null;
    return distance.toDouble();
  }

  @override
  Future<RoutedPath?> routePath({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    // `overview=full` is what makes OSRM return a geometry at all, and
    // `geometries=geojson` is what makes it plain coordinates instead of
    // the encoded-polyline string the API defaults to -- which would need a
    // decoder of its own, in a file whose whole job is one HTTP call.
    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/$fromLon,$fromLat;$toLon,$toLat'
      '?overview=full&geometries=geojson',
    );
    final response = await _http.get(uri);
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['code'] != 'Ok') return null;
    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final first = routes.first;
    if (first is! Map<String, dynamic>) return null;
    final distance = first['distance'];
    if (distance is! num) return null;
    final points = _geoJsonLineString(first['geometry']);
    if (points == null) return null;
    // Missing or non-numeric `duration` is not a failure: OSRM always sends
    // one, but this endpoint is user-editable (see [defaultRoutingEndpoints])
    // and a compatible host that omits it still gave a perfectly good road.
    // The screen simply says nothing about time in that case.
    final duration = first['duration'];
    return RoutedPath(
      distanceMeters: distance.toDouble(),
      durationSeconds: duration is num ? duration.toDouble() : null,
      points: points,
    );
  }
}

/// A GeoJSON `LineString` as map points, or `null` if it is not one.
///
/// GeoJSON orders every coordinate `[longitude, latitude]` -- the opposite
/// of how the rest of this app says it, and of how a human reads a pair of
/// numbers off a map. Reading it backwards does not crash and does not look
/// wrong in code; it silently plots Ulaanbaatar in the Indian Ocean. That is
/// why the swap happens here, once, with a test on it, rather than at each
/// call site.
List<ll.LatLng>? _geoJsonLineString(Object? geometry) {
  if (geometry is! Map<String, dynamic>) return null;
  final coordinates = geometry['coordinates'];
  if (coordinates is! List || coordinates.length < 2) return null;
  final points = <ll.LatLng>[];
  for (final pair in coordinates) {
    if (pair is! List || pair.length < 2) return null;
    final lon = pair[0];
    final lat = pair[1];
    if (lon is! num || lat is! num) return null;
    points.add(ll.LatLng(lat.toDouble(), lon.toDouble()));
  }
  return points;
}
