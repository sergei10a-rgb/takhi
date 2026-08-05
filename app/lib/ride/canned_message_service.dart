// SPDX-License-Identifier: AGPL-3.0-or-later
import 'canned_message.dart';
import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';

/// A canned coordination message as the receiving side sees it: the verified
/// sender, the trip it belongs to, and which preset it was.
class ReceivedCannedMessage {
  final String senderPubkey;
  final String tripId;
  final CannedMessage message;
  const ReceivedCannedMessage(this.senderPubkey, this.tripId, this.message);
}

/// Sends and receives the one-tap [CannedMessage] presets over the same
/// reliable NIP-17 [RideDmChannel] as every other ride DM. Bidirectional —
/// unlike [TripStatusService], which only the driver drives — because either
/// person at the kerb may be the one who needs to say "I'm here" first.
class CannedMessageService {
  final RideDmChannel _dm;
  CannedMessageService(this._dm);

  Future<void> send({
    required String senderPrivHex,
    required String recipientPubHex,
    required String tripId,
    required CannedMessage message,
    required int now,
  }) async {
    await _dm.send(
      senderPrivHex: senderPrivHex,
      recipientPubHex: recipientPubHex,
      payload: RideCannedMessagePayload(tripId: tripId, message: message),
      now: now,
    );
  }

  Stream<ReceivedCannedMessage> watch(String myPubHex, String myPrivHex) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is RideCannedMessagePayload)
        .map((dm) {
          final payload = dm.payload as RideCannedMessagePayload;
          return ReceivedCannedMessage(
            dm.senderPubkey,
            payload.tripId,
            payload.message,
          );
        });
  }
}
