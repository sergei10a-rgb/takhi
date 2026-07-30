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
        'name': profile.name,
        'car': profile.car,
        'color': profile.color,
        'plate': profile.plate,
        'km_tariff': profile.kmTariffMnt,
        'wait_tariff': profile.waitTariffMntPerMinute,
      }),
    );
  }

  @override
  Future<DriverProfile?> load() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return DriverProfile(
      name: map['name'] as String,
      car: map['car'] as String,
      color: map['color'] as String,
      plate: map['plate'] as String,
      kmTariffMnt: map['km_tariff'] as int,
      // Absent on a profile this device cached before waiting fares
      // existed; a driver should not have to re-enter their whole profile
      // because one field was added to it.
      waitTariffMntPerMinute: map['wait_tariff'] as int? ?? 0,
    );
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
