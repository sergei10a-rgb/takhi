// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/meter/tariff_store.dart';

void main() {
  test('InMemoryTariffStore round-trips a saved value', () async {
    final store = InMemoryTariffStore();
    expect(await store.loadMntPerKm(), isNull);
    await store.saveMntPerKm(1200);
    expect(await store.loadMntPerKm(), 1200);
  });

  test('SharedPreferencesTariffStore persists via shared_preferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store =
        SharedPreferencesTariffStore(SharedPreferences.getInstance);
    expect(await store.loadMntPerKm(), isNull);
    await store.saveMntPerKm(950);
    expect(await store.loadMntPerKm(), 950);
  });
}
