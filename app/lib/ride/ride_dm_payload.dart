// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'trip_phase.dart';

/// The structured content carried inside a NIP-17 rumor for every private
/// ride message (spec §6: offer/agreement, handoff, and cancellation all
/// share the encrypted-DM channel; this is the JSON schema for that
/// channel's `content`). [encode] is what goes into `nip17Wrap`'s
/// `content:`; [RideDmPayload.decode] is what a rumor's content is parsed
/// back into after `nip17Unwrap`.
sealed class RideDmPayload {
  const RideDmPayload();

  String encode() => jsonEncode(toJson());
  Map<String, dynamic> toJson();

  /// Parses a rumor's `content` back into a typed payload. Throws
  /// [FormatException] for malformed JSON, a non-object JSON value, a
  /// wrong-typed or missing field, or an unrecognized `type`.
  static RideDmPayload decode(String json) {
    final map = _requiredMap(jsonDecode(json));
    return switch (map['type']) {
      'offer' => RideOfferPayload._fromJson(map),
      'handoff' => RideHandoffPayload._fromJson(map),
      'cancel' => RideCancelPayload._fromJson(map),
      'trip_status' => RideTripStatusPayload._fromJson(map),
      'call_offer' => CallOfferPayload._fromJson(map),
      'call_answer' => CallAnswerPayload._fromJson(map),
      'call_ice' => CallIceCandidatePayload._fromJson(map),
      'call_hangup' => CallHangupPayload._fromJson(map),
      final other => throw FormatException(
        'unknown ride DM payload type: $other',
      ),
    };
  }
}

/// The rumor `content` this is decrypted from is untrusted input -- per
/// spec §9, any holder of the recipient's pubkey can craft it -- so every
/// field is type-checked explicitly and a [FormatException], never an
/// uncaught [TypeError], is thrown on any mismatch. Mirrors the
/// `_requiredString`/`_requiredInt` helper pattern in
/// `takhi_protocol`'s `event.dart` (`NostrEvent.fromJson`), which fixed
/// the identical unchecked-cast defect for the sibling type.
Map<String, dynamic> _requiredMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException(
    'RideDmPayload.decode: expected a JSON object, got '
    '${value.runtimeType}',
  );
}

String _requiredString(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is String) return value;
  throw FormatException(
    "RideDmPayload.decode: '$field' must be a String, got "
    '${value.runtimeType}',
  );
}

int _requiredInt(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is int) return value;
  throw FormatException(
    "RideDmPayload.decode: '$field' must be an int, got "
    '${value.runtimeType}',
  );
}

double _requiredDouble(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is num) return value.toDouble();
  throw FormatException(
    "RideDmPayload.decode: '$field' must be a number, got "
    '${value.runtimeType}',
  );
}

String _optionalString(
  Map<String, dynamic> map,
  String field, {
  String fallback = '',
}) {
  final value = map[field];
  if (value == null) return fallback;
  if (value is String) return value;
  throw FormatException(
    "RideDmPayload.decode: '$field' must be a String or null, got "
    '${value.runtimeType}',
  );
}

/// A driver's offer on a ride request: proposed price, ETA, and a short
/// vehicle description (spec §6 "Санал / тохиролцоо", §7.1 step 3).
/// [rideRequestId] correlates the offer back to the `NostrEvent.id` of the
/// public kind-20177 request it answers -- a field the spec's summary
/// table leaves implicit but the DM payload must carry explicitly.
final class RideOfferPayload extends RideDmPayload {
  final String rideRequestId;
  final int priceMnt;
  final int etaMinutes;
  final String vehicleDescription;

  const RideOfferPayload({
    required this.rideRequestId,
    required this.priceMnt,
    required this.etaMinutes,
    required this.vehicleDescription,
  });

  factory RideOfferPayload._fromJson(Map<String, dynamic> map) =>
      RideOfferPayload(
        rideRequestId: _requiredString(map, 'rideRequestId'),
        priceMnt: _requiredInt(map, 'priceMnt'),
        etaMinutes: _requiredInt(map, 'etaMinutes'),
        vehicleDescription: _requiredString(map, 'vehicleDescription'),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'offer',
    'rideRequestId': rideRequestId,
    'priceMnt': priceMnt,
    'etaMinutes': etaMinutes,
    'vehicleDescription': vehicleDescription,
  };
}

/// The passenger's exact pickup handoff to the driver they selected: only
/// ever sent to that one driver (spec §6 "Тохироо + яг байршил", §9
/// privacy tiering -- the exact point is never public).
final class RideHandoffPayload extends RideDmPayload {
  final String rideRequestId;
  final String tripId;
  final double lat;
  final double lon;
  final String plusCode;
  final String landmarkText;

  const RideHandoffPayload({
    required this.rideRequestId,
    required this.tripId,
    required this.lat,
    required this.lon,
    required this.plusCode,
    required this.landmarkText,
  });

  factory RideHandoffPayload._fromJson(Map<String, dynamic> map) =>
      RideHandoffPayload(
        rideRequestId: _requiredString(map, 'rideRequestId'),
        tripId: _requiredString(map, 'tripId'),
        lat: _requiredDouble(map, 'lat'),
        lon: _requiredDouble(map, 'lon'),
        plusCode: _requiredString(map, 'plusCode'),
        landmarkText: _requiredString(map, 'landmarkText'),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'handoff',
    'rideRequestId': rideRequestId,
    'tripId': tripId,
    'lat': lat,
    'lon': lon,
    'plusCode': plusCode,
    'landmarkText': landmarkText,
  };
}

/// Either side backing out before the trip starts (spec §7.5).
final class RideCancelPayload extends RideDmPayload {
  final String rideRequestId;
  final String reason;

  const RideCancelPayload({required this.rideRequestId, this.reason = ''});

  factory RideCancelPayload._fromJson(Map<String, dynamic> map) =>
      RideCancelPayload(
        rideRequestId: _requiredString(map, 'rideRequestId'),
        reason: _optionalString(map, 'reason'),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'cancel',
    'rideRequestId': rideRequestId,
    'reason': reason,
  };
}

/// A driver-initiated trip-phase transition (spec §7.1 steps 5-6). Rides
/// the same reliable NIP-17 gift-wrap transport as offer/handoff/cancel —
/// unlike position pings (`LiveLocationChannel`, ephemeral kind 20178), a
/// phase change is discrete, low-frequency, and must not be missed (in
/// particular `TripPhase.arrived`, which is what tells the passenger's
/// side to move into the rating step), so it does not ride the lighter,
/// best-effort location channel.
final class RideTripStatusPayload extends RideDmPayload {
  final String tripId;
  final TripPhase phase;

  const RideTripStatusPayload({required this.tripId, required this.phase});

  factory RideTripStatusPayload._fromJson(Map<String, dynamic> map) {
    final tripId = _requiredString(map, 'tripId');
    final phaseName = _requiredString(map, 'phase');
    final phase = TripPhase.values.firstWhere(
      (p) => p.name == phaseName,
      orElse: () => throw FormatException('unknown trip phase: $phaseName'),
    );
    return RideTripStatusPayload(tripId: tripId, phase: phase);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'trip_status',
    'tripId': tripId,
    'phase': phase.name,
  };
}

/// A WebRTC SDP offer, opening a P2P call attempt for [tripId] (spec
/// §7.3-①). Rides the same NIP-17 gift-wrap transport as every other ride
/// DM -- offer/answer/ICE exchange is low-frequency (a handful of
/// messages per call attempt, not a per-second stream like live location),
/// so gift-wrap's identity-hiding and timing-randomization cost nothing
/// here that matters, unlike `LiveLocationChannel`'s deliberate choice to
/// skip it (Plan 4).
final class CallOfferPayload extends RideDmPayload {
  final String tripId;
  final String sdp;

  const CallOfferPayload({required this.tripId, required this.sdp});

  factory CallOfferPayload._fromJson(Map<String, dynamic> map) =>
      CallOfferPayload(
        tripId: _requiredString(map, 'tripId'),
        sdp: _requiredString(map, 'sdp'),
      );

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'call_offer', 'tripId': tripId, 'sdp': sdp};
}

/// The callee's WebRTC SDP answer, completing the offer/answer exchange
/// for [tripId].
final class CallAnswerPayload extends RideDmPayload {
  final String tripId;
  final String sdp;

  const CallAnswerPayload({required this.tripId, required this.sdp});

  factory CallAnswerPayload._fromJson(Map<String, dynamic> map) =>
      CallAnswerPayload(
        tripId: _requiredString(map, 'tripId'),
        sdp: _requiredString(map, 'sdp'),
      );

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'call_answer', 'tripId': tripId, 'sdp': sdp};
}

/// A single trickled ICE candidate for [tripId]'s in-progress call
/// negotiation. `candidate`/`sdpMid`/`sdpMLineIndex` are the exact three
/// fields `RTCIceCandidate` (flutter_webrtc) and this plan's own
/// `IceCandidateData` (Task 4) carry -- kept as plain strings/int here
/// rather than importing any WebRTC type, since `takhi_protocol`-adjacent
/// wire-format code must stay independent of any specific WebRTC package
/// version.
final class CallIceCandidatePayload extends RideDmPayload {
  final String tripId;
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;

  const CallIceCandidatePayload({
    required this.tripId,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  factory CallIceCandidatePayload._fromJson(Map<String, dynamic> map) =>
      CallIceCandidatePayload(
        tripId: _requiredString(map, 'tripId'),
        candidate: _requiredString(map, 'candidate'),
        sdpMid: _requiredString(map, 'sdpMid'),
        sdpMLineIndex: _requiredInt(map, 'sdpMLineIndex'),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'call_ice',
    'tripId': tripId,
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
  };
}

/// Either side ending a call -- while ringing (declined/cancelled) or
/// mid-call (hung up). [reason] is a short, optional, non-localized debug
/// string (never shown verbatim in the UI, which renders its own
/// localized "call ended" copy regardless of [reason]'s content).
final class CallHangupPayload extends RideDmPayload {
  final String tripId;
  final String reason;

  const CallHangupPayload({required this.tripId, this.reason = ''});

  factory CallHangupPayload._fromJson(Map<String, dynamic> map) =>
      CallHangupPayload(
        tripId: _requiredString(map, 'tripId'),
        reason: _optionalString(map, 'reason'),
      );

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'call_hangup', 'tripId': tripId, 'reason': reason};
}
