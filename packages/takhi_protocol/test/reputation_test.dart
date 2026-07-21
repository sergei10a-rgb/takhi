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

  test(
      'without any viewer trust, a Sybil ring of 9 fresh throwaway pubkeys '
      'scores IDENTICALLY to 9 genuinely distinct riders (documented limit)',
      () {
    // This is a documented, expected limitation, not a bug: a freshly-minted
    // pubkey rating the subject exactly once is, on receipt data alone,
    // cryptographically indistinguishable from a genuine new rider doing the
    // same thing. No pure function of `allReceipts` can tell them apart --
    // see the design note atop computeReputation(). Ring: S with fakes
    // F0..F8 all cross-signing, one trip each.
    final ring = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      ring.add(r('F$i', 'S', 'ring$i', 5));
      ring.add(r('S', 'F$i', 'ring$i', 5));
    }
    final ringRep = computeReputation(subjectPubkey: 'S', allReceipts: ring);

    // Distinct real riders R0..R8, none trusted, but genuinely distinct --
    // same shape as the ring above (9 distinct authors, 1 trip each).
    final distinct = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      distinct.add(r('R$i', 'D', 'real$i', 5));
      distinct.add(r('D', 'R$i', 'real$i', 5));
    }
    final distinctRep =
        computeReputation(subjectPubkey: 'D', allReceipts: distinct);

    expect(distinctRep.trustWeight, equals(ringRep.trustWeight));

    // The ONLY thing that lets the honest set win is a viewer-supplied trust
    // anchor (Rule 3 / web-of-trust) -- that's the real Sybil defense.
    final trustedView = computeReputation(
        subjectPubkey: 'D', allReceipts: distinct, viewerTrusted: {'R0', 'R1'});
    expect(trustedView.trustWeight, greaterThan(ringRep.trustWeight));

    // A ring where the SAME single fake signs many trips collapses (Rule 2:
    // reusing one pubkey diminishes sharply, since it's the cheapest attack).
    final lazyRing = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      lazyRing.add(r('F', 'S', 'lazy$i', 5));
      lazyRing.add(r('S', 'F', 'lazy$i', 5));
    }
    final lazyRep =
        computeReputation(subjectPubkey: 'S', allReceipts: lazyRing);
    expect(lazyRep.trustWeight, lessThan(distinctRep.trustWeight));
  });

  test(
      'minting more distinct throwaway pubkeys (no viewer trust) yields '
      'sub-linear, not linear/unbounded, weight growth (Rule 4)', () {
    Reputation repFor(int fakeCount) {
      final receipts = <TripReceipt>[];
      for (var i = 0; i < fakeCount; i++) {
        receipts.add(r('F$i', 'S', 't$i', 5));
        receipts.add(r('S', 'F$i', 't$i', 5));
      }
      return computeReputation(subjectPubkey: 'S', allReceipts: receipts);
    }

    final rep9 = repFor(9);
    final rep50 = repFor(50);

    // A purely linear scheme (the old bug) would give rep50/rep9 == 50/9
    // (~5.56x). Growth must now be strictly sub-linear in identity count.
    final linearRatio = 50 / 9;
    final actualRatio = rep50.trustWeight / rep9.trustWeight;
    expect(actualRatio, lessThan(linearRatio));
  });
}
