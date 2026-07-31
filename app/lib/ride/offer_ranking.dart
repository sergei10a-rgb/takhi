// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import 'offer_service.dart';

/// One offer combined with the reputation of the driver who sent it.
class RankedRideOffer {
  final RideOffer offer;
  final Reputation reputation;
  const RankedRideOffer(this.offer, this.reputation);
}

/// What the passenger asked the offer list to be ordered by.
///
/// Three, and exactly three, because these are the three facts the app
/// actually holds about an offer: the driver's paired-receipt standing (spec
/// §9), the price they named, and the minutes they said they are away.
/// Nothing here is a blended "best match" score -- a weighted mix of
/// incomparable things is precisely the sort of judgement a dispatcher makes
/// on your behalf, and the whole point of this screen is that the rider makes
/// it themselves.
enum OfferSort {
  /// [Reputation.trustWeight], highest first. The default, because it is the
  /// one ordering a rider cannot reproduce by eye: price and ETA are printed
  /// on every card and can be scanned, while standing is computed from
  /// receipts fetched off the relays.
  reputation,

  /// [RideOfferPayload.priceMnt], lowest first.
  price,

  /// [RideOfferPayload.etaMinutes], lowest first.
  eta,
}

/// Ranks [offers] by [sort], pairing each with its driver's
/// [computeReputation].
///
/// [receiptsFor] looks up the trip receipts already known about a driver
/// pubkey (from [TripReceiptRepository], injected so this function stays pure
/// and independently testable). [viewerTrusted] is the passenger's own
/// web-of-trust set (spec §9).
///
/// Reputation is computed for every offer whatever the sort is: the cards
/// state a driver's standing regardless of what the list is ordered by, and a
/// rider who sorts by price still needs to see who the cheapest driver is.
///
/// Every comparator ends in the offer's *arrival index*, so ties resolve to
/// the order the offers came in and the list is stable. Without it `List.sort`
/// -- which Dart does not promise is stable -- was free to shuffle equally
/// ranked offers between rebuilds, and this list rebuilds on every arriving
/// offer and every receipt that lands. A row that moves under a thumb reaching
/// for it is worse than a row in the wrong order.
List<RankedRideOffer> rankRideOffers(
  List<RideOffer> offers, {
  required List<TripReceipt> Function(String driverPubkey) receiptsFor,
  Set<String> viewerTrusted = const {},
  OfferSort sort = OfferSort.reputation,
}) {
  final ranked = offers.indexed
      .map(
        (entry) => (
          index: entry.$1,
          value: RankedRideOffer(
            entry.$2,
            computeReputation(
              subjectPubkey: entry.$2.driverPubkey,
              allReceipts: receiptsFor(entry.$2.driverPubkey),
              viewerTrusted: viewerTrusted,
            ),
          ),
        ),
      )
      .toList();

  int primary(RankedRideOffer a, RankedRideOffer b) => switch (sort) {
    OfferSort.reputation => b.reputation.trustWeight.compareTo(
      a.reputation.trustWeight,
    ),
    OfferSort.price => a.offer.payload.priceMnt.compareTo(
      b.offer.payload.priceMnt,
    ),
    OfferSort.eta => a.offer.payload.etaMinutes.compareTo(
      b.offer.payload.etaMinutes,
    ),
  };

  ranked.sort((a, b) {
    final byKey = primary(a.value, b.value);
    return byKey != 0 ? byKey : a.index.compareTo(b.index);
  });
  return ranked.map((entry) => entry.value).toList();
}

/// Which entry of [ranked] belongs to the single most-trusted driver, or
/// `null` when no such driver exists.
///
/// `null` in two cases, and both of them matter:
///
///  * nobody has any paired history yet, so every `trustWeight` is 0 and a
///    "most trusted" badge would be pinning a judgement onto arrival order;
///  * the top two are tied, so the badge would point at one of two equals.
///
/// Deliberately an identity question rather than "is this row first": the
/// badge marks the *most trusted driver*, and that claim stays true when the
/// rider sorts the list by price instead. Tied to position it would have
/// silently migrated to whichever offer happened to be cheapest.
int? mostTrustedIndex(List<RankedRideOffer> ranked) {
  if (ranked.isEmpty) return null;
  var bestIndex = 0;
  var bestWeight = ranked.first.reputation.trustWeight;
  var tied = false;
  for (var i = 1; i < ranked.length; i++) {
    final weight = ranked[i].reputation.trustWeight;
    if (weight > bestWeight) {
      bestWeight = weight;
      bestIndex = i;
      tied = false;
    } else if (weight == bestWeight) {
      tied = true;
    }
  }
  if (bestWeight <= 0 || tied) return null;
  return bestIndex;
}
