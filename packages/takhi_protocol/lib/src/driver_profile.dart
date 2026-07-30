// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'event.dart';
import 'takhi_events.dart';

/// Builds a driver's public kind-0 profile with the `takhi` extension (spec
/// §6 "Профайл | 0 + takhi өргөтгөл"): a replaceable event whose `content`
/// is a JSON object with a top-level `name` plus a nested `takhi` object
/// carrying the driver-only fields (car, color, plate, km-tariff).
///
/// Deliberately never accepts or emits a bank QR field -- spec §8 is
/// explicit that the QR image never touches any public profile (doxxing
/// risk); it stays device-local (`app/lib/payment/driver_qr_store.dart`)
/// and is only ever shown on-screen or sent DM-encrypted to one rider.
NostrEvent buildDriverProfile({
  required String pubkey,
  required int now,
  required String name,
  required String car,
  required String color,
  required String plate,
  required int kmTariffMnt,
  int waitTariffMntPerMinute = 0,
}) {
  final content = jsonEncode({
    'name': name,
    'takhi': {
      'car': car,
      'color': color,
      'plate': plate,
      'km_tariff': kmTariffMnt,
      // Always written, including the zero: a passenger comparing drivers
      // must be able to tell "waiting is free with me" from "this driver
      // published before the field existed and I do not know yet".
      'wait_tariff': waitTariffMntPerMinute,
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

/// The driver-relevant fields parsed out of a kind-0 profile's `takhi`
/// extension (see [buildDriverProfile]).
class DriverProfile {
  final String name, car, color, plate;
  final int kmTariffMnt;

  /// What this driver charges per minute stopped in traffic (spec §7.4).
  /// Published next to [kmTariffMnt] rather than revealed at the end of the
  /// trip: a metered price a passenger only learns half of is not a price
  /// they agreed to. Zero — the default, and what a profile published before
  /// this field existed parses as — means waiting is free.
  final int waitTariffMntPerMinute;

  const DriverProfile({
    required this.name,
    required this.car,
    required this.color,
    required this.plate,
    required this.kmTariffMnt,
    this.waitTariffMntPerMinute = 0,
  });
}

/// Parses [e]'s `content` back into a [DriverProfile]. [e] may originate
/// from a public relay -- any other pubkey can publish an arbitrary kind-0
/// event -- so every field is type-checked explicitly and a
/// [FormatException], never an uncaught [TypeError], is thrown on any
/// mismatch (mirrors `NostrEvent.fromJson`'s and `RideDmPayload.decode`'s
/// "never crash on foreign input" convention).
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
  final name = _requiredString(content, 'name');
  final takhiRaw = content['takhi'];
  if (takhiRaw is! Map<String, dynamic>) {
    throw FormatException(
      "profile content missing the 'takhi' extension object",
    );
  }
  return DriverProfile(
    name: name,
    car: _requiredString(takhiRaw, 'car'),
    color: _requiredString(takhiRaw, 'color'),
    plate: _requiredString(takhiRaw, 'plate'),
    kmTariffMnt: _requiredInt(takhiRaw, 'km_tariff'),
    waitTariffMntPerMinute: _optionalInt(takhiRaw, 'wait_tariff'),
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
