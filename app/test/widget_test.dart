// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:takhi/main.dart';
import 'package:takhi/onboarding/startup_gate.dart';

void main() {
  testWidgets('TakhiApp boots onto the splash continuation and still reaches '
      'a real screen when the key store never answers at all', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: TakhiApp()));

    // Nothing is known about the stored identity on the first frame, so
    // `StartupGate` holds a bare brand-coloured screen -- not the brand
    // name, and emphatically not onboarding (see `startup_gate_test.dart`).
    expect(find.text('Тахь'), findsNothing);

    // This test overrides no key store, so `SecureKeyStore` runs for real
    // -- and `flutter_secure_storage` has no plugin behind it under
    // `flutter_test`, so the read never completes. That is the wedged
    // Keystore `StartupGate.readTimeout` exists for: without the ceiling
    // this boot would sit on an empty screen forever.
    await tester.pump(StartupGate.readTimeout);

    expect(find.text('Тахь'), findsOneWidget);
  });
}
