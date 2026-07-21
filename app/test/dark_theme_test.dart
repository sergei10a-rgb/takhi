// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/onboarding/onboarding_page.dart';
import 'package:takhi/onboarding/restore_page.dart';
import 'package:takhi/onboarding/seed_backup_page.dart';
import 'package:takhi/router.dart';
import 'package:takhi/theme/takhi_theme.dart';

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
}
