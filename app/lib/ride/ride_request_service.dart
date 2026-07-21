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

/// Publishes a passenger's ride request (spec §7.1 step 1: pick points,
/// optional price, publish with PoW and a 4-minute expiry) and lets the
/// passenger cancel with a specific driver they've already been offered
/// by (spec §7.5 -- cancellation is a DM to whichever driver(s) were
/// engaged; the public request itself is ephemeral and simply expires).
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
  }) async {
    await _dm.send(
      senderPrivHex: privHex,
      recipientPubHex: driverPubHex,
      payload: RideCancelPayload(rideRequestId: rideRequestId, reason: reason),
      now: now,
    );
  }
}
