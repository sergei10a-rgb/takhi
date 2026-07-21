// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/main.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/router.dart';

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

/// Every scenario below can end up on [HomePage], which now dials
/// [relayPoolProvider] — override it with a fake-socket pool so no test
/// touches the real network.
RelayPool _fakeRelayPool() =>
    RelayPool(defaultRelayUrls, connect: (u) => _FakeRelaySocket());

void main() {
  testWidgets(
    'redirects straight to /home when a stored identity already exists, '
    'instead of showing onboarding',
    (t) async {
      final store = InMemoryKeyStore();
      await IdentityService(store).createNew();

      await t.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(store),
            relayPoolProvider.overrideWithValue(_fakeRelayPool()),
          ],
          child: const TakhiApp(),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Шинээр эхлэх'), findsNothing); // onboarding is gone
      expect(find.text('Зорчигч'), findsOneWidget); // home's mode toggle
      expect(find.text('Жолооч'), findsOneWidget);
    },
  );

  testWidgets(
    'stays on onboarding — and never overwrites anything — when there is '
    'no stored identity yet',
    (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
            relayPoolProvider.overrideWithValue(_fakeRelayPool()),
          ],
          child: const TakhiApp(),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Шинээр эхлэх'), findsOneWidget);
      expect(find.text('Сэргээх'), findsOneWidget);
    },
  );

  testWidgets('navigating to /seed without a mnemonic extra falls back to '
      'onboarding instead of crashing', (t) async {
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        relayPoolProvider.overrideWithValue(_fakeRelayPool()),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);

    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          routerConfig: router,
        ),
      ),
    );
    await t.pumpAndSettle();

    // No `extra` passed — the real deep-link-style entry this route
    // guards against.
    router.go('/seed');
    await t.pumpAndSettle();

    expect(find.text('Шинээр эхлэх'), findsOneWidget); // back on onboarding
    expect(find.byType(GridView), findsNothing); // not the seed word grid
  });
}
