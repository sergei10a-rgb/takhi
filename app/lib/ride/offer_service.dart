// SPDX-License-Identifier: AGPL-3.0-or-later
import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';

/// A driver's offer as the passenger sees it: who sent it (the verified
/// sender from `RideDmChannel.inbox`, never a self-reported field) plus
/// the decoded fields.
class RideOffer {
  final String driverPubkey;
  final RideOfferPayload payload;
  final int receivedAt;
  const RideOffer(this.driverPubkey, this.payload, this.receivedAt);
}

/// Sends a driver's offer to a passenger (spec §7.1 step 3) and lets a
/// passenger collect the stream of offers addressed to them. Reputation-
/// ranking the collected offers is [rankRideOffers] (`offer_ranking.dart`)
/// -- kept separate so it stays pure and relay-free for testing.
class OfferService {
  final RideDmChannel _dm;
  OfferService(this._dm);

  Future<void> sendOffer({
    required String driverPrivHex,
    required String passengerPubHex,
    required RideOfferPayload offer,
    required int now,
  }) async {
    await _dm.send(
      senderPrivHex: driverPrivHex,
      recipientPubHex: passengerPubHex,
      payload: offer,
      now: now,
    );
  }

  /// Every incoming offer addressed to the passenger, across all of
  /// their active ride requests -- callers filter by
  /// `RideOffer.payload.rideRequestId` for the request they're currently
  /// showing offers for.
  Stream<RideOffer> receiveOffers(
      String passengerPubHex, String passengerPrivHex) {
    return _dm
        .inbox(passengerPubHex, passengerPrivHex)
        .where((dm) => dm.payload is RideOfferPayload)
        .map((dm) => RideOffer(
              dm.senderPubkey,
              dm.payload as RideOfferPayload,
              dm.receivedAt,
            ));
  }
}
