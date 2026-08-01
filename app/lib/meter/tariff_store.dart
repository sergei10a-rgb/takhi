// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// What the driver charges: one rate per kilometre travelled, one per minute
/// stopped, and one per minute of the trip as a whole (spec §7.4). Kept as
/// one value rather than three loose ints because they are only ever
/// meaningful together — a run metered with one driver's distance rate and
/// another's stopped-time rate would be nobody's price.
///
/// Both minute rates default to zero, which means that component is simply
/// not charged. That is a legitimate choice a driver can make, and it is
/// also what a tariff saved by an older build — one that knew about fewer
/// rates than this — migrates to.
class DriverTariff {
  final int mntPerKm;

  /// The stopped-time rate («түгжрэл/зогсолт»): charged only for the seconds
  /// the vehicle stood still.
  final int mntPerMinute;

  /// The whole-trip-duration rate: charged for every second from the first
  /// GPS fix to the last, moving or not.
  ///
  /// It therefore overlaps [mntPerMinute] on purpose — a driver who fills in
  /// both charges stopped time under both, because stopped seconds are part
  /// of the trip's duration too. `computeDurationFareMnt` carries the full
  /// reasoning; this store's job is only to remember all three numbers
  /// exactly as the driver typed them, without deciding which combinations
  /// are sensible.
  final int durationMntPerMinute;

  const DriverTariff({
    required this.mntPerKm,
    this.mntPerMinute = 0,
    this.durationMntPerMinute = 0,
  });

  /// Compared by value: this is held in screen state and diffed against a
  /// freshly loaded copy, where identity comparison would silently report
  /// every load as a change.
  @override
  bool operator ==(Object other) =>
      other is DriverTariff &&
      other.mntPerKm == mntPerKm &&
      other.mntPerMinute == mntPerMinute &&
      other.durationMntPerMinute == durationMntPerMinute;

  @override
  int get hashCode => Object.hash(mntPerKm, mntPerMinute, durationMntPerMinute);

  @override
  String toString() =>
      'DriverTariff($mntPerKm₮/км, $mntPerMinute₮/мин зогсолт, '
      '$durationMntPerMinute₮/мин хугацаа)';
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

  /// Its own key rather than a change to [_minuteKey]'s shape, for the same
  /// reason [_minuteKey] was added beside [_kmKey]: an install that predates
  /// this rate simply does not have the key, reads back as zero, and keeps
  /// metering exactly as it did. Re-encoding the two existing keys to carry
  /// a third number would have made every already-shipped tariff
  /// unreadable — the one outcome a driver must never get out of an update,
  /// because the app would then quietly meter their shift at nothing.
  static const _durationMinuteKey =
      'takhi_driver_tariff_duration_mnt_per_minute';

  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesTariffStore(this._prefs);

  @override
  Future<void> save(DriverTariff tariff) async {
    final prefs = await _prefs();
    await prefs.setInt(_kmKey, tariff.mntPerKm);
    await prefs.setInt(_minuteKey, tariff.mntPerMinute);
    await prefs.setInt(_durationMinuteKey, tariff.durationMntPerMinute);
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
      durationMntPerMinute: prefs.getInt(_durationMinuteKey) ?? 0,
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
