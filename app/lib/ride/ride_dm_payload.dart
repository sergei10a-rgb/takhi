// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:takhi_protocol/takhi_protocol.dart';

import '../profile/driver_photo_rules.dart';
import 'canned_message.dart';
import 'ride_cancel_reason.dart';
import 'trip_phase.dart';
import 'trip_start_code.dart';

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
      'canned_message' => RideCannedMessagePayload._fromJson(map),
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

/// The pickup confirmation code off the wire, or `null` if absent or
/// malformed.
///
/// Four digits, matched loosely: anything that is not exactly four ASCII
/// digits is dropped to `null` rather than thrown on, so a stranger putting
/// junk in the field costs the confirmation step but never the handoff
/// around it — the exact pickup point the driver is waiting for must survive
/// a bad code. Kept as a `String`, not an `int`, so a leading zero (`0421`)
/// is a valid code rather than the number 421.
String? _optionalStartCode(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is! String) return null;
  return isWellFormedStartCode(value) ? value : null;
}

/// The structured cancel reason off the wire, or [RideCancelReason.unknown]
/// for anything this build cannot place: an absent field (an old sender), a
/// non-String, or a token from a newer client. Never throws — the same
/// drop-to-fallback contract as [_optionalStartCode], and deliberately unlike
/// the trip-phase decode, because the cancel this rides on must tear a dead
/// ride down no matter who sent it.
RideCancelReason _optionalCancelReason(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is! String) return RideCancelReason.unknown;
  return RideCancelReason.fromWire(value);
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

/// How precisely an offer states where the driver is: **geohash-7**,
/// roughly a 153m x 153m cell, so a car plots to within about ±76m.
///
/// One rung finer than the public ride request (geohash-6, ~±600m) and one
/// rung coarser than a coordinate. See [RideOfferPayload.driverGeohash] for
/// why both neighbours were rejected.
const int kDriverGeohashPrecision = 7;

/// A geohash cell from another person's client, or `null` when it is
/// absent or unusable.
///
/// Length-checked rather than trusted. The value is decoded and drawn on a
/// map, and `geohashDecodeCenter` on a hostile string is not something this
/// screen should find out about at paint time. Anything longer than
/// [kDriverGeohashPrecision] is truncated rather than refused, so a future
/// client sending a finer cell still plots -- at the precision this app
/// agreed to, not the one it was handed.
///
/// A bad value costs the map a car and nothing else: the offer itself still
/// arrives and is still choosable from the list. Losing a real offer over a
/// malformed optional field would be the worse failure by far.
String? _optionalGeohashOrNull(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException(
      "RideDmPayload.decode: '$field' must be a string or null, got "
      '${value.runtimeType}',
    );
  }
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  if (!_geohashAlphabet.hasMatch(trimmed)) return null;
  return trimmed.length > kDriverGeohashPrecision
      ? trimmed.substring(0, kDriverGeohashPrecision)
      : trimmed;
}

/// Base32 as geohash uses it: no `a`, `i`, `l` or `o`.
final RegExp _geohashAlphabet = RegExp(r'^[0-9bcdefghjkmnpqrstuvwxyz]+$');

/// Like [_optionalInt], but refuses a negative.
///
/// Used for [RideHandoffPayload.tipMnt], which arrives from another
/// person's client and is added to a price. A negative "bonus" would
/// quietly reduce a figure the driver already accepted, turning a gift into
/// a counter-offer the driver never saw. Treated as absent rather than
/// thrown on, because the rest of the handoff -- the exact pickup point the
/// driver is waiting for -- is still good and must not be lost over a bad
/// tip.
int? _optionalPositiveIntOrNull(Map<String, dynamic> map, String field) {
  final value = _optionalInt(map, field);
  if (value == null || value <= 0) return null;
  return value;
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

/// How long a driver's offer stays actionable, in seconds from the moment it
/// is sent. The driver stamps [RideOfferPayload.expiresAtSeconds] `= now +
/// this`; the passenger's list counts down to it and drops the row when it
/// passes.
///
/// Three minutes: long enough to read several offers and choose between them
/// unhurried, short enough that a row a passenger taps is one the driver who
/// sent it is still standing behind — a six-minute-old promise of a
/// four-minute ETA is already broken.
const int kOfferValiditySeconds = 180;

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

  /// Roughly where this driver is, as a **geohash-7** cell (~±76m), so the
  /// passenger can see the cars on a map and pick one instead of reading a
  /// list of strangers.
  ///
  /// The precision is a deliberate middle rung on spec §6's ladder, and
  /// both neighbours were rejected on purpose:
  ///
  ///  * **geohash-6** (~±600m) is what the PUBLIC request carries. Too
  ///    coarse here -- two drivers in one cell would draw on the same
  ///    pixel, and "pick your car off the map" stops meaning anything.
  ///  * **An exact point** is too much. A driver answering ten requests
  ///    would hand their precise position to the nine passengers who did
  ///    not choose them, and this is sent BEFORE anyone has chosen.
  ///
  /// It is safe to send at all only because of where it travels: inside a
  /// NIP-17 gift wrap addressed to the one passenger whose request this
  /// driver chose to answer. It is never in the kind-0 profile, which is
  /// world-readable and already carries the car, the colour and the plate
  /// -- a public position feed beside those would let anyone follow a
  /// named, plated vehicle all day and learn where its driver sleeps.
  /// Publishing driver locations was considered for exactly this feature
  /// and refused for exactly that reason.
  ///
  /// `null` on an offer from a client older than this field, or from a
  /// driver whose GPS has not produced a fix yet. The map simply does not
  /// draw a car for them; the list still shows the offer in full, so a
  /// driver with no fix is never silently excluded from being chosen.
  final String? driverGeohash;

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

  /// What this driver charges per minute of the trip itself -- every minute
  /// from the first GPS fix to the last, moving or stopped (the third rate,
  /// added 2026-08-01). Travels with [kmTariffMnt] for exactly the reason
  /// [waitTariffMntPerMinute] does, and more sharply: a rate that bills the
  /// whole trip is the one a passenger has the least chance of guessing from
  /// the km figure, so an offer that omits it is quoting a price that cannot
  /// be compared with the driver's next to it.
  ///
  /// It deliberately overlaps [waitTariffMntPerMinute] -- stopped seconds are
  /// inside the trip's duration too, so a driver who sets both charges those
  /// seconds twice. That is the driver's own commercial decision (author's
  /// ruling, 2026-08-01), which is why nothing here validates the pair, and
  /// why both figures reach the passenger separately rather than being folded
  /// into one "time rate" that would hide the arrangement being offered.
  ///
  /// `null` (the default) means the same as its two neighbours': an offer
  /// built before this field existed, or a plain fixed-price one. `0` is a
  /// promise that the trip's duration costs nothing.
  final int? durationTariffMntPerMinute;

  /// The driver's booked-ride base fee (their `DriverTariff.bookingBaseMnt`):
  /// a flat charge that covers the drive to the passenger, added once to a
  /// ride the app arranged rather than a street hail. It travels here for the
  /// same reason the three rates above do -- so the fare the driver's meter
  /// computes and the fare the passenger's screen shows are built from one
  /// agreed set of numbers, not two. The street-hail meter never sees it (a
  /// hail had no approach to pay for); a matched trip charges it as its
  /// boarding fee.
  ///
  /// `null` on an offer built before this field existed or a fixed-price one;
  /// `0` is a driver who charges nothing to be booked.
  final int? bookingBaseMnt;

  /// The driver's minimum fare (their `DriverTariff.minFareMnt`): the least
  /// the trip will cost, applied as a visible top-up when the metered charges
  /// fall short of it. Carried so a matched trip honours the same floor the
  /// offline meter does, rather than silently dropping it the moment a ride
  /// was arranged through the app.
  ///
  /// `null`/absent on an older or fixed-price offer; `0` means no floor.
  final int? minFareMnt;

  /// Unix second after which this offer should no longer be acted on: the
  /// driver's promise has a shelf life.
  ///
  /// A driver who offered 3 000₮ and a four-minute ETA six minutes ago is
  /// somewhere else now, and a passenger who taps that stale row hands a
  /// pickup to a car that has already gone. So the driver stamps a deadline
  /// (`now + kOfferValiditySeconds`), the passenger's list counts down to it
  /// and drops the row when it passes, and the promise a passenger can still
  /// act on is only ever one the driver can still keep.
  ///
  /// `null` — the default — is an offer with no deadline, which is every
  /// offer built before this field existed: the list shows it with no timer
  /// and never expires it, exactly as it behaved then. A wrong-typed value is
  /// rejected with the whole offer, like every other numeric field here
  /// ([_optionalInt] throws), so a garbage deadline drops the one offer that
  /// carried it and never reaches the list. And because the deadline rides on
  /// the driver's own offer, the worst a peer can do is misdate their *own* —
  /// there is no field here through which one offer can expire another.
  final int? expiresAtSeconds;

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
    this.driverGeohash,
    this.kmTariffMnt,
    this.waitTariffMntPerMinute,
    this.durationTariffMntPerMinute,
    this.bookingBaseMnt,
    this.minFareMnt,
    this.expiresAtSeconds,
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
        driverGeohash: _optionalGeohashOrNull(map, 'driverGeohash'),
        kmTariffMnt: _optionalInt(map, 'kmTariffMnt'),
        waitTariffMntPerMinute: _optionalInt(map, 'waitTariffMntPerMinute'),
        durationTariffMntPerMinute: _optionalInt(
          map,
          'durationTariffMntPerMinute',
        ),
        bookingBaseMnt: _optionalInt(map, 'bookingBaseMnt'),
        minFareMnt: _optionalInt(map, 'minFareMnt'),
        expiresAtSeconds: _optionalInt(map, 'expiresAtSeconds'),
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
    if (driverGeohash != null) 'driverGeohash': driverGeohash,
    if (kmTariffMnt != null) 'kmTariffMnt': kmTariffMnt,
    if (waitTariffMntPerMinute != null)
      'waitTariffMntPerMinute': waitTariffMntPerMinute,
    if (durationTariffMntPerMinute != null)
      'durationTariffMntPerMinute': durationTariffMntPerMinute,
    if (bookingBaseMnt != null) 'bookingBaseMnt': bookingBaseMnt,
    if (minFareMnt != null) 'minFareMnt': minFareMnt,
    if (expiresAtSeconds != null) 'expiresAtSeconds': expiresAtSeconds,
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

  /// A bonus the passenger chose to add on top of the driver's own quoted
  /// price, or `null` when they added nothing.
  ///
  /// This is what replaced the passenger naming a price up front. That old
  /// field was a guess made before anyone had quoted anything, and a guess
  /// that landed low simply produced no offers -- so the passenger sat
  /// watching an empty list with nothing telling them why. A bonus is the
  /// same wish ("I will pay more to get picked up") expressed at the only
  /// moment it can mean something: against a real figure from a real driver
  /// who is actually nearby.
  ///
  /// Carried on the handoff rather than sent as a counter-offer because it
  /// needs no negotiation. The driver has already named their price and the
  /// passenger is accepting it; the bonus only ever moves the total
  /// upwards, so there is nothing for the driver to agree to and no round
  /// trip to wait through. What matters is that the two screens show the
  /// same total, which is why it travels at all rather than staying a
  /// private intention the passenger hands over in cash.
  ///
  /// `null` rather than `0` for absent, and never negative -- a "bonus"
  /// that reduced the agreed price would be a counter-offer wearing the
  /// wrong name, and the driver would have accepted a number they never
  /// saw. `RideOfferSelection.tipMnt` refuses one before it gets here.
  final int? tipMnt;

  /// A four-digit code the passenger's screen shows and the driver types in
  /// before the meter starts, confirming the two people are actually
  /// together (spec §7.1 pickup handoff; the anti-fraud half of the local,
  /// server-less flow).
  ///
  /// Generated on the passenger's device at handoff (`generateStartCode`),
  /// carried inside this NIP-17 gift-wrap to the one driver, and checked by
  /// the driver against what the passenger reads out. Without it, a driver
  /// could start a fare on a stranger, or the wrong passenger could get into
  /// the wrong car — the mistakes a dispatcher's ride-ID would otherwise
  /// catch, closed here without a server.
  ///
  /// `null` on a handoff from a client older than this field, or one built
  /// in code without a code — the driver's UI then simply skips the
  /// confirmation step rather than blocking a trip it cannot verify.
  final String? startCode;

  const RideHandoffPayload({
    required this.rideRequestId,
    required this.tripId,
    required this.lat,
    required this.lon,
    required this.plusCode,
    required this.landmarkText,
    this.phone,
    this.tipMnt,
    this.startCode,
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
        tipMnt: _optionalPositiveIntOrNull(map, 'tipMnt'),
        startCode: _optionalStartCode(map, 'startCode'),
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
    if (tipMnt != null) 'tipMnt': tipMnt,
    if (startCode != null) 'startCode': startCode,
  };
}

/// Either side backing out before the trip starts (spec §7.5).
final class RideCancelPayload extends RideDmPayload {
  final String rideRequestId;

  /// The free-text note that has always ridden here. Kept exactly as it was —
  /// always emitted, wrong type still refused — so its existing behaviour and
  /// tests are untouched by the structured code beside it.
  final String reason;

  /// The named reason (spec §7.5), or [RideCancelReason.unknown] when none was
  /// given. Additive and back-compatible: an old sender omits it and it reads
  /// as `unknown`; an old receiver never looks for it.
  final RideCancelReason reasonCode;

  const RideCancelPayload({
    required this.rideRequestId,
    this.reason = '',
    this.reasonCode = RideCancelReason.unknown,
  });

  factory RideCancelPayload._fromJson(Map<String, dynamic> map) =>
      RideCancelPayload(
        rideRequestId: _requiredString(map, 'rideRequestId'),
        reason: _optionalString(map, 'reason'),
        reasonCode: _optionalCancelReason(map, 'reasonCode'),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'cancel',
    'rideRequestId': rideRequestId,
    'reason': reason,
    // Omitted when unknown, so a cancel carrying no named reason is
    // byte-for-byte the message this app sent before the field existed — an
    // old client reading it sees exactly what it always did.
    if (reasonCode != RideCancelReason.unknown)
      'reasonCode': reasonCode.wireValue,
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
  /// The distance half is never sent: it is [finalFareMnt] minus every time
  /// charge beside it -- [finalWaitingFareMnt] and [finalDurationFareMnt] --
  /// and a number sent twice is a number that can arrive contradicting
  /// itself. `null` on a fixed-price trip and on any status sent by a client
  /// built before waiting fares existed.
  final int? finalWaitingFareMnt;
  final int? finalWaitingSeconds;

  /// The trip-duration share of [finalFareMnt] and the seconds it covers --
  /// the third rate, billed on every second from the first GPS fix to the
  /// last (author's ruling, 2026-08-01). Sent for the same reason the
  /// waiting pair is: the passenger's phone measured a different trip.
  ///
  /// These seconds **overlap** [finalWaitingSeconds] on purpose: a stopped
  /// second is inside the trip's duration too, so a driver charging both
  /// rates bills it twice. Both rows therefore have to arrive separately --
  /// summing them into one "time" figure would present the passenger with a
  /// number that matches no rate they were quoted, and hide the double
  /// charge they actually agreed to when they picked this offer.
  ///
  /// `null` on a fixed-price trip and on any status from a client built
  /// before this rate existed -- which is why the receiving side treats
  /// absent as zero rather than as an error: those trips genuinely had no
  /// duration charge.
  final int? finalDurationFareMnt;
  final int? finalDurationSeconds;

  /// The flat booking base charged once on this trip (the fee for the drive to
  /// the passenger), and the minimum-fare top-up that lifted a short fare to
  /// the floor. Sent for the same reason the time charges are: the passenger's
  /// phone cannot recompute the driver's, and the confirm screen has to show
  /// each as its own row rather than folding it into distance -- a booking base
  /// or a floor reported as kilometres is a row claiming the car drove further
  /// than it did. Both are part of [finalFareMnt]; the derived distance row is
  /// [finalFareMnt] minus every one of these charges. `null` on a fixed-price
  /// trip and on any status from a client built before these fees existed --
  /// which is why absent is read as zero, not as an error: those trips had no
  /// booking base and no floor.
  final int? finalBaseFareMnt;
  final int? finalMinFareTopUpMnt;

  const RideTripStatusPayload({
    required this.tripId,
    required this.phase,
    this.finalFareMnt,
    this.finalWaitingFareMnt,
    this.finalWaitingSeconds,
    this.finalDurationFareMnt,
    this.finalDurationSeconds,
    this.finalBaseFareMnt,
    this.finalMinFareTopUpMnt,
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
      finalDurationFareMnt: _optionalInt(map, 'finalDurationFareMnt'),
      finalDurationSeconds: _optionalInt(map, 'finalDurationSeconds'),
      finalBaseFareMnt: _optionalInt(map, 'finalBaseFareMnt'),
      finalMinFareTopUpMnt: _optionalInt(map, 'finalMinFareTopUpMnt'),
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
    if (finalDurationFareMnt != null)
      'finalDurationFareMnt': finalDurationFareMnt,
    if (finalDurationSeconds != null)
      'finalDurationSeconds': finalDurationSeconds,
    if (finalBaseFareMnt != null) 'finalBaseFareMnt': finalBaseFareMnt,
    if (finalMinFareTopUpMnt != null)
      'finalMinFareTopUpMnt': finalMinFareTopUpMnt,
  };
}

/// A one-tap coordination message between the two people on a trip while they
/// find each other at the kerb (spec §6 "Тохироо"): "on my way", "I'm here",
/// "coming out", "one moment". See [CannedMessage] for why the set is fixed.
///
/// [tripId] scopes it to the trip in progress, so a stray message from a
/// finished or a different ride cannot raise a banner on this one. The sender
/// is the gift-wrap's verified pubkey, never a self-reported field, so nothing
/// here says *who* — the receiver already knows the one person they are on a
/// trip with.
final class RideCannedMessagePayload extends RideDmPayload {
  final String tripId;
  final CannedMessage message;

  const RideCannedMessagePayload({
    required this.tripId,
    required this.message,
  });

  factory RideCannedMessagePayload._fromJson(Map<String, dynamic> map) =>
      RideCannedMessagePayload(
        tripId: _requiredString(map, 'tripId'),
        // Throws on an unrecognized preset, which drops this one message
        // rather than painting a banner nobody can read — see
        // [CannedMessage.fromWire].
        message: CannedMessage.fromWire(_requiredString(map, 'message')),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'canned_message',
    'tripId': tripId,
    'message': message.wireValue,
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
