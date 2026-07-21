// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/ride_request_service.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final passenger = generateKeyPair(List<int>.filled(32, 61));
  final driver = generateKeyPair(List<int>.filled(32, 62));

  test('publishRequest publishes a PoW-mined, signed ride request',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = RideRequestService(pool, RideDmChannel(pool));

    final event = await service.publishRequest(
      privHex: passenger.privateHex,
      now: 1000,
      pickupLat: 47.9186,
      pickupLon: 106.9176,
      destLat: 47.9100,
      destLon: 106.9000,
      offeredMnt: 5000,
      powDifficulty: 4, // small so the test stays fast
    );

    expect(event.kind, kKindRideRequest);
    expect(event.pubkey, passenger.publicHex);
    expect(event.sig, isNotNull);
    expect(verifyEvent(event), isTrue);
    expect(countLeadingZeroBits(event.id!), greaterThanOrEqualTo(4));
    expect(parseRideRequest(event).offeredMnt, 5000);

    final sentFrame =
        jsonDecode(sockets['wss://a']!.sent.single) as List<dynamic>;
    expect(sentFrame[0], 'EVENT');
    expect((sentFrame[1] as Map<String, dynamic>)['kind'], kKindRideRequest);
  });

  test('cancelWithDriver sends a cancel DM to exactly that driver',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final dm = RideDmChannel(pool);
    final service = RideRequestService(pool, dm);

    final got = <InboundRideDm>[];
    final sub =
        dm.inbox(driver.publicHex, driver.privateHex).listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await service.cancelWithDriver(
      privHex: passenger.privateHex,
      driverPubHex: driver.publicHex,
      rideRequestId: 'req1',
      now: 1000,
      reason: 'олдлоо',
    );
    // The publish above went to the same fake socket; replay it to the
    // subscriber exactly as a relay would echo a matching event back.
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, passenger.publicHex);
    expect(got.first.payload, isA<RideCancelPayload>());
    expect((got.first.payload as RideCancelPayload).reason, 'олдлоо');
    await sub.cancel();
  });
}
