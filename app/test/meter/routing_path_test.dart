// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/meter/routing_client.dart';

/// One OSRM answer with a three-point GeoJSON geometry, in OSRM's own
/// `[lon, lat]` order -- the axis order that is trivially easy to read
/// backwards, and which would put Ulaanbaatar in the Indian Ocean.
const _geoJsonBody = '''
{
  "code": "Ok",
  "routes": [
    {
      "distance": 5321.4,
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [106.9176, 47.9186],
          [106.9300, 47.9200],
          [106.9500, 47.9250]
        ]
      }
    }
  ]
}
''';

void main() {
  test(
    'reads an OSRM GeoJSON route into lat/lon points in that order',
    () async {
      late Uri requested;
      final routing = OsrmRoutingClient(
        'https://router.example',
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response(_geoJsonBody, 200);
        }),
      );

      final path = await routing.routePath(
        fromLat: 47.9186,
        fromLon: 106.9176,
        toLat: 47.9250,
        toLon: 106.9500,
      );

      expect(path, isNotNull);
      expect(path!.distanceMeters, 5321.4);
      expect(path.points, const [
        ll.LatLng(47.9186, 106.9176),
        ll.LatLng(47.9200, 106.9300),
        ll.LatLng(47.9250, 106.9500),
      ]);
      // Without both of these OSRM answers with no geometry at all and the
      // route silently degrades to the straight-line fallback forever.
      expect(requested.query, contains('overview=full'));
      expect(requested.query, contains('geometries=geojson'));
    },
  );

  test('returns null when the service answers with a non-200', () async {
    final routing = OsrmRoutingClient(
      'https://router.example',
      httpClient: MockClient((_) async => http.Response('nope', 503)),
    );

    expect(
      await routing.routePath(fromLat: 1, fromLon: 2, toLat: 3, toLon: 4),
      isNull,
    );
  });

  test('returns null when the service finds no route', () async {
    final routing = OsrmRoutingClient(
      'https://router.example',
      httpClient: MockClient(
        (_) async => http.Response('{"code":"NoRoute","routes":[]}', 200),
      ),
    );

    expect(
      await routing.routePath(fromLat: 1, fromLon: 2, toLat: 3, toLon: 4),
      isNull,
    );
  });

  test('returns null rather than a half-drawn line when the geometry is '
      'missing or malformed', () async {
    final routing = OsrmRoutingClient(
      'https://router.example',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"code":"Ok","routes":[{"distance":100,"geometry":null}]}',
          200,
        ),
      ),
    );

    expect(
      await routing.routePath(fromLat: 1, fromLon: 2, toLat: 3, toLon: 4),
      isNull,
    );
  });
}
