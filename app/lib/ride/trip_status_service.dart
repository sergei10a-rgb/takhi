// SPDX-License-Identifier: AGPL-3.0-or-later
import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';
import 'trip_phase.dart';

/// A trip-phase transition as the receiving side sees it.
class ReceivedTripStatus {
  final String senderPubkey;
  final String tripId;
  final TripPhase phase;

  /// See [RideTripStatusPayload.finalFareMnt]'s doc comment -- `null` for
  /// every transition except a metered trip's `TripPhase.arrived`.
  final int? finalFareMnt;

  /// See [RideTripStatusPayload.finalWaitingFareMnt] -- the waiting half of
  /// [finalFareMnt], so this side signs the driver's breakdown rather than
  /// guessing its own from a track that never matches exactly.
  final int? finalWaitingFareMnt;
  final int? finalWaitingSeconds;

  /// See [RideTripStatusPayload.finalDurationFareMnt] -- the trip-duration
  /// share of [finalFareMnt], which overlaps the waiting one on purpose and
  /// so must stay its own row all the way to the screen the passenger signs.
  final int? finalDurationFareMnt;
  final int? finalDurationSeconds;

  /// See [RideTripStatusPayload.finalBaseFareMnt]/[RideTripStatusPayload
  /// .finalMinFareTopUpMnt] -- the flat booking base and the floor lift, each
  /// its own row on the screen the passenger signs so neither is reported as
  /// distance.
  final int? finalBaseFareMnt;
  final int? finalMinFareTopUpMnt;

  const ReceivedTripStatus(
    this.senderPubkey,
    this.tripId,
    this.phase, {
    this.finalFareMnt,
    this.finalWaitingFareMnt,
    this.finalWaitingSeconds,
    this.finalDurationFareMnt,
    this.finalDurationSeconds,
    this.finalBaseFareMnt,
    this.finalMinFareTopUpMnt,
  });
}

/// Sends/receives driver-initiated trip-phase transitions (spec §7.1 steps
/// 5-6) over the existing reliable NIP-17 [RideDmChannel] — see
/// [RideTripStatusPayload]'s doc comment for why this rides the DM
/// transport rather than the lighter-weight [LiveLocationChannel].
class TripStatusService {
  final RideDmChannel _dm;
  TripStatusService(this._dm);

  Future<void> sendStatus({
    required String driverPrivHex,
    required String passengerPubHex,
    required String tripId,
    required TripPhase phase,
    required int now,
    int? finalFareMnt,
    int? finalWaitingFareMnt,
    int? finalWaitingSeconds,
    int? finalDurationFareMnt,
    int? finalDurationSeconds,
    int? finalBaseFareMnt,
    int? finalMinFareTopUpMnt,
  }) async {
    await _dm.send(
      senderPrivHex: driverPrivHex,
      recipientPubHex: passengerPubHex,
      payload: RideTripStatusPayload(
        tripId: tripId,
        phase: phase,
        finalFareMnt: finalFareMnt,
        finalWaitingFareMnt: finalWaitingFareMnt,
        finalWaitingSeconds: finalWaitingSeconds,
        finalDurationFareMnt: finalDurationFareMnt,
        finalDurationSeconds: finalDurationSeconds,
        finalBaseFareMnt: finalBaseFareMnt,
        finalMinFareTopUpMnt: finalMinFareTopUpMnt,
      ),
      now: now,
    );
  }

  Stream<ReceivedTripStatus> watchStatus(String myPubHex, String myPrivHex) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is RideTripStatusPayload)
        .map((dm) {
          final payload = dm.payload as RideTripStatusPayload;
          return ReceivedTripStatus(
            dm.senderPubkey,
            payload.tripId,
            payload.phase,
            finalFareMnt: payload.finalFareMnt,
            finalWaitingFareMnt: payload.finalWaitingFareMnt,
            finalWaitingSeconds: payload.finalWaitingSeconds,
            finalDurationFareMnt: payload.finalDurationFareMnt,
            finalDurationSeconds: payload.finalDurationSeconds,
            finalBaseFareMnt: payload.finalBaseFareMnt,
            finalMinFareTopUpMnt: payload.finalMinFareTopUpMnt,
          );
        });
  }
}
