// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/live_location_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final driver = generateKeyPair(List<int>.filled(32, 103));
  final passenger = generateKeyPair(List<int>.filled(32, 104));

  test('send + watch delivers a position ping scoped to one trip', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = LiveLocationChannel(pool);

    final got = <LiveLocation>[];
    final sub = channel
        .watch(passenger.publicHex, passenger.privateHex, 'trip-1')
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await channel.send(
      senderPrivHex: driver.privateHex,
      recipientPubHex: passenger.publicHex,
      tripId: 'trip-1',
      lat: 47.92,
      lon: 106.91,
      now: 1000,
    );
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, driver.publicHex);
    expect(got.first.tripId, 'trip-1');
    expect(got.first.lat, 47.92);
    expect(got.first.lon, 106.91);
    await sub.cancel();
  });

  test('watch filters by both #p and #d tags', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = LiveLocationChannel(pool);

    channel.watch(passenger.publicHex, passenger.privateHex, 'trip-1');
    final reqFrame =
        jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>;
    final filter = reqFrame[2] as Map<String, dynamic>;
    expect(filter['kinds'], [kKindLiveLocation]);
    expect(filter['#p'], [passenger.publicHex]);
    expect(filter['#d'], ['trip-1']);
  });
}
