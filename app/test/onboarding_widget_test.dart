// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:takhi/onboarding/onboarding_page.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/l10n/app_localizations.dart';

void main() {
  testWidgets('onboarding shows brand name and create button', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const OnboardingPage(),
      ),
    ));
    expect(find.text('Тахь'), findsWidgets);
    expect(find.text('Шинээр эхлэх'), findsOneWidget);
    expect(find.text('Зорчигч'), findsOneWidget);
  });
}
