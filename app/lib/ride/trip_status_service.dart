// SPDX-License-Identifier: AGPL-3.0-or-later
import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';
import 'trip_phase.dart';

/// A trip-phase transition as the receiving side sees it.
class ReceivedTripStatus {
  final String senderPubkey;
  final String tripId;
  final TripPhase phase;
  const ReceivedTripStatus(this.senderPubkey, this.tripId, this.phase);
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
  }) async {
    await _dm.send(
      senderPrivHex: driverPrivHex,
      recipientPubHex: passengerPubHex,
      payload: RideTripStatusPayload(tripId: tripId, phase: phase),
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
          );
        });
  }
}
