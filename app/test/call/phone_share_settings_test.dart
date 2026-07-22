// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/call/phone_share_settings.dart';

void main() {
  test(
    'isEnabled defaults to true (spec §7.3-②: "default: асаалттай")',
    () async {
      final store = InMemoryPhoneShareSettingsStore();
      expect(await store.isEnabled(), isTrue);
    },
  );

  test('setEnabled persists across reads', () async {
    final store = InMemoryPhoneShareSettingsStore();
    await store.setEnabled(false);
    expect(await store.isEnabled(), isFalse);
  });

  test('loadOwnPhone is null until saveOwnPhone is called', () async {
    final store = InMemoryPhoneShareSettingsStore();
    expect(await store.loadOwnPhone(), isNull);
    await store.saveOwnPhone('99112233');
    expect(await store.loadOwnPhone(), '99112233');
  });

  // Mirrors `SharedPreferencesTariffStore`'s coverage in
  // `tariff_store_test.dart` -- the real, provider-wired implementation
  // (`call_providers.dart`'s `phoneShareSettingsStoreProvider`) had zero
  // test coverage until now; only the in-memory double above was exercised.
  test(
    'SharedPreferencesPhoneShareSettingsStore defaults isEnabled to true',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesPhoneShareSettingsStore(
        SharedPreferences.getInstance,
      );
      expect(await store.isEnabled(), isTrue);
    },
  );

  test('SharedPreferencesPhoneShareSettingsStore.setEnabled persists via '
      'shared_preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesPhoneShareSettingsStore(
      SharedPreferences.getInstance,
    );
    await store.setEnabled(false);
    expect(await store.isEnabled(), isFalse);
  });

  test('SharedPreferencesPhoneShareSettingsStore round-trips the own phone '
      'number via shared_preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesPhoneShareSettingsStore(
      SharedPreferences.getInstance,
    );
    expect(await store.loadOwnPhone(), isNull);
    await store.saveOwnPhone('99112233');
    expect(await store.loadOwnPhone(), '99112233');
  });
}
