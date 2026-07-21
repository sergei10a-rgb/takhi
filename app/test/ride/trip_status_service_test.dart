// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi/ride/trip_status_service.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final driver = generateKeyPair(List<int>.filled(32, 101));
  final passenger = generateKeyPair(List<int>.filled(32, 102));

  test('sendStatus delivers a phase transition to the passenger', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = TripStatusService(RideDmChannel(pool));

    final got = <ReceivedTripStatus>[];
    final sub = service
        .watchStatus(passenger.publicHex, passenger.privateHex)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await service.sendStatus(
      driverPrivHex: driver.privateHex,
      passengerPubHex: passenger.publicHex,
      tripId: 'trip-1',
      phase: TripPhase.arrived,
      now: 1000,
    );
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, driver.publicHex);
    expect(got.first.tripId, 'trip-1');
    expect(got.first.phase, TripPhase.arrived);
    await sub.cancel();
  });
}
