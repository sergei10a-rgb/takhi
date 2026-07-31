// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/geo/gps_track.dart';
import 'package:takhi/map/trip_route_preview.dart';
import 'package:takhi/meter/routing_client.dart';

const _pickup = ll.LatLng(47.9186, 106.9176);
const _destination = ll.LatLng(47.9250, 106.9500);

/// A [RoutePathClient] whose single answer the test dictates -- including
/// "never answers", which is what a dead OSRM host actually looks like.
class _ScriptedPathClient implements RoutePathClient {
  final Future<RoutedPath?> Function() _answer;
  int calls = 0;

  _ScriptedPathClient(this._answer);

  @override
  Future<RoutedPath?> routePath({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) {
    calls++;
    return _answer();
  }
}

void main() {
  group('a routing service that answers', () {
    test('draws the road the router returned, not the crow line', () async {
      const bend = ll.LatLng(47.9200, 106.9300);
      final client = _ScriptedPathClient(
        () async => const RoutedPath(
          distanceMeters: 5000,
          points: [_pickup, bend, _destination],
        ),
      );

      final preview = await loadTripRoutePreview(
        pathClient: client,
        pickup: _pickup,
        destination: _destination,
      );

      expect(preview.points, [_pickup, bend, _destination]);
      expect(preview.distanceMeters, 5000);
      expect(preview.isApproximate, isFalse);
    });

    test('carries the driving time the router measured', () async {
      // The other half of what a trip is, and the half that replaced an
      // invented price: "seven kilometres" is two different journeys at
      // nine in the morning and at midnight.
      final client = _ScriptedPathClient(
        () async => const RoutedPath(
          distanceMeters: 5000,
          durationSeconds: 762.4,
          points: [_pickup, _destination],
        ),
      );

      final preview = await loadTripRoutePreview(
        pathClient: client,
        pickup: _pickup,
        destination: _destination,
      );

      expect(preview.durationSeconds, 762);
    });

    test('leaves the driving time unknown when the host did not send one, '
        'rather than deriving one', () async {
      final client = _ScriptedPathClient(
        () async => const RoutedPath(
          distanceMeters: 5000,
          points: [_pickup, _destination],
        ),
      );

      final preview = await loadTripRoutePreview(
        pathClient: client,
        pickup: _pickup,
        destination: _destination,
      );

      expect(
        preview.durationSeconds,
        isNull,
        reason:
            'A duration guessed from distance and an assumed speed is '
            'indistinguishable on screen from a measured one.',
      );
    });
  });

  group('a routing service that does not answer', () {
    /// Everything the fallback must be true of, whatever went wrong: a line
    /// is still drawn, it is the straight one, and it says so.
    void expectStraightLineFallback(TripRoutePreview preview) {
      expect(
        preview.points,
        [_pickup, _destination],
        reason:
            'Offline still has to draw something -- a rider with no route '
            'is exactly the rider who needs to see the two ends joined.',
      );
      expect(
        preview.isApproximate,
        isTrue,
        reason:
            'The straight line is not the road. Claiming otherwise is the '
            'false precision this flag exists to prevent.',
      );
      expect(
        preview.distanceMeters,
        haversineMeters(
          _pickup.latitude,
          _pickup.longitude,
          _destination.latitude,
          _destination.longitude,
        ).round(),
      );
      expect(
        preview.durationSeconds,
        isNull,
        reason:
            'Nobody drove the straight line and nobody timed it. A minutes '
            'figure here would be pure invention.',
      );
    }

    Future<TripRoutePreview> load(_ScriptedPathClient client) =>
        loadTripRoutePreview(
          pathClient: client,
          pickup: _pickup,
          destination: _destination,
          timeout: const Duration(milliseconds: 30),
        );

    test(
      'falls back to the straight line when the host is unreachable',
      () async {
        final preview = await load(
          _ScriptedPathClient(() async => throw Exception('no network')),
        );
        expectStraightLineFallback(preview);
      },
    );

    test(
      'falls back when the router finds no route between the two points',
      () async {
        final preview = await load(_ScriptedPathClient(() async => null));
        expectStraightLineFallback(preview);
      },
    );

    test(
      'falls back rather than hanging when the host never replies',
      () async {
        // A mobile connection that accepts the socket and then goes silent is
        // the common failure, and it is the one an un-bounded await turns into
        // a screen that never finishes loading.
        final preview = await load(
          _ScriptedPathClient(
            () => Future.delayed(const Duration(seconds: 30)),
          ),
        );
        expectStraightLineFallback(preview);
      },
    );

    test('falls back when the router answers with a degenerate one-point '
        'geometry', () async {
      final preview = await load(
        _ScriptedPathClient(
          () async => const RoutedPath(distanceMeters: 800, points: [_pickup]),
        ),
      );
      expectStraightLineFallback(preview);
    });
  });

  test('two identical points still yield a drawable two-point line', () async {
    final client = _ScriptedPathClient(() async => null);
    final preview = await loadTripRoutePreview(
      pathClient: client,
      pickup: _pickup,
      destination: _pickup,
    );

    expect(preview.points, hasLength(2));
    expect(preview.distanceMeters, 0);
  });
}
