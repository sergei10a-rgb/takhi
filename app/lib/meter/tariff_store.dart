// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// What the driver charges: one rate per kilometre travelled and one per
/// minute waited (spec §7.4). Kept as one value rather than two loose ints
/// because they are only ever meaningful together — a run metered with one
/// driver's distance rate and another's waiting rate would be nobody's
/// price.
///
/// [mntPerMinute] defaults to zero, which means waiting is free. That is
/// both a legitimate choice a driver can make and what a tariff saved
/// before waiting fares existed migrates to.
class DriverTariff {
  final int mntPerKm;
  final int mntPerMinute;

  const DriverTariff({required this.mntPerKm, this.mntPerMinute = 0});

  /// Compared by value: this is held in screen state and diffed against a
  /// freshly loaded copy, where identity comparison would silently report
  /// every load as a change.
  @override
  bool operator ==(Object other) =>
      other is DriverTariff &&
      other.mntPerKm == mntPerKm &&
      other.mntPerMinute == mntPerMinute;

  @override
  int get hashCode => Object.hash(mntPerKm, mntPerMinute);

  @override
  String toString() => 'DriverTariff($mntPerKm₮/км, $mntPerMinute₮/мин)';
}

/// The driver's own tariff, local-only. Plan 3 (spec §16, own
/// Self-Review open question #4) explicitly deferred the public kind-0
/// profile extension (car/plate/km-tariff) as not yet built — this store
/// is the taximeter's local-only stand-in for those fields, never published,
/// never part of any Nostr event.
abstract interface class TariffStore {
  Future<void> save(DriverTariff tariff);

  /// The saved tariff, or `null` when the driver has not set one yet — the
  /// state `TaximeterPage` shows its "set your rate" step for.
  Future<DriverTariff?> load();
}

class SharedPreferencesTariffStore implements TariffStore {
  /// Unchanged from when this store held nothing but a km-tariff, so an
  /// existing install keeps the rate its driver already typed. That is the
  /// whole migration: an old install has this key and not [_minuteKey], and
  /// reads back as a driver who charges nothing for waiting until they say
  /// otherwise.
  static const _kmKey = 'takhi_driver_tariff_mnt_per_km';
  static const _minuteKey = 'takhi_driver_tariff_mnt_per_minute';

  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesTariffStore(this._prefs);

  @override
  Future<void> save(DriverTariff tariff) async {
    final prefs = await _prefs();
    await prefs.setInt(_kmKey, tariff.mntPerKm);
    await prefs.setInt(_minuteKey, tariff.mntPerMinute);
  }

  @override
  Future<DriverTariff?> load() async {
    final prefs = await _prefs();
    final mntPerKm = prefs.getInt(_kmKey);
    // The km-tariff alone decides whether a tariff exists at all: it is the
    // one a run cannot be metered without, and the only one an older
    // version of the app ever wrote.
    if (mntPerKm == null) return null;
    return DriverTariff(
      mntPerKm: mntPerKm,
      mntPerMinute: prefs.getInt(_minuteKey) ?? 0,
    );
  }
}

/// Test double, mirrors `InMemoryKeyStore` (`identity/identity_service.dart`).
class InMemoryTariffStore implements TariffStore {
  DriverTariff? _value;

  @override
  Future<void> save(DriverTariff tariff) async => _value = tariff;

  @override
  Future<DriverTariff?> load() async => _value;
}
