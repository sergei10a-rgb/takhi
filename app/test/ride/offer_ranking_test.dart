// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/offer_ranking.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

TripReceipt _receipt(String author, String about, String trip) =>
    TripReceipt(
      tripId: trip,
      counterpartyPubkey: about,
      role: 'passenger',
      ratingStars: 5,
      distanceMeters: 1,
      durationSeconds: 1,
      priceMnt: 1,
      comment: '',
      authorPubkey: author,
      createdAt: 0,
    );

RideOffer _offer(String driverPubkey, int priceMnt) => RideOffer(
      driverPubkey,
      RideOfferPayload(
        rideRequestId: 'req1',
        priceMnt: priceMnt,
        etaMinutes: 5,
        vehicleDescription: 'x',
      ),
      1000,
    );

void main() {
  test('ranks a driver with paired trip history above one with none', () {
    final trusted = _offer('D1', 5000);
    final stranger = _offer('D2', 4000);
    final receipts = [
      _receipt('R1', 'D1', 't1'),
      _receipt('D1', 'R1', 't1'),
    ];
    final ranked = rankRideOffers(
      [stranger, trusted],
      receiptsFor: (pubkey) => receipts
          .where((r) =>
              r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey)
          .toList(),
    );
    expect(ranked.first.offer.driverPubkey, 'D1');
    expect(ranked.first.reputation.pairedTripCount, 1);
    expect(ranked.last.offer.driverPubkey, 'D2');
    expect(ranked.last.reputation.pairedTripCount, 0);
  });

  test('viewer-trusted counterparties push a driver higher', () {
    final a = _offer('DA', 5000);
    final b = _offer('DB', 5000);
    final receiptsA = [_receipt('X', 'DA', 't1'), _receipt('DA', 'X', 't1')];
    final receiptsB = [_receipt('Y', 'DB', 't1'), _receipt('DB', 'Y', 't1')];
    final all = [...receiptsA, ...receiptsB];
    final ranked = rankRideOffers(
      [a, b],
      receiptsFor: (pubkey) => all
          .where((r) =>
              r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey)
          .toList(),
      viewerTrusted: {'X'},
    );
    expect(ranked.first.offer.driverPubkey, 'DA');
  });
}
