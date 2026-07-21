// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/offer_ranking.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_receipt_repository.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  test('collects parsed receipts emitted before the timeout', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final future = repo.receiptsAbout(
      'D1',
      timeout: const Duration(milliseconds: 20),
    );
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
    final signed = signEvent(
      unsigned,
      kp.privateHex,
      auxRand: List<int>.filled(32, 0),
    );
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, signed.toJson()]));

    final receipts = await future;
    expect(receipts.length, 1);
    expect(receipts.first.counterpartyPubkey, 'D1');
  });

  test('skips events that fail to parse as a trip receipt', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final future = repo.receiptsAbout(
      'D1',
      timeout: const Duration(milliseconds: 20),
    );
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
        content: 'x',
      ),
      kp.privateHex,
      auxRand: List<int>.filled(32, 0),
    );
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, wrongKind.toJson()]));

    final receipts = await future;
    expect(receipts, isEmpty);
  });

  test('issues both #p and authors filters, not just #p', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final future = repo.receiptsAbout(
      'D1',
      timeout: const Duration(milliseconds: 20),
    );
    await future;

    final reqFrames = sockets['wss://a']!.sent
        .map((f) => jsonDecode(f) as List<dynamic>)
        .where((f) => f.first == 'REQ')
        .toList();
    expect(reqFrames.length, 2);
    final filters = reqFrames.map((f) => f[2] as Map<String, dynamic>);
    expect(
      filters,
      contains(containsPair('#p', ['D1'])),
      reason: 'must still fetch receipts written ABOUT the subject',
    );
    expect(
      filters,
      contains(containsPair('authors', ['D1'])),
      reason:
          'must also fetch receipts the subject themselves authored, or '
          "computeReputation's reciprocal-pairing check can never match "
          'and pairedTripCount/trustWeight stay 0 forever',
    );
  });

  test(
    'collects receipts authored by the subject about someone else',
    () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final repo = TripReceiptRepository(pool);

      final kp = generateKeyPair(List<int>.filled(32, 83));
      final future = repo.receiptsAbout(
        kp.publicHex,
        timeout: const Duration(milliseconds: 20),
      );
      final reqFrames = sockets['wss://a']!.sent
          .map((f) => jsonDecode(f) as List<dynamic>)
          .where((f) => f.first == 'REQ')
          .toList();
      final authoredSubId = reqFrames[1][1] as String;

      final unsigned = buildTripReceipt(
        pubkey: kp.publicHex,
        now: 1,
        tripId: 't2',
        counterpartyPubkey: 'P1',
        role: 'driver',
        ratingStars: 4,
        distanceMeters: 1,
        durationSeconds: 1,
        priceMnt: 1,
      );
      final signed = signEvent(
        unsigned,
        kp.privateHex,
        auxRand: List<int>.filled(32, 0),
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', authoredSubId, signed.toJson()]),
      );

      final receipts = await future;
      expect(receipts.length, 1);
      expect(receipts.first.authorPubkey, kp.publicHex);
      expect(receipts.first.counterpartyPubkey, 'P1');
    },
  );

  test('repository -> rankRideOffers pairs reciprocal on-relay receipts '
      '(regression for the missing authors-side fetch)', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final driver = generateKeyPair(List<int>.filled(32, 84));
    final passenger = generateKeyPair(List<int>.filled(32, 85));

    final future = repo.receiptsAbout(
      driver.publicHex,
      timeout: const Duration(milliseconds: 20),
    );
    final reqFrames = sockets['wss://a']!.sent
        .map((f) => jsonDecode(f) as List<dynamic>)
        .where((f) => f.first == 'REQ')
        .toList();
    final aboutSubId = reqFrames[0][1] as String;
    final authoredSubId = reqFrames[1][1] as String;

    // The passenger's receipt ABOUT the driver.
    final aboutDriver = signEvent(
      buildTripReceipt(
        pubkey: passenger.publicHex,
        now: 1,
        tripId: 'trip-1',
        counterpartyPubkey: driver.publicHex,
        role: 'passenger',
        ratingStars: 5,
        distanceMeters: 1000,
        durationSeconds: 300,
        priceMnt: 5000,
      ),
      passenger.privateHex,
      auxRand: List<int>.filled(32, 1),
    );
    // The driver's reciprocal receipt about the same trip/passenger --
    // only reachable via the `authors` filter, not `#p`.
    final authoredByDriver = signEvent(
      buildTripReceipt(
        pubkey: driver.publicHex,
        now: 1,
        tripId: 'trip-1',
        counterpartyPubkey: passenger.publicHex,
        role: 'driver',
        ratingStars: 5,
        distanceMeters: 1000,
        durationSeconds: 300,
        priceMnt: 5000,
      ),
      driver.privateHex,
      auxRand: List<int>.filled(32, 2),
    );

    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', aboutSubId, aboutDriver.toJson()]),
    );
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', authoredSubId, authoredByDriver.toJson()]),
    );

    final receipts = await future;

    final offer = RideOffer(
      driver.publicHex,
      const RideOfferPayload(
        rideRequestId: 'req1',
        priceMnt: 5000,
        etaMinutes: 5,
        vehicleDescription: 'x',
      ),
      1000,
    );
    final ranked = rankRideOffers([offer], receiptsFor: (_) => receipts);

    expect(ranked.single.reputation.pairedTripCount, 1);
    expect(ranked.single.reputation.trustWeight, greaterThan(0));
  });
}
