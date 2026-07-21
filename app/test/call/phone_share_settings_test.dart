// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
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
}
