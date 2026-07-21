// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:takhi/meter/routing_client.dart';

void main() {
  test('routeDistanceMeters parses a successful OSRM response', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/route/v1/driving/106.9,47.9;107.0,48.0');
      return http.Response(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {'distance': 12345.6},
          ],
        }),
        200,
      );
    });
    final routing = OsrmRoutingClient(
      'https://router.project-osrm.org',
      httpClient: client,
    );
    final distance = await routing.routeDistanceMeters(
      fromLat: 47.9,
      fromLon: 106.9,
      toLat: 48.0,
      toLon: 107.0,
    );
    expect(distance, 12345.6);
  });

  test('routeDistanceMeters returns null on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('', 503));
    final routing = OsrmRoutingClient('https://x', httpClient: client);
    final distance = await routing.routeDistanceMeters(
      fromLat: 0,
      fromLon: 0,
      toLat: 1,
      toLon: 1,
    );
    expect(distance, isNull);
  });

  test('routeDistanceMeters returns null when the service reports no '
      'route', () async {
    final client = MockClient(
      (request) async =>
          http.Response(jsonEncode({'code': 'NoRoute', 'routes': []}), 200),
    );
    final routing = OsrmRoutingClient('https://x', httpClient: client);
    final distance = await routing.routeDistanceMeters(
      fromLat: 0,
      fromLon: 0,
      toLat: 1,
      toLon: 1,
    );
    expect(distance, isNull);
  });
}
