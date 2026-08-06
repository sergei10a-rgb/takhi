// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

const _sample = DriverProfile(
  familyName: 'Б.',
  givenName: 'Бат',
  car: 'Prius 20',
  color: 'цагаан',
  plate: '1234УНА',
  kmTariffMnt: 1500,
);

void main() {
  test('InMemoryDriverProfileStore round-trips a saved profile', () async {
    final store = InMemoryDriverProfileStore();
    expect(await store.load(), isNull);
    await store.save(_sample);
    final loaded = await store.load();
    expect(loaded!.fullName, 'Б. Бат');
    expect(loaded.car, 'Prius 20');
    expect(loaded.color, 'цагаан');
    expect(loaded.plate, '1234УНА');
    expect(loaded.kmTariffMnt, 1500);
  });

  test(
    'SharedPreferencesDriverProfileStore persists via shared_preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesDriverProfileStore(
        SharedPreferences.getInstance,
      );
      expect(await store.load(), isNull);
      await store.save(_sample);
      final loaded = await store.load();
      expect(loaded!.fullName, 'Б. Бат');
      expect(loaded.car, 'Prius 20');
      expect(loaded.color, 'цагаан');
      expect(loaded.plate, '1234УНА');
      expect(loaded.kmTariffMnt, 1500);
    },
  );

  // A driver who filled in their profile before the name was split in two
  // has a single `name` cached on their phone. Losing it would send them
  // back to a blank form for a change that has nothing to do with their
  // car, colour, plate or tariffs.
  group('a profile cached before the name was split', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<DriverProfile?> loadLegacy(Map<String, dynamic> stored) async {
      SharedPreferences.setMockInitialValues({
        'takhi_driver_profile_v1': jsonEncode(stored),
      });
      return SharedPreferencesDriverProfileStore(
        SharedPreferences.getInstance,
      ).load();
    }

    test('keeps the vehicle half intact', () async {
      final loaded = await loadLegacy({
        'name': 'Батбаяр',
        'car': 'Prius 20',
        'color': 'цагаан',
        'plate': '1234УНА',
        'km_tariff': 1500,
      });
      expect(loaded!.car, 'Prius 20');
      expect(loaded.plate, '1234УНА');
      expect(loaded.kmTariffMnt, 1500);
    });

    // Carried over as the *given* name: that is what a driver typing one
    // name into a box labelled «Нэр» meant by it. They are left one field
    // to add rather than a whole form to retype.
    test('carries the old single name over as the given name', () async {
      final loaded = await loadLegacy({
        'name': 'Батбаяр',
        'car': 'Prius 20',
        'color': 'цагаан',
        'plate': '1234УНА',
        'km_tariff': 1500,
      });
      expect(loaded!.givenName, 'Батбаяр');
      expect(loaded.familyName, isNull);
      // Still incomplete, so the offer gate keeps refusing until the
      // family name is filled in -- which is the point.
      expect(loaded.fullName, isNull);
    });

    test('drops a legacy name that is not a usable name part', () async {
      final loaded = await loadLegacy({
        'name': 'Жолооч №7',
        'car': 'Prius 20',
        'color': 'цагаан',
        'plate': '1234УНА',
        'km_tariff': 1500,
      });
      expect(loaded!.givenName, isNull);
      expect(loaded.car, 'Prius 20');
    });

    test('a new-format profile ignores any legacy name beside it', () async {
      final loaded = await loadLegacy({
        'name': 'Хуучин',
        'family_name': 'Б.',
        'given_name': 'Батбаяр',
        'car': 'Prius 20',
        'color': 'цагаан',
        'plate': '1234УНА',
        'km_tariff': 1500,
      });
      expect(loaded!.fullName, 'Б. Батбаяр');
    });
  });

  // The store is the only place a driver's name is ever written down. If it
  // ever started round-tripping through the public profile builder instead,
  // this is where that would show up.
  test('a saved profile with no name yet round-trips as nameless', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesDriverProfileStore(
      SharedPreferences.getInstance,
    );
    await store.save(
      const DriverProfile(
        car: 'Prius',
        color: 'хар',
        plate: '1234УНА',
        kmTariffMnt: 1500,
      ),
    );
    final loaded = await store.load();
    expect(loaded!.familyName, isNull);
    expect(loaded.givenName, isNull);
    expect(loaded.car, 'Prius');
  });

  // All three rates are part of the profile a driver typed in once, so all
  // three have to survive the round trip through storage. A rate that comes
  // back as zero is not a cosmetic loss: it is a driver quietly working for
  // less than they set.
  test('all three tariffs survive a save/load round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesDriverProfileStore(
      SharedPreferences.getInstance,
    );
    await store.save(
      const DriverProfile(
        car: 'Prius',
        color: 'хар',
        plate: '1234УНА',
        kmTariffMnt: 1500,
        waitTariffMntPerMinute: 300,
        durationTariffMntPerMinute: 200,
      ),
    );
    final loaded = await store.load();
    expect(loaded!.kmTariffMnt, 1500);
    expect(loaded.waitTariffMntPerMinute, 300);
    expect(loaded.durationTariffMntPerMinute, 200);
  });

  // Same argument as the legacy-name group above, for the rate added after
  // it: a driver should not have to re-enter their whole profile because one
  // field was added to it.
  group('a profile cached before a tariff field existed', () {
    Future<DriverProfile?> loadLegacy(Map<String, dynamic> stored) async {
      SharedPreferences.setMockInitialValues({
        'takhi_driver_profile_v1': jsonEncode(stored),
      });
      return SharedPreferencesDriverProfileStore(
        SharedPreferences.getInstance,
      ).load();
    }

    test('loads with a zero duration tariff rather than throwing', () async {
      final loaded = await loadLegacy({
        'family_name': 'Б.',
        'given_name': 'Батбаяр',
        'car': 'Prius 20',
        'color': 'цагаан',
        'plate': '1234УНА',
        'km_tariff': 1500,
        'wait_tariff': 300,
      });
      expect(loaded!.durationTariffMntPerMinute, 0);
      // Everything the driver *had* filled in is still there -- the whole
      // point of migrating rather than discarding.
      expect(loaded.waitTariffMntPerMinute, 300);
      expect(loaded.kmTariffMnt, 1500);
      expect(loaded.fullName, 'Б. Батбаяр');
    });

    // The oldest shape on a real device: km-tariff only, from before either
    // time-based rate existed.
    test(
      'loads with both time rates at zero when neither was cached',
      () async {
        final loaded = await loadLegacy({
          'car': 'Prius 20',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': 1500,
        });
        expect(loaded!.waitTariffMntPerMinute, 0);
        expect(loaded.durationTariffMntPerMinute, 0);
        expect(loaded.kmTariffMnt, 1500);
      },
    );
  });

  // Field-test bug (2026-08): load() must survive a blob it cannot parse --
  // broken JSON, or a required field of the wrong type from a partial or
  // foreign write -- by returning null, not by throwing. A throw here is an
  // uncaught error on the profile page's open, which the driver reads as "my
  // registration vanished and I can't get it back".
  group('a corrupt or foreign blob', () {
    Future<DriverProfile?> loadRaw(String raw) async {
      SharedPreferences.setMockInitialValues({'takhi_driver_profile_v1': raw});
      return SharedPreferencesDriverProfileStore(
        SharedPreferences.getInstance,
      ).load();
    }

    test('returns null when the JSON itself is broken', () async {
      expect(await loadRaw('not json at all'), isNull);
    });

    test('returns null when a required field has the wrong type', () async {
      expect(
        await loadRaw(
          '{"car":"Prius","color":"цагаан","plate":"УБА","km_tariff":"1500"}',
        ),
        isNull,
      );
    });

    test('returns null when a required field is missing', () async {
      expect(await loadRaw('{"car":"Prius","km_tariff":1500}'), isNull);
    });
  });
}
