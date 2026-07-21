// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:takhi/onboarding/onboarding_page.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/l10n/app_localizations.dart';

/// A [KeyStore] whose [write] always fails the way the real secure-storage
/// backend does when the OS-level backend is unavailable (locked keystore,
/// denied access, unsupported platform), to exercise the onboarding page's
/// failure path without touching a platform channel.
class _FailingKeyStore implements KeyStore {
  @override
  Future<void> write(String p) async =>
      throw const SecureStoreException('write failed', 'boom');

  @override
  Future<String?> read() async => null;

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('onboarding shows brand name and create button', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const OnboardingPage(),
        ),
      ),
    );
    expect(find.text('Тахь'), findsWidgets);
    expect(find.text('Шинээр эхлэх'), findsOneWidget);
    expect(find.text('Зорчигч'), findsOneWidget);
  });

  testWidgets('create identity surfaces an error and re-enables the button '
      'when secure storage fails', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [keyStoreProvider.overrideWithValue(_FailingKeyStore())],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const OnboardingPage(),
        ),
      ),
    );

    await t.tap(find.text('Шинээр эхлэх'));
    await t.pumpAndSettle(); // let the failed write resolve
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Шинэ бүртгэл үүсгэж чадсангүй. Дахин оролдоно уу.'),
      findsOneWidget,
    );

    // Button is enabled again for a retry, not stuck disabled forever.
    final button = t.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNotNull);
  });
}
