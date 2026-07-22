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
import 'package:takhi/onboarding/onboarding_page.dart' show TakhiMode;
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

/// Home never dials the real network in tests — every scenario below
/// overrides [relayPoolProvider] with a pool wired to [_FakeRelaySocket].
RelayPool _fakeRelayPool() =>
    RelayPool(defaultRelayUrls, connect: (u) => _FakeRelaySocket());

Widget _harness({required KeyStore keyStore, RelayPool? relayPool}) =>
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(keyStore),
        relayPoolProvider.overrideWithValue(relayPool ?? _fakeRelayPool()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const HomePage(),
      ),
    );

void main() {
  testWidgets(
    'shows the passenger/driver mode toggle and switches selection on tap',
    (t) async {
      await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
      await t.pumpAndSettle();

      expect(find.text('Зорчигч'), findsOneWidget);
      expect(find.text('Жолооч'), findsOneWidget);

      final segmented = find.byType(SegmentedButton<TakhiMode>);
      expect(t.widget<SegmentedButton<TakhiMode>>(segmented).selected, {
        TakhiMode.passenger,
      });

      await t.tap(find.text('Жолооч'));
      await t.pumpAndSettle();

      expect(t.widget<SegmentedButton<TakhiMode>>(segmented).selected, {
        TakhiMode.driver,
      });
    },
  );

  testWidgets('shows the npub of the currently stored identity', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();

    await t.pumpWidget(_harness(keyStore: store));
    await t.pumpAndSettle();

    expect(find.text(identity.npub), findsOneWidget);
  });

  testWidgets('shows nothing where the npub goes when there is no identity', (
    t,
  ) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    expect(find.textContaining('npub1'), findsNothing);
  });

  testWidgets(
    'connects relayPoolProvider on reaching home and shows the connected '
    'status once connectAll resolves',
    (t) async {
      final sockets = <String, _FakeRelaySocket>{};
      final pool = RelayPool(
        defaultRelayUrls,
        connect: (u) => sockets[u] = _FakeRelaySocket(),
      );

      await t.pumpWidget(
        _harness(keyStore: InMemoryKeyStore(), relayPool: pool),
      );

      // Immediately after the first frame, connectAll() is still pending.
      expect(find.text('Холбогдож байна…'), findsOneWidget);

      await t.pumpAndSettle();

      expect(pool.connectedUrls, defaultRelayUrls.toSet());
      expect(pool.connectedUrls.length, greaterThanOrEqualTo(3));
      expect(find.textContaining('Холбогдлоо'), findsOneWidget);
    },
  );
}
