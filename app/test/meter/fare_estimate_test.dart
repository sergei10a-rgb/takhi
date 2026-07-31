// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/meter/fare_estimate.dart';
import 'package:takhi/meter/routing_client.dart';

class _FakeRoutingClient implements RoutingClient {
  final Future<double?> Function() _onCall;
  _FakeRoutingClient(this._onCall);

  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => _onCall();
}

void main() {
  test('estimateTripFare uses the routed distance when available', () async {
    final routing = _FakeRoutingClient(() async => 10000);
    final estimate = await estimateTripFare(
      routingClient: routing,
      mntPerKm: 1000,
      fromLat: 0,
      fromLon: 0,
      toLat: 1,
      toLon: 1,
    );
    expect(estimate.mnt, 10000);
    expect(estimate.isApproximate, isFalse);
  });

  test('estimateTripFare falls back to the offline estimate when the '
      'routing client throws', () async {
    final routing = _FakeRoutingClient(() async => throw Exception('offline'));
    final estimate = await estimateTripFare(
      routingClient: routing,
      mntPerKm: 1000,
      fromLat: 0,
      fromLon: 0,
      toLat: 0,
      toLon: 1,
    );
    expect(estimate.isApproximate, isTrue);
    // haversine(0,0 -> 0,1) ~111195m * 1.35 * 1 mnt/m -> ~150,113
    expect(estimate.mnt, closeTo(150113, 50));
  });

  test(
    'estimateTripFare falls back when the routing client returns null',
    () async {
      final routing = _FakeRoutingClient(() async => null);
      final estimate = await estimateTripFare(
        routingClient: routing,
        mntPerKm: 500,
        fromLat: 0,
        fromLon: 0,
        toLat: 0,
        toLon: 1,
      );
      expect(estimate.isApproximate, isTrue);
    },
  );

  test('estimateTripFare falls back when the routing client exceeds the '
      'timeout', () async {
    final routing = _FakeRoutingClient(
      () => Future.delayed(const Duration(milliseconds: 50), () => 5000.0),
    );
    final estimate = await estimateTripFare(
      routingClient: routing,
      mntPerKm: 500,
      fromLat: 0,
      fromLon: 0,
      toLat: 0,
      toLon: 1,
      timeout: const Duration(milliseconds: 5),
    );
    expect(estimate.isApproximate, isTrue);
  });
}
