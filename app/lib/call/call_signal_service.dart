// SPDX-License-Identifier: AGPL-3.0-or-later
import '../ride/ride_dm_channel.dart';
import '../ride/ride_dm_payload.dart';

/// A call-signaling message as the receiving side sees it -- [payload] is
/// always one of the four `Call*Payload` subtypes (`ride_dm_payload.dart`),
/// never `RideOfferPayload`/`RideHandoffPayload`/etc.; [CallSignalService.
/// watchSignals] filters to only those before this type is ever
/// constructed.
class ReceivedCallSignal {
  final String senderPubkey;
  final RideDmPayload payload;
  const ReceivedCallSignal(this.senderPubkey, this.payload);
}

/// Sends/receives WebRTC offer/answer/ICE/hangup signaling (spec §7.3-①)
/// over the existing `RideDmChannel` -- the thin, call-specific sibling of
/// `TripStatusService` (Plan 4), same shape, different payload family.
class CallSignalService {
  final RideDmChannel _dm;
  CallSignalService(this._dm);

  Future<void> sendOffer({
    required String privHex,
    required String recipientPubHex,
    required String tripId,
    required String sdp,
    required int now,
  }) => _dm.send(
    senderPrivHex: privHex,
    recipientPubHex: recipientPubHex,
    payload: CallOfferPayload(tripId: tripId, sdp: sdp),
    now: now,
  );

  Future<void> sendAnswer({
    required String privHex,
    required String recipientPubHex,
    required String tripId,
    required String sdp,
    required int now,
  }) => _dm.send(
    senderPrivHex: privHex,
    recipientPubHex: recipientPubHex,
    payload: CallAnswerPayload(tripId: tripId, sdp: sdp),
    now: now,
  );

  Future<void> sendIceCandidate({
    required String privHex,
    required String recipientPubHex,
    required String tripId,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
    required int now,
  }) => _dm.send(
    senderPrivHex: privHex,
    recipientPubHex: recipientPubHex,
    payload: CallIceCandidatePayload(
      tripId: tripId,
      candidate: candidate,
      sdpMid: sdpMid,
      sdpMLineIndex: sdpMLineIndex,
    ),
    now: now,
  );

  Future<void> sendHangup({
    required String privHex,
    required String recipientPubHex,
    required String tripId,
    String reason = '',
    required int now,
  }) => _dm.send(
    senderPrivHex: privHex,
    recipientPubHex: recipientPubHex,
    payload: CallHangupPayload(tripId: tripId, reason: reason),
    now: now,
  );

  /// Every call-signal payload addressed to [myPubHex] and scoped to
  /// [tripId] -- a device is never in more than one call at once in this
  /// MVP, so filtering by trip id (rather than, say, a separate call id)
  /// is sufficient and reuses the identifier every other trip-scoped
  /// channel (`LiveLocationChannel`, `TripStatusService`) already keys on.
  Stream<ReceivedCallSignal> watchSignals(
    String myPubHex,
    String myPrivHex,
    String tripId,
  ) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where(
          (dm) => _isCallSignal(dm.payload) && _tripIdOf(dm.payload) == tripId,
        )
        .map((dm) => ReceivedCallSignal(dm.senderPubkey, dm.payload));
  }
}

bool _isCallSignal(RideDmPayload p) =>
    p is CallOfferPayload ||
    p is CallAnswerPayload ||
    p is CallIceCandidatePayload ||
    p is CallHangupPayload;

String _tripIdOf(RideDmPayload p) => switch (p) {
  CallOfferPayload(:final tripId) => tripId,
  CallAnswerPayload(:final tripId) => tripId,
  CallIceCandidatePayload(:final tripId) => tripId,
  CallHangupPayload(:final tripId) => tripId,
  _ => throw StateError('not a call signal payload'),
};
