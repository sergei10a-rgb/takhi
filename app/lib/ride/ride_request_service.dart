// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';
import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';

/// Default NIP-13 proof-of-work difficulty for a published ride request
/// (spec §6: "NIP-13 PoW" on kind 20177) -- mines in well under a second
/// on a phone, but makes flooding the relay network with junk requests
/// non-free. The final value is an open protocol question (spec §16.3);
/// this is the working MVP default, matching the difficulty Plan 1's own
/// `minePow` test calls "trivially fast".
const int kRideRequestPowDifficulty = 8;

/// A cancellation the local side received: the verified sender (recovered
/// by `nip17Unwrap`, never a self-reported field) and the payload.
///
/// The sender is the half that matters. `rideRequestId` travels on a public
/// kind-20177 event, so anyone who watched one go by can name it; only the
/// pubkey says *who* is calling the ride off, and a driver's screen must
/// key on that or a stranger can cancel somebody else's job.
class ReceivedRideCancel {
  final String senderPubkey;
  final RideCancelPayload payload;
  const ReceivedRideCancel(this.senderPubkey, this.payload);
}

/// Publishes a passenger's ride request (spec §7.1 step 1: pick points,
/// optional price, publish with PoW and a 4-minute expiry) and carries
/// cancellations (spec §7.5) in both directions.
///
/// ## What "cancel" can and cannot mean here
///
/// There is no retraction. The public request is kind 20177 -- ephemeral,
/// so relays are not even asked to store it -- and it carries an
/// `expiration` tag [publishRequest] sets [expirySeconds] ahead. A NIP-09
/// deletion would be addressed to a copy no relay is holding, and relays
/// honour deletions at their own discretion regardless. So the only honest
/// mechanism, and the one spec §7.5 names, is a DM to each driver who was
/// actually engaged: they stop coming, and the public listing goes quiet on
/// its own when it expires. UI copy has to say that and nothing more --
/// "your request was deleted" would be a sentence this protocol cannot back.
class RideRequestService {
  final RelayPool _pool;
  final RideDmChannel _dm;

  RideRequestService(this._pool, this._dm);

  /// Builds, mines PoW for, signs, and publishes a ride request. Returns
  /// the signed event -- its `id` is the ride request id offers and the
  /// eventual handoff reference.
  Future<NostrEvent> publishRequest({
    required String privHex,
    required int now,
    required double pickupLat,
    required double pickupLon,
    required double destLat,
    required double destLon,
    int? offeredMnt,
    String note = '',
    int expirySeconds = 240,
    int powDifficulty = kRideRequestPowDifficulty,
  }) async {
    final pubHex = pubkeyFromPrivate(privHex);
    final unsigned = buildRideRequest(
      pubkey: pubHex,
      now: now,
      pickupLat: pickupLat,
      pickupLon: pickupLon,
      destLat: destLat,
      destLon: destLon,
      offeredMnt: offeredMnt,
      note: note,
      expirySeconds: expirySeconds,
    );
    final mined = minePow(unsigned, powDifficulty);
    final signed = signEvent(mined, privHex);
    await _pool.publish(signed);
    return signed;
  }

  /// Tells one driver the passenger is backing out of a request they'd
  /// offered on (spec §7.5).
  Future<void> cancelWithDriver({
    required String privHex,
    required String driverPubHex,
    required String rideRequestId,
    required int now,
    String reason = '',
  }) => cancelWithDrivers(
    privHex: privHex,
    driverPubHexes: [driverPubHex],
    rideRequestId: rideRequestId,
    now: now,
    reason: reason,
  );

  /// Tells *every* driver engaged with this request that it is off.
  ///
  /// One door rather than a loop at the call site, for the reason
  /// `OfferService.sendOffer` keeps its own gate here: a passenger who
  /// cancels while four drivers are waiting on an answer owes all four the
  /// message, and "we told the one they had selected" is the shape that bug
  /// takes. Duplicates in [driverPubHexes] are collapsed -- a driver who
  /// sent two offers is one person and must not be messaged twice.
  ///
  /// A relay that refuses one send must not silence the rest, so each
  /// recipient is attempted independently and the first failure is
  /// rethrown only after everybody has been tried.
  Future<void> cancelWithDrivers({
    required String privHex,
    required Iterable<String> driverPubHexes,
    required String rideRequestId,
    required int now,
    String reason = '',
  }) async {
    final payload = RideCancelPayload(
      rideRequestId: rideRequestId,
      reason: reason,
    );
    Object? firstFailure;
    for (final driverPubHex in driverPubHexes.toSet()) {
      try {
        await _dm.send(
          senderPrivHex: privHex,
          recipientPubHex: driverPubHex,
          payload: payload,
          now: now,
        );
      } on Exception catch (e) {
        firstFailure ??= e;
      }
    }
    if (firstFailure != null) throw firstFailure;
  }

  /// Every cancellation addressed to the local identity -- for a driver,
  /// this fires when a passenger calls off a ride they offered on or were
  /// selected for.
  ///
  /// Shaped exactly like `OfferService.receiveOffers` and
  /// `HandoffService.receiveHandoffs`: one filtered view of the shared
  /// NIP-17 inbox, with the verified sender carried through so the screen
  /// consuming it can check who is actually cancelling.
  Stream<ReceivedRideCancel> receiveCancellations(
    String myPubHex,
    String myPrivHex,
  ) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is RideCancelPayload)
        .map(
          (dm) => ReceivedRideCancel(
            dm.senderPubkey,
            dm.payload as RideCancelPayload,
          ),
        );
  }
}
