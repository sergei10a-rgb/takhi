// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/offer_ranking.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

TripReceipt _receipt(String author, String about, String trip) => TripReceipt(
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

RideOffer _offer(String driverPubkey, int priceMnt, {int etaMinutes = 5}) =>
    RideOffer(
      driverPubkey,
      RideOfferPayload(
        rideRequestId: 'req1',
        priceMnt: priceMnt,
        etaMinutes: etaMinutes,
        vehicleDescription: 'x',
      ),
      1000,
    );

/// Both halves of one trip, so `computeReputation` can pair them.
List<TripReceipt> _pair(String rider, String driver, String trip) => [
  _receipt(rider, driver, trip),
  _receipt(driver, rider, trip),
];

void main() {
  test('ranks a driver with paired trip history above one with none', () {
    final trusted = _offer('D1', 5000);
    final stranger = _offer('D2', 4000);
    final receipts = [_receipt('R1', 'D1', 't1'), _receipt('D1', 'R1', 't1')];
    final ranked = rankRideOffers(
      [stranger, trusted],
      receiptsFor: (pubkey) => receipts
          .where(
            (r) => r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey,
          )
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
          .where(
            (r) => r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey,
          )
          .toList(),
      viewerTrusted: {'X'},
    );
    expect(ranked.first.offer.driverPubkey, 'DA');
  });

  // The rider gets to say what "best" means. Until these existed the answer
  // was hard-coded to reputation and the list silently overruled a rider who
  // was choosing on price.
  group('the sort the rider picked', () {
    final receipts = _pair('R1', 'D1', 't1');
    List<TripReceipt> receiptsFor(String pubkey) => receipts
        .where(
          (r) => r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey,
        )
        .toList();

    // D1 has history, costs the most and is the slowest; D2 is cheapest;
    // D3 is soonest. No two sort keys agree, so each ordering is a claim
    // about the key alone.
    final withHistory = _offer('D1', 9000, etaMinutes: 9);
    final cheapest = _offer('D2', 4000, etaMinutes: 6);
    final soonest = _offer('D3', 6000, etaMinutes: 2);
    final offers = [withHistory, cheapest, soonest];

    test('reputation is the default, and it is not price order', () {
      final ranked = rankRideOffers(offers, receiptsFor: receiptsFor);

      expect(ranked.first.offer.driverPubkey, 'D1');
    });

    test('sorting by price puts the cheapest offer first', () {
      final ranked = rankRideOffers(
        offers,
        receiptsFor: receiptsFor,
        sort: OfferSort.price,
      );

      expect(ranked.map((r) => r.offer.driverPubkey).toList(), [
        'D2',
        'D3',
        'D1',
      ]);
    });

    test('sorting by arrival time puts the soonest driver first', () {
      final ranked = rankRideOffers(
        offers,
        receiptsFor: receiptsFor,
        sort: OfferSort.eta,
      );

      expect(ranked.map((r) => r.offer.driverPubkey).toList(), [
        'D3',
        'D2',
        'D1',
      ]);
    });

    test('reputation is still computed under every sort, so the cards can '
        'state it whatever the list is ordered by', () {
      final ranked = rankRideOffers(
        offers,
        receiptsFor: receiptsFor,
        sort: OfferSort.price,
      );

      final d1 = ranked.firstWhere((r) => r.offer.driverPubkey == 'D1');
      expect(d1.reputation.pairedTripCount, 1);
    });
  });

  test('offers that tie on the sort key keep the order they arrived in, so '
      'the list cannot reshuffle under a thumb', () {
    // Three identical prices: without an explicit tiebreak `List.sort` is
    // free to permute them, and this list rebuilds on every arriving offer.
    final offers = [_offer('A', 5000), _offer('B', 5000), _offer('C', 5000)];

    for (final sort in OfferSort.values) {
      final ranked = rankRideOffers(
        offers,
        receiptsFor: (_) => const [],
        sort: sort,
      );
      expect(
        ranked.map((r) => r.offer.driverPubkey).toList(),
        ['A', 'B', 'C'],
        reason: 'ties must resolve to arrival order under $sort',
      );
    }
  });

  group('which card wears the "most trusted" badge', () {
    test('nobody, while every driver is new -- the badge would be pinning a '
        'judgement onto arrival order', () {
      final ranked = rankRideOffers([
        _offer('A', 5000),
        _offer('B', 4000),
      ], receiptsFor: (_) => const []);

      expect(mostTrustedIndex(ranked), isNull);
    });

    test('nobody, while the top two are tied', () {
      final all = [..._pair('X', 'DA', 't1'), ..._pair('Y', 'DB', 't2')];
      final ranked = rankRideOffers(
        [_offer('DA', 5000), _offer('DB', 5000)],
        receiptsFor: (pubkey) => all
            .where(
              (r) => r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey,
            )
            .toList(),
      );

      expect(mostTrustedIndex(ranked), isNull);
    });

    // The reason this is an identity and not "index 0": under a price sort
    // the most-trusted driver is somewhere down the list, and a badge tied to
    // position would have hopped onto whoever was cheapest.
    test('follows the driver, not the first row, when the rider sorts by '
        'price', () {
      final receipts = _pair('R1', 'D1', 't1');
      final ranked = rankRideOffers(
        [_offer('D1', 9000), _offer('D2', 4000)],
        receiptsFor: (pubkey) => receipts
            .where(
              (r) => r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey,
            )
            .toList(),
        sort: OfferSort.price,
      );

      expect(ranked.first.offer.driverPubkey, 'D2');
      expect(mostTrustedIndex(ranked), 1);
    });
  });
}
