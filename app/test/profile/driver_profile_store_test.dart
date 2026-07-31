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
}
