// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:http/http.dart' as http;

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
class OsrmRoutingClient implements RoutingClient {
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
}
