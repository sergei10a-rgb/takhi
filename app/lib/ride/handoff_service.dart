// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';
import 'trip_id.dart';

/// A handoff the local side received -- for a driver, this is the
/// passenger's exact pickup point once selected (spec §6/§7.1 step 4).
class ReceivedHandoff {
  final String senderPubkey;
  final RideHandoffPayload payload;
  const ReceivedHandoff(this.senderPubkey, this.payload);
}

/// Sends the passenger's exact pickup location to the one driver they
/// selected (spec §7.1 step 4) and lets either side listen for it. The
/// passenger mints [generateTripId] here -- this is the only place a trip
/// id is created; every later trip receipt (Plan 4) reuses it as the `d`
/// tag.
class HandoffService {
  final RideDmChannel _dm;
  HandoffService(this._dm);

  /// Sends the handoff and returns the trip id that was minted for it
  /// (or the caller-supplied [tripId], used verbatim if given).
  Future<String> sendHandoff({
    required String passengerPrivHex,
    required String driverPubHex,
    required String rideRequestId,
    required double lat,
    required double lon,
    required String landmarkText,
    required int now,
    String? tripId,
  }) async {
    final id = tripId ?? generateTripId();
    final payload = RideHandoffPayload(
      rideRequestId: rideRequestId,
      tripId: id,
      lat: lat,
      lon: lon,
      plusCode: plusCodeEncode(lat, lon),
      landmarkText: landmarkText,
    );
    await _dm.send(
      senderPrivHex: passengerPrivHex,
      recipientPubHex: driverPubHex,
      payload: payload,
      now: now,
    );
    return id;
  }

  /// Every handoff addressed to the local identity -- for a driver, this
  /// fires once a passenger selects them.
  Stream<ReceivedHandoff> receiveHandoffs(String myPubHex, String myPrivHex) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is RideHandoffPayload)
        .map((dm) => ReceivedHandoff(
              dm.senderPubkey,
              dm.payload as RideHandoffPayload,
            ));
  }
}
