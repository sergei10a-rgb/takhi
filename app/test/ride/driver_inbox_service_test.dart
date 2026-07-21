// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/driver_inbox_service.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

NostrEvent _signedRequest({
  required KeyPair kp,
  required int now,
  required double pickupLat,
  required double pickupLon,
  int expirySeconds = 240,
}) {
  final unsigned = buildRideRequest(
    pubkey: kp.publicHex,
    now: now,
    pickupLat: pickupLat,
    pickupLon: pickupLon,
    destLat: pickupLat,
    destLon: pickupLon,
    expirySeconds: expirySeconds,
  );
  return signEvent(unsigned, kp.privateHex, auxRand: List<int>.filled(32, 0));
}

void main() {
  // Sukhbaatar Square, Ulaanbaatar.
  const driverLat = 47.9186, driverLon = 106.9176;

  test("subscribes on the driver's own geohash cell plus its 8 neighbors",
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = DriverInboxService(pool);

    service.nearbyRequests(
        driverLat: driverLat, driverLon: driverLon, nowSeconds: () => 0);
    final reqFrame =
        jsonDecode(sockets['wss://a']!.sent.single) as List<dynamic>;
    final filterJson = reqFrame[2] as Map<String, dynamic>;
    final cells = (filterJson['#g'] as List<dynamic>).cast<String>();
    expect(cells.length, 9); // own cell + 8 neighbors
    expect(
        cells.contains(geohashEncode(driverLat, driverLon, precision: 6)),
        isTrue);
  });

  test('yields a parsed, unexpired ride request', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = DriverInboxService(pool);
    final passenger = generateKeyPair(List<int>.filled(32, 71));

    final got = <RideRequestListing>[];
    final sub = service
        .nearbyRequests(
            driverLat: driverLat, driverLon: driverLon, nowSeconds: () => 1100)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    final event = _signedRequest(
        kp: passenger, now: 1000, pickupLat: driverLat, pickupLon: driverLon);
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, event.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.rideRequestId, event.id);
    expect(got.first.request.pickupGeohash,
        geohashEncode(driverLat, driverLon, precision: 6));
    await sub.cancel();
  });

  test("drops a request whose NIP-40 expiration has already passed",
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = DriverInboxService(pool);
    final passenger = generateKeyPair(List<int>.filled(32, 72));

    final got = <RideRequestListing>[];
    // now (9999) is well past now(1000)+expirySeconds(240)=1240.
    final sub = service
        .nearbyRequests(
            driverLat: driverLat, driverLon: driverLon, nowSeconds: () => 9999)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    final event = _signedRequest(
        kp: passenger, now: 1000, pickupLat: driverLat, pickupLon: driverLon);
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, event.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got, isEmpty);
    await sub.cancel();
  });
}
