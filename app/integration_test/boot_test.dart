// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:takhi/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('app boots to onboarding without crashing', (t) async {
    app.main();
    await t.pumpAndSettle();
    expect(find.text('Тахь'), findsWidgets);
  });
}
