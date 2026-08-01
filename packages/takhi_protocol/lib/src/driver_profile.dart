// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'event.dart';
import 'takhi_events.dart';

/// Builds a driver's public kind-0 profile with the `takhi` extension (spec
/// §6 "Профайл | 0 + takhi өргөтгөл"): a replaceable event whose `content`
/// is a JSON object carrying the driver-only fields (car, color, plate,
/// and all three tariffs -- km, stopped-time, trip-duration).
///
/// Two things this deliberately never emits, for the same reason by two
/// different routes:
///
///  * **A bank QR field.** Spec §8 is explicit that the QR image never
///    touches any public profile (doxxing risk); it stays device-local
///    (`app/lib/payment/driver_qr_store.dart`).
///  * **The driver's name.** A kind-0 event is world-readable and
///    permanently replicated across every relay it reaches, so a `name`
///    here is a name anyone can harvest and keep, forever, against a
///    stable pubkey that also publishes a plate number and a live
///    geohash. The driver's name -- and their photograph -- reach exactly
///    one passenger instead, inside the NIP-17 gift-wrapped offer, and
///    only once that passenger has published a request the driver chose to
///    answer. That is the same "vague in public, exact to the person you
///    are actually dealing with" tiering spec §6 already applies to
///    location, applied to identity.
///
/// There is no `name:` parameter at all, rather than an optional one that
/// callers are asked not to pass: a parameter that exists is a parameter
/// that eventually gets filled in.
NostrEvent buildDriverProfile({
  required String pubkey,
  required int now,
  required String car,
  required String color,
  required String plate,
  required int kmTariffMnt,
  int waitTariffMntPerMinute = 0,
  int durationTariffMntPerMinute = 0,
}) {
  final content = jsonEncode({
    'takhi': {
      'car': car,
      'color': color,
      'plate': plate,
      'km_tariff': kmTariffMnt,
      // Always written, including the zero: a passenger comparing drivers
      // must be able to tell "waiting is free with me" from "this driver
      // published before the field existed and I do not know yet".
      'wait_tariff': waitTariffMntPerMinute,
      // Written unconditionally for the same reason as `wait_tariff`, and
      // it matters more here: this rate runs on every second of the trip,
      // so a passenger who cannot tell "the driver set it to zero" from
      // "this profile predates the field" cannot tell what the ride will
      // cost at all.
      'duration_tariff': durationTariffMntPerMinute,
    },
  });
  return NostrEvent(
    pubkey: pubkey,
    createdAt: now,
    kind: kKindProfile,
    tags: const [],
    content: content,
  );
}

/// A driver's profile: the vehicle and price fields that go out publicly
/// (see [buildDriverProfile]), plus the two name parts that do not.
///
/// [familyName] and [givenName] are nullable, and their nullability means
/// exactly one of two things depending on where the instance came from:
///
///  * **Parsed from a relay** ([parseDriverProfile]) -- always `null`, by
///    construction. Names are never published, so a public profile has none
///    to read, and this type cannot be used to smuggle one in from a relay
///    even if some other client publishes a `name` field anyway.
///  * **Loaded from this device's own store** -- `null` means the driver
///    has not filled them in yet. That includes every profile saved before
///    names existed, which is why they are not `required`: a driver must
///    not lose their car, plate and tariffs because one field was added
///    beside them.
///
/// A driver needs both parts filled in before they may send an offer; that
/// rule lives in the app layer (`profile/driver_offer_eligibility.dart`)
/// rather than in this constructor, because a half-filled profile is a
/// perfectly valid thing to hold in memory while it is being typed.
class DriverProfile {
  /// Овог. Normally written as an initial in Mongolia (`Б.`), which is why
  /// [driverNamePartProblem] accepts a trailing period.
  final String? familyName;

  /// Нэр -- the name a passenger actually uses out loud.
  final String? givenName;

  final String car, color, plate;
  final int kmTariffMnt;

  /// What this driver charges per minute stopped in traffic (spec §7.4).
  /// Published next to [kmTariffMnt] rather than revealed at the end of the
  /// trip: a metered price a passenger only learns half of is not a price
  /// they agreed to. Zero — the default, and what a profile published before
  /// this field existed parses as — means waiting is free.
  final int waitTariffMntPerMinute;

  /// What this driver charges per minute of the trip's whole duration —
  /// every second from the first GPS fix to the last, moving or stopped.
  ///
  /// The third rate, independent of the other two, and deliberately
  /// overlapping [waitTariffMntPerMinute]: a driver who sets both charges
  /// stopped minutes under both, because a stopped minute is part of the
  /// trip's duration as well. That is the app author's decision and the
  /// driver's own commercial one — the protocol carries all three numbers
  /// and refuses to arbitrate between them. Published for the same reason
  /// the other two are: a metered price a passenger only learns part of is
  /// not a price they agreed to. Zero — the default, and what a profile
  /// published before this field existed parses as — means the trip's
  /// duration is not charged for.
  final int durationTariffMntPerMinute;

  const DriverProfile({
    required this.car,
    required this.color,
    required this.plate,
    required this.kmTariffMnt,
    this.familyName,
    this.givenName,
    this.waitTariffMntPerMinute = 0,
    this.durationTariffMntPerMinute = 0,
  });

  /// Both name parts, in the order Mongolian names are written and said --
  /// family name first (`Б. Батбаяр`) -- or `null` while either half is
  /// still missing.
  ///
  /// Null rather than a partial string on purpose: half a name shown as if
  /// it were the whole one is worse than a pubkey, because a passenger
  /// reading «Батбаяр» has no way to tell it is incomplete.
  String? get fullName {
    final family = familyName, given = givenName;
    if (family == null || given == null) return null;
    if (family.isEmpty || given.isEmpty) return null;
    return '$family $given';
  }

  DriverProfile copyWith({
    String? familyName,
    String? givenName,
    String? car,
    String? color,
    String? plate,
    int? kmTariffMnt,
    int? waitTariffMntPerMinute,
    int? durationTariffMntPerMinute,
  }) =>
      DriverProfile(
        familyName: familyName ?? this.familyName,
        givenName: givenName ?? this.givenName,
        car: car ?? this.car,
        color: color ?? this.color,
        plate: plate ?? this.plate,
        kmTariffMnt: kmTariffMnt ?? this.kmTariffMnt,
        waitTariffMntPerMinute:
            waitTariffMntPerMinute ?? this.waitTariffMntPerMinute,
        durationTariffMntPerMinute:
            durationTariffMntPerMinute ?? this.durationTariffMntPerMinute,
      );
}

/// Parses [e]'s `content` back into a [DriverProfile]. [e] may originate
/// from a public relay -- any other pubkey can publish an arbitrary kind-0
/// event -- so every field is type-checked explicitly and a
/// [FormatException], never an uncaught [TypeError], is thrown on any
/// mismatch (mirrors `NostrEvent.fromJson`'s and `RideDmPayload.decode`'s
/// "never crash on foreign input" convention).
///
/// Any `name` the content happens to carry is ignored rather than read.
/// Some other client -- or an older build of this one -- may well publish
/// one; treating it as the driver's name would put a world-readable,
/// unverified, attacker-choosable string on a passenger's screen next to a
/// face, which is the exact thing the encrypted-offer route exists to
/// avoid. The names on a [DriverProfile] come from this device's own store
/// or from a gift-wrapped offer, and from nowhere else.
DriverProfile parseDriverProfile(NostrEvent e) {
  if (e.kind != kKindProfile) {
    throw FormatException('not a profile event (kind ${e.kind})');
  }
  // jsonDecode itself throws FormatException on malformed JSON, matching
  // this function's own "never an uncaught TypeError" contract without any
  // extra catch/rethrow.
  final decoded = jsonDecode(e.content);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException(
      'profile content must be a JSON object, got ${decoded.runtimeType}',
    );
  }
  final content = decoded;
  final takhiRaw = content['takhi'];
  if (takhiRaw is! Map<String, dynamic>) {
    throw FormatException(
      "profile content missing the 'takhi' extension object",
    );
  }
  return DriverProfile(
    car: _requiredString(takhiRaw, 'car'),
    color: _requiredString(takhiRaw, 'color'),
    plate: _requiredString(takhiRaw, 'plate'),
    kmTariffMnt: _requiredInt(takhiRaw, 'km_tariff'),
    waitTariffMntPerMinute: _optionalInt(takhiRaw, 'wait_tariff'),
    durationTariffMntPerMinute: _optionalInt(takhiRaw, 'duration_tariff'),
  );
}

String _requiredString(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is String) return value;
  throw FormatException(
    "parseDriverProfile: '$field' must be a String, got "
    '${value.runtimeType}',
  );
}

int _requiredInt(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is int) return value;
  throw FormatException(
    "parseDriverProfile: '$field' must be an int, got ${value.runtimeType}",
  );
}

/// Reads a field a profile published by an older client simply will not
/// have. Absent means zero; present-but-wrong-typed is still a
/// [FormatException], because that is a malformed profile rather than an
/// older one.
int _optionalInt(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value == null) return 0;
  return _requiredInt(map, field);
}
