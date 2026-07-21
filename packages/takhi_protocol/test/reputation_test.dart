// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

TripReceipt r(String author, String about, String trip, int stars) =>
    TripReceipt(
      tripId: trip,
      counterpartyPubkey: about,
      role: 'x',
      ratingStars: stars,
      distanceMeters: 1,
      durationSeconds: 1,
      priceMnt: 1,
      comment: '',
      authorPubkey: author,
      createdAt: 0,
    );

void main() {
  test('unpaired self-praise carries no weight', () {
    // subject S authored praise about itself via alt A, but A never
    // counter-signed -> not paired.
    final receipts = [r('A', 'S', 't1', 5)]; // only one side
    final rep = computeReputation(subjectPubkey: 'S', allReceipts: receipts);
    expect(rep.pairedTripCount, 0);
    expect(rep.trustWeight, 0);
  });

  test('one genuine paired trip counts once', () {
    final receipts = [
      r('P', 'S', 't1', 5), // passenger P rates driver S
      r('S', 'P', 't1', 5), // driver S rates passenger P (same trip)
    ];
    final rep = computeReputation(subjectPubkey: 'S', allReceipts: receipts);
    expect(rep.pairedTripCount, 1);
    expect(rep.averageRating, 5.0);
    expect(rep.trustWeight, greaterThan(0));
  });

  test('Sybil ring of 10 mutual ratings scores far below 10 distinct riders',
      () {
    // Ring: S with fakes F0..F8 all cross-signing
    final ring = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      ring.add(r('F$i', 'S', 'ring$i', 5));
      ring.add(r('S', 'F$i', 'ring$i', 5));
    }
    final ringRep = computeReputation(subjectPubkey: 'S', allReceipts: ring);

    // Distinct real riders R0..R8, none trusted, but genuinely distinct
    final distinct = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      distinct.add(r('R$i', 'D', 'real$i', 5));
      distinct.add(r('D', 'R$i', 'real$i', 5));
    }
    final distinctRep =
        computeReputation(subjectPubkey: 'D', allReceipts: distinct);

    // Both have 9 paired trips, but with viewer trust the honest one wins.
    final trustedView = computeReputation(
        subjectPubkey: 'D', allReceipts: distinct, viewerTrusted: {'R0', 'R1'});
    expect(trustedView.trustWeight, greaterThan(ringRep.trustWeight));
    // And a ring where the SAME single fake signs many trips collapses:
    final lazyRing = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      lazyRing.add(r('F', 'S', 'lazy$i', 5));
      lazyRing.add(r('S', 'F', 'lazy$i', 5));
    }
    final lazyRep =
        computeReputation(subjectPubkey: 'S', allReceipts: lazyRing);
    expect(lazyRep.trustWeight, lessThan(distinctRep.trustWeight));
  });
}
