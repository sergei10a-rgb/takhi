// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// The driver's own km-tariff (₮/km), local-only. Plan 3 (spec §16, own
/// Self-Review open question #4) explicitly deferred the public kind-0
/// profile extension (car/plate/km-tariff) as not yet built — this store
/// is the taximeter's local-only stand-in for that field, never published,
/// never part of any Nostr event.
abstract interface class TariffStore {
  Future<void> saveMntPerKm(int mntPerKm);
  Future<int?> loadMntPerKm();
}

class SharedPreferencesTariffStore implements TariffStore {
  static const _key = 'takhi_driver_tariff_mnt_per_km';
  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesTariffStore(this._prefs);

  @override
  Future<void> saveMntPerKm(int mntPerKm) async =>
      (await _prefs()).setInt(_key, mntPerKm);

  @override
  Future<int?> loadMntPerKm() async => (await _prefs()).getInt(_key);
}

/// Test double, mirrors `InMemoryKeyStore` (`identity/identity_service.dart`).
class InMemoryTariffStore implements TariffStore {
  int? _value;

  @override
  Future<void> saveMntPerKm(int mntPerKm) async => _value = mntPerKm;

  @override
  Future<int?> loadMntPerKm() async => _value;
}
