// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import 'offer_service.dart';

/// One offer combined with the reputation of the driver who sent it,
/// sorted by [Reputation.trustWeight] (spec §7.1 step 3: "нэр хүнд + үнэ +
/// ETA-гаар сонгоно" -- reputation is the primary sort key; price/ETA are
/// shown alongside for the passenger to weigh themselves).
class RankedRideOffer {
  final RideOffer offer;
  final Reputation reputation;
  const RankedRideOffer(this.offer, this.reputation);
}

/// Ranks [offers] by each driver's [computeReputation], highest
/// `trustWeight` first. [receiptsFor] looks up the trip receipts already
/// known about a driver pubkey (from [TripReceiptRepository], injected so
/// this function stays pure and independently testable). [viewerTrusted]
/// is the passenger's own web-of-trust set (spec §9).
List<RankedRideOffer> rankRideOffers(
  List<RideOffer> offers, {
  required List<TripReceipt> Function(String driverPubkey) receiptsFor,
  Set<String> viewerTrusted = const {},
}) {
  final ranked = offers
      .map(
        (offer) => RankedRideOffer(
          offer,
          computeReputation(
            subjectPubkey: offer.driverPubkey,
            allReceipts: receiptsFor(offer.driverPubkey),
            viewerTrusted: viewerTrusted,
          ),
        ),
      )
      .toList();
  ranked.sort(
    (a, b) => b.reputation.trustWeight.compareTo(a.reputation.trustWeight),
  );
  return ranked;
}
