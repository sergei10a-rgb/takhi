// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/onboarding/onboarding_page.dart';

/// A minimal harness router mirroring `routerProvider`'s `/` -> `/seed` leg,
/// without pulling in the identity-based redirect (that's covered by
/// router_redirect_test.dart) — this file is only about the confirmation
/// guard in front of [IdentityService.createNewWithMnemonic].
GoRouter _harnessRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const OnboardingPage()),
    GoRoute(
      path: '/seed',
      builder: (context, state) =>
          Scaffold(body: Center(child: Text('SEED_REACHED: ${state.extra}'))),
    ),
  ],
);

Widget _harness(KeyStore store) => ProviderScope(
  overrides: [keyStoreProvider.overrideWithValue(store)],
  child: MaterialApp.router(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('mn'),
    routerConfig: _harnessRouter(),
  ),
);

void main() {
  testWidgets('tapping "start fresh" with an identity already stored asks for '
      'confirmation instead of overwriting it immediately', (t) async {
    final store = InMemoryKeyStore();
    await IdentityService(store).createNew();
    final before = await store.read();

    await t.pumpWidget(_harness(store));
    await t.tap(find.text('Шинээр эхлэх'));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Одоогийн бүртгэлийг дарж бичих үү?'), findsOneWidget);
    expect(find.textContaining('SEED_REACHED'), findsNothing);
    expect(await store.read(), before); // untouched while the dialog is up
  });

  testWidgets('cancelling the confirmation keeps the old identity and does not '
      'navigate anywhere', (t) async {
    final store = InMemoryKeyStore();
    await IdentityService(store).createNew();
    final before = await store.read();

    await t.pumpWidget(_harness(store));
    await t.tap(find.text('Шинээр эхлэх'));
    await t.pumpAndSettle();

    await t.tap(find.text('Цуцлах'));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('SEED_REACHED'), findsNothing);
    expect(await store.read(), before);
  });

  testWidgets(
    'confirming the overwrite creates a fresh identity and proceeds to '
    'the seed backup screen',
    (t) async {
      final store = InMemoryKeyStore();
      await IdentityService(store).createNew();
      final before = await store.read();

      await t.pumpWidget(_harness(store));
      await t.tap(find.text('Шинээр эхлэх'));
      await t.pumpAndSettle();

      await t.tap(find.text('Тийм, үргэлжлүүл'));
      await t.pumpAndSettle();

      expect(find.textContaining('SEED_REACHED'), findsOneWidget);
      expect(await store.read(), isNot(before));
    },
  );

  testWidgets(
    'no confirmation dialog appears when there is no existing identity to '
    'overwrite',
    (t) async {
      await t.pumpWidget(_harness(InMemoryKeyStore()));
      await t.tap(find.text('Шинээр эхлэх'));
      await t.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('SEED_REACHED'), findsOneWidget);
    },
  );
}
