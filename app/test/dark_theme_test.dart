// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/home/home_page.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/onboarding/onboarding_page.dart';
import 'package:takhi/onboarding/restore_page.dart';
import 'package:takhi/onboarding/seed_backup_page.dart';
import 'package:takhi/theme/takhi_theme.dart';

import 'support/contrast.dart';

/// WCAG AA minimum contrast ratio for normal-size body text.
const _kMinAaContrast = 4.5;

/// A [KeyStore] whose [write] always fails the way the real secure-storage
/// backend does when unavailable, to reach [OnboardingPage]'s inline error
/// state without touching a platform channel.
class _FailingKeyStore implements KeyStore {
  @override
  Future<void> write(String p) async =>
      throw const SecureStoreException('write failed', 'boom');

  @override
  Future<String?> read() async => null;

  @override
  Future<void> clear() async {}
}

class _FakeRelaySocket implements RelaySocket {
  final _c = StreamController<String>.broadcast();
  @override
  Stream<String> get messages => _c.stream;
  @override
  void send(String d) {}
  @override
  Future<void> close() async => _c.close();
  @override
  Future<void> get ready => Future<void>.value();
}

final _darkSurface = takhiTheme(Brightness.dark).colorScheme.surface;

/// Pumps [child] under a [MaterialApp] configured exactly like the real
/// app's light/dark theme pair, but forced into dark mode via
/// [ThemeMode.dark] — regardless of the host OS's actual theme setting.
Widget _darkHarness(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        themeMode: ThemeMode.dark,
        theme: takhiTheme(Brightness.light),
        darkTheme: takhiTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: child,
      ),
    );

Color? _scaffoldBackground(WidgetTester t) =>
    t.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;

void main() {
  testWidgets('OnboardingPage scaffold uses the dark surface in dark theme', (
    t,
  ) async {
    await t.pumpWidget(
      _darkHarness(
        const OnboardingPage(),
        overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
      ),
    );
    await t.pump();

    expect(_scaffoldBackground(t), _darkSurface);
  });

  testWidgets('RestorePage scaffold uses the dark surface in dark theme', (
    t,
  ) async {
    await t.pumpWidget(
      _darkHarness(
        const RestorePage(),
        overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
      ),
    );
    await t.pump();

    expect(_scaffoldBackground(t), _darkSurface);
  });

  testWidgets('SeedBackupPage scaffold uses the dark surface in dark theme', (
    t,
  ) async {
    await t.pumpWidget(
      _darkHarness(const SeedBackupPage(mnemonic: 'abandon abandon about')),
    );
    await t.pump();

    expect(_scaffoldBackground(t), _darkSurface);
  });

  testWidgets('HomePage scaffold uses the dark surface in dark theme', (
    t,
  ) async {
    await t.pumpWidget(
      _darkHarness(
        const HomePage(),
        overrides: [
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          relayPoolProvider.overrideWithValue(
            RelayPool(defaultRelayUrls, connect: (u) => _FakeRelaySocket()),
          ),
        ],
      ),
    );
    await t.pump();

    expect(_scaffoldBackground(t), _darkSurface);
  });

  group('inline error text meets WCAG AA contrast in dark mode', () {
    // Regression coverage: these three screens previously shared one fixed
    // TakhiColors.error hex that was only tuned for the light surface (see
    // design-system-audit fix). Asserting on the actually-rendered color
    // (not just equality with a constant) catches any future call site
    // that re-hardcodes the light-only value directly.
    testWidgets('OnboardingPage create-identity error', (t) async {
      await t.pumpWidget(
        _darkHarness(
          const OnboardingPage(),
          overrides: [keyStoreProvider.overrideWithValue(_FailingKeyStore())],
        ),
      );

      await t.tap(find.byType(FilledButton).first);
      await t.pumpAndSettle();

      final text = t.widget<Text>(
        find.text('Шинэ бүртгэл үүсгэж чадсангүй. Дахин оролдоно уу.'),
      );
      final color = text.style!.color!;
      final ratio = contrastRatio(color, _darkSurface);
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinAaContrast),
        reason:
            'onboarding dark-mode error text only clears '
            '${ratio.toStringAsFixed(2)}:1 against the dark surface',
      );
    });

    testWidgets('RestorePage invalid-mnemonic error', (t) async {
      await t.pumpWidget(
        _darkHarness(
          const RestorePage(),
          overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
        ),
      );

      await t.enterText(find.byType(TextField), 'not a real seed phrase');
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();

      final errorText = t.widget<Text>(
        find.text('Нөөц үг буруу байна. Дахин шалгаад оруулна уу.'),
      );
      final color = errorText.style!.color!;
      final ratio = contrastRatio(color, _darkSurface);
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinAaContrast),
        reason:
            'restore dark-mode error text only clears '
            '${ratio.toStringAsFixed(2)}:1 against the dark surface',
      );
    });

    testWidgets('SeedBackupPage warning banner', (t) async {
      await t.pumpWidget(
        _darkHarness(const SeedBackupPage(mnemonic: 'abandon abandon about')),
      );
      await t.pump();

      final icon = t.widget<Icon>(find.byIcon(Icons.warning_amber_rounded));
      final color = icon.color!;
      final ratio = contrastRatio(color, _darkSurface);
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinAaContrast),
        reason:
            'seed-backup dark-mode warning banner only clears '
            '${ratio.toStringAsFixed(2)}:1 against the dark surface',
      );
    });
  });
}
