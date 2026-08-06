// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

/// The driver's own public profile (spec §6 "Профайл | 0 + takhi
/// өргөтгөл"), cached locally so the app can show/re-publish it without a
/// relay round trip and so other flows (§7.2 GPS-taximeter pricing) can
/// read the driver's own km-tariff instantly. Mirrors `TariffStore`
/// (`meter/tariff_store.dart`)'s interface/SharedPreferences/InMemory
/// shape -- that store remains the local-only stand-in for the fully
/// offline §7.4 street-hail meter, which never touches identity or a
/// public profile at all; this store is the superset used once a driver
/// has a takhi identity and wants their profile to actually reach a relay.
abstract interface class DriverProfileStore {
  Future<void> save(DriverProfile profile);
  Future<DriverProfile?> load();
}

class SharedPreferencesDriverProfileStore implements DriverProfileStore {
  static const _key = 'takhi_driver_profile_v1';
  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesDriverProfileStore(this._prefs);

  @override
  Future<void> save(DriverProfile profile) async {
    final prefs = await _prefs();
    await prefs.setString(
      _key,
      jsonEncode({
        // Local only. These two are the halves of the driver's name, and
        // this file -- not the published kind-0 -- is the only place they
        // are ever written down. See `DriverPhotoStore`'s doc comment for
        // the same argument at more length.
        if (profile.familyName != null) 'family_name': profile.familyName,
        if (profile.givenName != null) 'given_name': profile.givenName,
        'car': profile.car,
        'color': profile.color,
        'plate': profile.plate,
        'km_tariff': profile.kmTariffMnt,
        'wait_tariff': profile.waitTariffMntPerMinute,
        'duration_tariff': profile.durationTariffMntPerMinute,
      }),
    );
  }

  @override
  Future<DriverProfile?> load() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    // The blob is untrusted input: a write that never finished, or one from a
    // build that structured the profile differently, must load as "no profile
    // cached" rather than throw an uncaught cast error onto the page that
    // reads it on open. To a driver that throw reads as their registration
    // vanishing with no way back (field-test bug, 2026-08).
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final car = decoded['car'];
    final color = decoded['color'];
    final plate = decoded['plate'];
    final km = decoded['km_tariff'];
    // The four the vehicle half cannot be reconstructed without. A blob
    // missing any of them, or holding the wrong type for it, is not a profile
    // this build can trust -- treat it as none rather than half-load it.
    if (car is! String || color is! String || plate is! String || km is! int) {
      return null;
    }
    final family = decoded['family_name'];
    final wait = decoded['wait_tariff'];
    final duration = decoded['duration_tariff'];
    return DriverProfile(
      familyName: family is String ? family : null,
      // A profile cached before the name was split in two carries a single
      // `name`. It is carried over as the *given* name, because that is
      // what a Mongolian driver typing one name into a box labelled «Нэр»
      // meant by it -- leaving them one field to fill in rather than a
      // whole form to retype. Anything that is not a usable name part is
      // dropped instead, so a legacy value cannot smuggle past the rule
      // the form itself enforces.
      givenName: _migratedGivenName(decoded),
      car: car,
      color: color,
      plate: plate,
      kmTariffMnt: km,
      // Absent (or, defensively, the wrong type) on a profile this device
      // cached before waiting fares existed; a driver should not have to
      // re-enter their whole profile because one field was added to it.
      waitTariffMntPerMinute: wait is int ? wait : 0,
      // The same migration for the third rate, and the same reason. Zero is
      // also the honest reading of an older cache: a driver who has never
      // seen this field has never set it, so the trip's duration goes
      // uncharged until they decide otherwise -- which is the direction
      // that cannot surprise a passenger.
      durationTariffMntPerMinute: duration is int ? duration : 0,
    );
  }

  static String? _migratedGivenName(Map<String, dynamic> map) {
    final current = map['given_name'];
    if (current is String) return current;
    final legacy = map['name'];
    if (legacy is! String) return null;
    final normalized = normalizeDriverNamePart(legacy);
    return isValidDriverNamePart(normalized) ? normalized : null;
  }
}

/// Test double, mirrors `InMemoryTariffStore` (`meter/tariff_store.dart`).
class InMemoryDriverProfileStore implements DriverProfileStore {
  DriverProfile? _value;

  @override
  Future<void> save(DriverProfile profile) async => _value = profile;

  @override
  Future<DriverProfile?> load() async => _value;
}
