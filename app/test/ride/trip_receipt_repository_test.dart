// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/trip_receipt_repository.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  test('collects parsed receipts emitted before the timeout', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final future = repo.receiptsAbout('D1',
        timeout: const Duration(milliseconds: 20));
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    final kp = generateKeyPair(List<int>.filled(32, 81));
    final unsigned = buildTripReceipt(
      pubkey: kp.publicHex,
      now: 1,
      tripId: 't1',
      counterpartyPubkey: 'D1',
      role: 'passenger',
      ratingStars: 5,
      distanceMeters: 1,
      durationSeconds: 1,
      priceMnt: 1,
    );
    final signed =
        signEvent(unsigned, kp.privateHex, auxRand: List<int>.filled(32, 0));
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, signed.toJson()]));

    final receipts = await future;
    expect(receipts.length, 1);
    expect(receipts.first.counterpartyPubkey, 'D1');
  });

  test('skips events that fail to parse as a trip receipt', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final future = repo.receiptsAbout('D1',
        timeout: const Duration(milliseconds: 20));
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    final kp = generateKeyPair(List<int>.filled(32, 82));
    final wrongKind = signEvent(
        NostrEvent(
            pubkey: kp.publicHex,
            createdAt: 1,
            kind: 1,
            tags: [],
            content: 'x'),
        kp.privateHex,
        auxRand: List<int>.filled(32, 0));
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', subId, wrongKind.toJson()]));

    final receipts = await future;
    expect(receipts, isEmpty);
  });
}
