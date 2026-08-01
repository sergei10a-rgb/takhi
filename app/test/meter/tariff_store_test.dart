// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/meter/tariff_store.dart';

void main() {
  test('InMemoryTariffStore round-trips all three tariffs', () async {
    final store = InMemoryTariffStore();
    expect(await store.load(), isNull);
    await store.save(
      const DriverTariff(
        mntPerKm: 1200,
        mntPerMinute: 300,
        durationMntPerMinute: 100,
      ),
    );
    final loaded = await store.load();
    expect(loaded?.mntPerKm, 1200);
    expect(loaded?.mntPerMinute, 300);
    expect(loaded?.durationMntPerMinute, 100);
  });

  test('DriverTariff leaves both minute rates at zero when they are not '
      'given, so a driver who sets neither is charged for neither', () {
    const tariff = DriverTariff(mntPerKm: 1000);
    expect(tariff.mntPerMinute, 0);
    expect(tariff.durationMntPerMinute, 0);
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
    // The third rate has to take part in the comparison too. This value is
    // held in screen state and diffed against a freshly loaded copy, so a
    // field left out of `==` is a field whose edit reads as no change at
    // all.
    expect(
      const DriverTariff(mntPerKm: 1000, durationMntPerMinute: 100),
      isNot(const DriverTariff(mntPerKm: 1000)),
    );
  });

  test('SharedPreferencesTariffStore persists all three tariffs', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesTariffStore(SharedPreferences.getInstance);
    expect(await store.load(), isNull);
    await store.save(
      const DriverTariff(
        mntPerKm: 950,
        mntPerMinute: 250,
        durationMntPerMinute: 120,
      ),
    );
    final loaded = await store.load();
    expect(loaded?.mntPerKm, 950);
    expect(loaded?.mntPerMinute, 250);
    expect(loaded?.durationMntPerMinute, 120);
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
    expect(loaded?.durationMntPerMinute, 0);
  });

  test('a tariff saved before the trip-duration rate existed still loads, '
      'keeping both rates the driver already typed and charging nothing for '
      'the new one', () async {
    // The shape a driver who has already used the stopped-time rate has on
    // disk today: two keys, no third. This is the migration that matters
    // most, because unlike the km-only case it is what every currently
    // installed copy of the app looks like.
    SharedPreferences.setMockInitialValues({
      'flutter.takhi_driver_tariff_mnt_per_km': 1500,
      'flutter.takhi_driver_tariff_mnt_per_minute': 400,
    });
    final store = SharedPreferencesTariffStore(SharedPreferences.getInstance);
    final loaded = await store.load();
    expect(loaded?.mntPerKm, 1500);
    expect(loaded?.mntPerMinute, 400);
    expect(loaded?.durationMntPerMinute, 0);
  });

  test('saving over a migrated tariff keeps the km rate the driver already '
      'had', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.takhi_driver_tariff_mnt_per_km': 1500,
    });
    final store = SharedPreferencesTariffStore(SharedPreferences.getInstance);
    final migrated = await store.load();
    await store.save(
      DriverTariff(
        mntPerKm: migrated!.mntPerKm,
        mntPerMinute: 400,
        durationMntPerMinute: 150,
      ),
    );
    final loaded = await store.load();
    expect(loaded?.mntPerKm, 1500);
    expect(loaded?.mntPerMinute, 400);
    expect(loaded?.durationMntPerMinute, 150);
  });

  test('clearing the trip-duration rate back to zero is written, not left as '
      'the number the driver just deleted', () async {
    // The failure this guards is a save that skips zeroes: a driver who
    // decides to stop charging for trip duration would empty the box, press
    // save, and find the old rate still metering every trip -- with the
    // screen showing no pill for it, because the page state says zero.
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesTariffStore(SharedPreferences.getInstance);
    await store.save(
      const DriverTariff(mntPerKm: 1500, durationMntPerMinute: 150),
    );
    await store.save(const DriverTariff(mntPerKm: 1500));
    expect((await store.load())?.durationMntPerMinute, 0);
  });
}
