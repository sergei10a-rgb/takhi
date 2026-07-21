// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('ride request has geohash, expiration, price tags', () {
    final e = buildRideRequest(
        pubkey: 'ab' * 32,
        now: 1000,
        pickupLat: 47.9186,
        pickupLon: 106.9176,
        destLat: 47.9100,
        destLon: 106.9000,
        offeredMnt: 5000);
    expect(e.kind, kKindRideRequest);
    expect(e.tags.firstWhere((t) => t.first == 'g')[1].length, 6);
    expect(e.tags.firstWhere((t) => t.first == 'expiration')[1], '1240');
    expect(e.tags.firstWhere((t) => t.first == 'price')[1], '5000');
  });

  test('trip receipt round-trips through parse', () {
    final e = buildTripReceipt(
        pubkey: 'cd' * 32,
        now: 2000,
        tripId: 'trip-xyz',
        counterpartyPubkey: 'ef' * 32,
        role: 'passenger',
        ratingStars: 5,
        distanceMeters: 6000,
        durationSeconds: 900,
        priceMnt: 9000,
        comment: 'сайн');
    final p = parseTripReceipt(e);
    expect(p.tripId, 'trip-xyz');
    expect(p.counterpartyPubkey, 'ef' * 32);
    expect(p.role, 'passenger');
    expect(p.ratingStars, 5);
  });

  test('parseTripReceipt rejects wrong kind', () {
    final wrong = NostrEvent(
        pubkey: 'ab' * 32, createdAt: 1, kind: 1, tags: [], content: '');
    expect(() => parseTripReceipt(wrong), throwsFormatException);
  });
}
