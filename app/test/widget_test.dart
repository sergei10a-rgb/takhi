// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:takhi/main.dart';

void main() {
  testWidgets('TakhiApp boots and shows placeholder home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: TakhiApp()));

    expect(find.text('Тахь'), findsOneWidget);
  });
}
