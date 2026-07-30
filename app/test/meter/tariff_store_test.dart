// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/meter/tariff_store.dart';

void main() {
  test('InMemoryTariffStore round-trips both tariffs', () async {
    final store = InMemoryTariffStore();
    expect(await store.load(), isNull);
    await store.save(const DriverTariff(mntPerKm: 1200, mntPerMinute: 300));
    final loaded = await store.load();
    expect(loaded?.mntPerKm, 1200);
    expect(loaded?.mntPerMinute, 300);
  });

  test('DriverTariff leaves the waiting rate at zero when it is not given, '
      'so a driver who never sets one simply charges nothing for waiting', () {
    const tariff = DriverTariff(mntPerKm: 1000);
    expect(tariff.mntPerMinute, 0);
  });

  test('DriverTariff compares by value', () {
    expect(
      const DriverTariff(mntPerKm: 1000, mntPerMinute: 300),
      const DriverTariff(mntPerKm: 1000, mntPerMinute: 300),
    );
    expect(
      const DriverTariff(mntPerKm: 1000, mntPerMinute: 300),
      isNot(const DriverTariff(mntPerKm: 1000, mntPerMinute: 250)),
    );
  });

  test('SharedPreferencesTariffStore persists both tariffs', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesTariffStore(SharedPreferences.getInstance);
    expect(await store.load(), isNull);
    await store.save(const DriverTariff(mntPerKm: 950, mntPerMinute: 250));
    final loaded = await store.load();
    expect(loaded?.mntPerKm, 950);
    expect(loaded?.mntPerMinute, 250);
  });

  test('a tariff saved before waiting fares existed still loads, as a '
      'km-tariff with no waiting charge', () async {
    // Exactly what a pre-upgrade install has on disk: the single legacy
    // key, written by the km-only store this one replaces.
    SharedPreferences.setMockInitialValues({
      'flutter.takhi_driver_tariff_mnt_per_km': 1500,
    });
    final store = SharedPreferencesTariffStore(SharedPreferences.getInstance);
    final loaded = await store.load();
    expect(loaded?.mntPerKm, 1500);
    expect(loaded?.mntPerMinute, 0);
  });

  test('saving over a migrated tariff keeps the km rate the driver already '
      'had', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.takhi_driver_tariff_mnt_per_km': 1500,
    });
    final store = SharedPreferencesTariffStore(SharedPreferences.getInstance);
    final migrated = await store.load();
    await store.save(
      DriverTariff(mntPerKm: migrated!.mntPerKm, mntPerMinute: 400),
    );
    final loaded = await store.load();
    expect(loaded?.mntPerKm, 1500);
    expect(loaded?.mntPerMinute, 400);
  });
}
