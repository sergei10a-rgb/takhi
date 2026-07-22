// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

const _sample = DriverProfile(
  name: 'Бат',
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
    expect(loaded!.name, 'Бат');
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
      expect(loaded!.name, 'Бат');
      expect(loaded.car, 'Prius 20');
      expect(loaded.color, 'цагаан');
      expect(loaded.plate, '1234УНА');
      expect(loaded.kmTariffMnt, 1500);
    },
  );
}
