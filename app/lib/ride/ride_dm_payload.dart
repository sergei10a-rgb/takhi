// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:takhi_protocol/takhi_protocol.dart';

import '../profile/driver_photo_rules.dart';
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
      'voice_note' => VoiceNotePayload._fromJson(map),
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

/// A nullable-int field reader, mirroring [_optionalStringOrNull]'s
/// "absent means null, present must be well-typed" contract for
/// [RideOfferPayload.kmTariffMnt].
int? _optionalInt(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException(
    "RideDmPayload.decode: '$field' must be an int or null, got "
    '${value.runtimeType}',
  );
}

/// The longest base64 string that can possibly encode
/// [kDriverPhotoMaxBytes]: base64 spends four characters on every three
/// bytes.
///
/// Checked *before* decoding, never after. A hostile driver can put a
/// fifty-megabyte string in this field, and expanding it to find out how
/// big it is would be doing the attack for them -- the passenger's phone
/// would run out of memory decoding a photo it was always going to
/// discard.
const int kMaxDriverPhotoBase64Length = ((kDriverPhotoMaxBytes + 2) ~/ 3) * 4;

/// Reads a driver name part off the wire.
///
/// Anything wrong with it -- absent, wrong type, too long, carrying markup
/// or a newline -- yields `null` rather than an exception, which the UI
/// then renders exactly as it renders a driver who has not set a name at
/// all. That is deliberate: the alternative to a missing name is a pubkey,
/// which is safe, whereas the alternative to *throwing* is losing the whole
/// offer -- price, ETA and car included -- because a stranger put an emoji
/// in a field. The passenger keeps the offer and loses only the part that
/// could not be trusted.
String? _driverNameOrNull(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is! String) return null;
  // Length before validation, so a megabyte of text is discarded on sight
  // rather than normalized and pattern-matched first.
  if (value.length > kMaxDriverNamePartLength * 4) return null;
  final normalized = normalizeDriverNamePart(value);
  if (driverNamePartProblem(normalized) != null) return null;
  return normalized;
}

/// Reads the driver's portrait off the wire, dropping it on any doubt.
///
/// Same "keep the offer, lose the field" rule as [_driverNameOrNull], and
/// the same reason: a photo that will not decode is a photo, not a reason
/// to throw away a ride.
String? _driverPhotoOrNull(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is! String) return null;
  if (value.isEmpty) return null;
  if (value.length > kMaxDriverPhotoBase64Length) return null;
  // The sender is supposed to have compressed this under the cap, but the
  // sender is exactly who this guard exists against, so the decoded size is
  // checked too -- a base64 string can be short and still, with padding
  // tricks, decode to more than the length check implied.
  final Uint8List decoded;
  try {
    decoded = base64Decode(value);
  } on FormatException {
    return null;
  }
  if (decoded.isEmpty || decoded.length > kDriverPhotoMaxBytes) return null;
  return value;
}

/// A genuinely-nullable variant of [_optionalString] -- that helper always
/// returns a non-null fallback, which cannot distinguish "absent" from
/// "explicitly empty". Used for [RideHandoffPayload.phone], where `null`
/// (sharing disabled/no number saved) must stay distinguishable from any
/// future explicit empty-string value.
String? _optionalStringOrNull(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value == null) return null;
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
///
/// [kmTariffMnt] is the driver's own km-tariff (from their published
/// `DriverProfile`, `takhi_protocol`'s `driver_profile.dart`), attached
/// only when the driver is offering §7.2 GPS-taximeter pricing for this
/// trip -- `null` (the default) means a plain fixed-price offer, matching
/// every offer built before this field existed. Its presence on the
/// *selected* offer is what `ActiveTripView` reads to decide whether a
/// trip runs metered or fixed (see that class's doc comment) -- there is
/// deliberately no separate "pricing mode" enum/flag: a driver attaching
/// their tariff *is* the metered-pricing proposal, and the passenger
/// selecting that offer *is* accepting it, so a redundant flag would only
/// ever restate what this field's nullability already says (YAGNI).
final class RideOfferPayload extends RideDmPayload {
  final String rideRequestId;
  final int priceMnt;
  final int etaMinutes;
  final String vehicleDescription;
  final int? kmTariffMnt;

  /// The waiting half of a metered offer: what this driver charges per
  /// minute the trip spends stopped (spec §7.4). Travels with
  /// [kmTariffMnt] and is shown beside it, because a passenger choosing
  /// between drivers on price is choosing on both numbers — a metered offer
  /// that quotes only the distance rate hides half of what an
  /// Ulaanbaatar rush-hour trip actually costs, and the rest arrives as a
  /// surprise at the destination.
  ///
  /// `null` (the default) means the same as [kmTariffMnt]'s: an offer built
  /// before this field existed, or a plain fixed-price offer. A driver who
  /// genuinely charges nothing for waiting sends `0`, which is a promise
  /// rather than an absence.
  final int? waitTariffMntPerMinute;

  /// Овог and нэр -- who the passenger is about to get into a car with.
  ///
  /// This is the *only* channel the driver's name travels on. It is
  /// deliberately not in their public kind-0 profile
  /// (`takhi_protocol`'s `driver_profile.dart` has no `name:` parameter at
  /// all): a kind-0 is world-readable and replicated forever, so a name
  /// published there is a name anyone can harvest against a pubkey that
  /// also carries a plate number and a live geohash. Here it is inside a
  /// NIP-17 gift-wrap addressed to one passenger, and only after that
  /// passenger published a request this driver chose to answer. Same
  /// "vague in public, exact to the person you are actually dealing with"
  /// tiering spec §6 applies to location, applied to identity.
  ///
  /// Nullable so that an offer built by a client from before this field
  /// existed still decodes -- and so that a name that arrives malformed can
  /// be dropped without losing the offer around it. A driver whose own
  /// client is up to date cannot *send* an offer without one; that rule is
  /// `driverOfferBlock` (`profile/driver_offer_eligibility.dart`), enforced
  /// in `OfferService.sendOffer` before anything reaches a relay.
  final String? driverFamilyName;
  final String? driverGivenName;

  /// The driver's portrait, JPEG, base64, at most [kDriverPhotoMaxBytes]
  /// decoded.
  ///
  /// **Not proof of anything.** The sending device checked that there is
  /// one human face of a reasonable size in it; nothing checked that the
  /// face is this driver's, and nothing can, without a server. A friend's
  /// photo, a celebrity's, or a photograph of a printed photograph all pass.
  /// The UI must say so plainly -- a passenger who trusts a verification
  /// that does not exist is worse off than one who knows they are looking
  /// at an unverified picture.
  final String? driverPhotoJpegBase64;

  /// [driverPhotoBytes]' answer, remembered after the first call.
  ///
  /// Two fields rather than one nullable field because `null` is a real
  /// answer here -- "there is no usable portrait" -- and must not be
  /// mistaken for "not decoded yet", which would re-run base64 and the size
  /// checks on every single build of every photo-less offer row.
  Uint8List? _decodedPhoto;
  bool _photoDecodeAttempted = false;

  /// Not `const`, deliberately. See [driverPhotoBytes]: this object caches
  /// its own decoded portrait, which a const instance cannot do, and the
  /// cache is what keeps a rider's offer list from re-decoding every
  /// driver's face on every rebuild. Nothing in the app builds one of these
  /// at compile time -- they come off the wire.
  RideOfferPayload({
    required this.rideRequestId,
    required this.priceMnt,
    required this.etaMinutes,
    required this.vehicleDescription,
    this.kmTariffMnt,
    this.waitTariffMntPerMinute,
    this.driverFamilyName,
    this.driverGivenName,
    this.driverPhotoJpegBase64,
  });

  factory RideOfferPayload._fromJson(Map<String, dynamic> map) =>
      RideOfferPayload(
        rideRequestId: _requiredString(map, 'rideRequestId'),
        priceMnt: _requiredInt(map, 'priceMnt'),
        etaMinutes: _requiredInt(map, 'etaMinutes'),
        vehicleDescription: _requiredString(map, 'vehicleDescription'),
        kmTariffMnt: _optionalInt(map, 'kmTariffMnt'),
        waitTariffMntPerMinute: _optionalInt(map, 'waitTariffMntPerMinute'),
        driverFamilyName: _driverNameOrNull(map, 'driverFamilyName'),
        driverGivenName: _driverNameOrNull(map, 'driverGivenName'),
        driverPhotoJpegBase64: _driverPhotoOrNull(map, 'driverPhotoJpeg'),
      );

  /// Both name parts joined family-first (`Б. Батбаяр`), or `null` while
  /// either half is missing. Half a name shown as if it were the whole one
  /// is worse than a pubkey: the passenger cannot tell it is incomplete.
  String? get driverFullName {
    final family = driverFamilyName, given = driverGivenName;
    if (family == null || given == null) return null;
    if (family.isEmpty || given.isEmpty) return null;
    return '$family $given';
  }

  /// The portrait as bytes, or `null` if there is none or it will not
  /// decode. Never throws -- `_fromJson` already discarded anything
  /// oversized or malformed, and this stays defensive for payloads built
  /// in code rather than parsed.
  ///
  /// **The same list every time, on purpose.** Flutter's image cache keys a
  /// `MemoryImage` on the *identity* of its byte list, so a getter that
  /// decoded afresh on each call handed every rebuild a key the cache had
  /// never seen: the offer list re-decoded every driver's face whenever a
  /// new offer arrived, and each portrait blanked for a frame while it did.
  /// Caching here rather than in the widgets is what makes the fix hold --
  /// the rows are stateless and rebuild constantly, while this object is
  /// created once, when the offer comes off the wire.
  Uint8List? get driverPhotoBytes {
    if (_photoDecodeAttempted) return _decodedPhoto;
    _photoDecodeAttempted = true;
    return _decodedPhoto = _decodeDriverPhoto();
  }

  Uint8List? _decodeDriverPhoto() {
    final encoded = driverPhotoJpegBase64;
    if (encoded == null || encoded.isEmpty) return null;
    if (encoded.length > kMaxDriverPhotoBase64Length) return null;
    try {
      final decoded = base64Decode(encoded);
      if (decoded.isEmpty || decoded.length > kDriverPhotoMaxBytes) return null;
      return decoded;
    } on FormatException {
      return null;
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'offer',
    'rideRequestId': rideRequestId,
    'priceMnt': priceMnt,
    'etaMinutes': etaMinutes,
    'vehicleDescription': vehicleDescription,
    if (kmTariffMnt != null) 'kmTariffMnt': kmTariffMnt,
    if (waitTariffMntPerMinute != null)
      'waitTariffMntPerMinute': waitTariffMntPerMinute,
    if (driverFamilyName != null) 'driverFamilyName': driverFamilyName,
    if (driverGivenName != null) 'driverGivenName': driverGivenName,
    if (driverPhotoJpegBase64 != null) 'driverPhotoJpeg': driverPhotoJpegBase64,
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

  /// The passenger's own phone number, present only when
  /// `PhoneShareSettingsStore.isEnabled()` was true at handoff time (spec
  /// §7.3-②) -- absent (`null`), not empty-string, when sharing is off or
  /// no number is saved. See Task 5's "Deliberate scope boundary" note
  /// for why this field exists only on the passenger-to-driver handoff and
  /// not symmetrically on the driver's offer.
  final String? phone;

  const RideHandoffPayload({
    required this.rideRequestId,
    required this.tripId,
    required this.lat,
    required this.lon,
    required this.plusCode,
    required this.landmarkText,
    this.phone,
  });

  factory RideHandoffPayload._fromJson(Map<String, dynamic> map) =>
      RideHandoffPayload(
        rideRequestId: _requiredString(map, 'rideRequestId'),
        tripId: _requiredString(map, 'tripId'),
        lat: _requiredDouble(map, 'lat'),
        lon: _requiredDouble(map, 'lon'),
        plusCode: _requiredString(map, 'plusCode'),
        landmarkText: _requiredString(map, 'landmarkText'),
        phone: _optionalStringOrNull(map, 'phone'),
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
    if (phone != null) 'phone': phone,
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

  /// The driver's own GPS-computed metered fare (spec §7.2), attached only
  /// to the `TripPhase.arrived` transition and only for a trip that was
  /// agreed at metered pricing (i.e. the selected `RideOfferPayload` carried
  /// a non-null `kmTariffMnt`) -- `null` for every fixed-price trip, which
  /// is every trip built before this field existed. This is how the
  /// passenger's side learns the authoritative fare: it is computed once,
  /// from the *driver's* measured distance, and carried here rather than
  /// each side silently computing its own (their GPS tracks can and do
  /// differ slightly) -- the passenger's own measurement is shown
  /// alongside it for transparency (spec §7.2 "ил тод байдал"), but this
  /// value is what both sides' trip receipts end up signing.
  final int? finalFareMnt;

  /// How much of [finalFareMnt] was time rather than distance, and the
  /// waiting it covers (spec §7.4). Carried for the same reason the total
  /// is: the passenger's own phone cannot recompute it, because its GPS
  /// track — and therefore its own view of when the car was stopped —
  /// differs slightly from the driver's. Sending the breakdown is what lets
  /// both trip receipts state the same two rows and not merely the same sum,
  /// which is the whole point of a dual-signed receipt.
  ///
  /// The distance half is never sent: it is [finalFareMnt] minus
  /// [finalWaitingFareMnt], and a number sent twice is a number that can
  /// arrive contradicting itself. `null` on a fixed-price trip and on any
  /// status sent by a client built before waiting fares existed.
  final int? finalWaitingFareMnt;
  final int? finalWaitingSeconds;

  const RideTripStatusPayload({
    required this.tripId,
    required this.phase,
    this.finalFareMnt,
    this.finalWaitingFareMnt,
    this.finalWaitingSeconds,
  });

  factory RideTripStatusPayload._fromJson(Map<String, dynamic> map) {
    final tripId = _requiredString(map, 'tripId');
    final phaseName = _requiredString(map, 'phase');
    final phase = TripPhase.values.firstWhere(
      (p) => p.name == phaseName,
      orElse: () => throw FormatException('unknown trip phase: $phaseName'),
    );
    return RideTripStatusPayload(
      tripId: tripId,
      phase: phase,
      finalFareMnt: _optionalInt(map, 'finalFareMnt'),
      finalWaitingFareMnt: _optionalInt(map, 'finalWaitingFareMnt'),
      finalWaitingSeconds: _optionalInt(map, 'finalWaitingSeconds'),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'trip_status',
    'tripId': tripId,
    'phase': phase.name,
    if (finalFareMnt != null) 'finalFareMnt': finalFareMnt,
    if (finalWaitingFareMnt != null) 'finalWaitingFareMnt': finalWaitingFareMnt,
    if (finalWaitingSeconds != null) 'finalWaitingSeconds': finalWaitingSeconds,
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
  Map<String, dynamic> toJson() => {
    'type': 'call_offer',
    'tripId': tripId,
    'sdp': sdp,
  };
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
  Map<String, dynamic> toJson() => {
    'type': 'call_answer',
    'tripId': tripId,
    'sdp': sdp,
  };
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
  Map<String, dynamic> toJson() => {
    'type': 'call_hangup',
    'tripId': tripId,
    'reason': reason,
  };
}

/// A short voice message (spec §7.3-③ "дуут зурвас") -- the final rung of
/// the calling fallback chain, guaranteed to cross any NAT/CGNAT because
/// it rides the same reliable NIP-17 gift-wrap DM transport as every other
/// ride message: no direct connection between the two devices is ever
/// needed. Capped at [kMaxVoiceNoteDurationSeconds]/[kMaxVoiceNoteBytes]
/// by `validateVoiceNoteAudio` (`app/lib/call/voice_note_service.dart`)
/// *before* a payload is ever constructed on the sending side -- this
/// class itself does not re-validate on decode, so a hand-crafted
/// oversized payload from a misbehaving peer still decodes without
/// throwing (consistent with every other payload's "never crash on
/// foreign input" policy); the receiving UI sizes its player display from
/// `durationSeconds` alone rather than trusting `audioBase64`'s length for
/// anything but playback itself.
final class VoiceNotePayload extends RideDmPayload {
  final String tripId;
  final String audioBase64;
  final int durationSeconds;

  const VoiceNotePayload({
    required this.tripId,
    required this.audioBase64,
    required this.durationSeconds,
  });

  factory VoiceNotePayload._fromJson(Map<String, dynamic> map) =>
      VoiceNotePayload(
        tripId: _requiredString(map, 'tripId'),
        audioBase64: _requiredString(map, 'audioBase64'),
        durationSeconds: _requiredInt(map, 'durationSeconds'),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'voice_note',
    'tripId': tripId,
    'audioBase64': audioBase64,
    'durationSeconds': durationSeconds,
  };
}
