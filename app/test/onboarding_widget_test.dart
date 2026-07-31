// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:takhi/onboarding/onboarding_page.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/info_chip.dart';
import 'package:takhi/widgets/secondary_button.dart';

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
    // Both roles are still named -- as labels now, not as a choice.
    expect(find.text('Зорчигч'), findsOneWidget);
    expect(find.text('Жолооч'), findsOneWidget);
    // Spec §4's legal/liability disclaimer, shown the first time (i.e.
    // every time onboarding itself is reachable -- a returning rider with
    // a stored identity is redirected straight past this screen, per
    // `routerProvider`'s redirect).
    expect(
      find.textContaining('Тахь бол эзэнгүй P2P платформ'),
      findsOneWidget,
    );
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

  testWidgets('the passenger/driver roles are stated, not asked: nothing on '
      'this screen reads the answer, and the control that demanded one also '
      'rendered its Cyrillic labels as empty boxes', (t) async {
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

    expect(find.byType(SegmentedButton<TakhiMode>), findsNothing);
    // `InfoChip` is documented as a label that takes no tap handler, so the
    // roles cannot be mistaken for a decision with consequences.
    expect(find.byType(InfoChip), findsNWidgets(2));
  });

  testWidgets('the disclaimer and the second entry point are legible on the '
      'light theme, where the pale parchment they used to be painted in sat '
      'on an equally pale surface', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
        child: MaterialApp(
          theme: takhiTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const OnboardingPage(),
        ),
      ),
    );

    final surfaces = TakhiSurfaces.forBrightness(Brightness.light);
    final disclaimer = t.widget<Text>(
      find.textContaining('Тахь бол эзэнгүй P2P платформ'),
    );
    // The primary foreground, off the surface ladder -- never a fixed
    // palette constant that only works against one brightness.
    expect(disclaimer.style?.color, surfaces.onSheet);
    expect(disclaimer.style?.color, isNot(TakhiColors.sand));

    expect(find.byType(SecondaryButton), findsOneWidget);
  });
}
