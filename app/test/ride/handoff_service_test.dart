// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/handoff_service.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final passenger = generateKeyPair(List<int>.filled(32, 91));
  final driver = generateKeyPair(List<int>.filled(32, 92));

  test('sendHandoff mints a trip id and delivers exact location to the '
      'driver', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final dm = RideDmChannel(pool);
    final service = HandoffService(dm);

    final got = <ReceivedHandoff>[];
    final sub = service
        .receiveHandoffs(driver.publicHex, driver.privateHex)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    final tripId = await service.sendHandoff(
      passengerPrivHex: passenger.privateHex,
      driverPubHex: driver.publicHex,
      rideRequestId: 'req1',
      lat: 47.9186,
      lon: 106.9176,
      landmarkText: 'Улаан хаалганы урд',
      now: 1000,
    );

    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(tripId.length, 32);
    expect(got.length, 1);
    expect(got.first.senderPubkey, passenger.publicHex);
    expect(got.first.payload.rideRequestId, 'req1');
    expect(got.first.payload.tripId, tripId);
    expect(got.first.payload.landmarkText, 'Улаан хаалганы урд');
    expect(got.first.payload.plusCode, plusCodeEncode(47.9186, 106.9176));
    await sub.cancel();
  });

  test(
    'a caller-supplied tripId is used verbatim instead of minting one',
    () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = HandoffService(RideDmChannel(pool));

      final tripId = await service.sendHandoff(
        passengerPrivHex: passenger.privateHex,
        driverPubHex: driver.publicHex,
        rideRequestId: 'req1',
        lat: 1,
        lon: 1,
        landmarkText: 'x',
        now: 1000,
        tripId: 'fixed-trip-id',
      );
      expect(tripId, 'fixed-trip-id');
    },
  );
}
