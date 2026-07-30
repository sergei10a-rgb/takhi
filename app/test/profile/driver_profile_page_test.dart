// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/profile/driver_profile_page.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi/profile/profile_providers.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

Widget _harness({
  required KeyStore keyStore,
  required RelayPool pool,
  required DriverProfileStore store,
}) => ProviderScope(
  overrides: [
    keyStoreProvider.overrideWithValue(keyStore),
    relayPoolProvider.overrideWithValue(pool),
    driverProfileStoreProvider.overrideWithValue(store),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('mn'),
    home: const DriverProfilePage(),
  ),
);

/// Mirrors `SettingsPage`'s real navigation shape (a button/tile pushes
/// `DriverProfilePage` via `Navigator.push`), so `Navigator.pop()` inside
/// `_save()` has a route to pop back to -- the same reasoning as
/// `driver_qr_capture_page_test.dart`'s `pumpPushed`.
Future<void> _pumpPushed(
  WidgetTester tester, {
  required KeyStore keyStore,
  required RelayPool pool,
  required DriverProfileStore store,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(keyStore),
        relayPoolProvider.overrideWithValue(pool),
        driverProfileStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DriverProfilePage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fills in the form, saves, publishes a kind-0 event and pops', (
    tester,
  ) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final store = InMemoryDriverProfileStore();

    await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

    await tester.enterText(
      find.byKey(const Key('driverProfileNameField')),
      'Бат',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileCarField')),
      'Prius 20',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileColorField')),
      'цагаан',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfilePlateField')),
      '1234УНА',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileKmTariffField')),
      '1500',
    );
    // The last field's `onChanged`-triggered rebuild (which is what
    // flips the save button from disabled to enabled) is only flushed
    // by the *next* pump -- without this, `tap()` below would hit a
    // still-disabled button from the previous frame and silently no-op.
    await tester.pump();
    await tester.tap(find.text('Хадгалах'));
    await tester.pumpAndSettle();

    expect(
      sockets['wss://a']!.sent.any(
        (s) => s.contains('"EVENT"') && s.contains('"kind":0'),
      ),
      isTrue,
    );
    final saved = await store.load();
    expect(saved!.name, 'Бат');
    expect(saved.kmTariffMnt, 1500);
  });

  testWidgets(
    'back is deliberately unguarded: the arrow is there, and unsaved edits '
    'are dropped without a confirmation, publishing nothing',
    (tester) async {
      final keyStore = InMemoryKeyStore();
      await IdentityService(keyStore).createNew();
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final store = InMemoryDriverProfileStore();

      await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

      expect(find.byType(BackButton), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Бат',
      );
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Re-typing a form is the whole cost of leaving here -- no trip, no
      // meter, no published event -- so this page is left poppable.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DriverProfilePage), findsNothing);
      expect(await store.load(), isNull);
      expect(sockets['wss://a']!.sent, isEmpty);
    },
  );

  testWidgets(
    'a waiting tariff typed beside the km-tariff is cached and published with '
    'the rest of the profile (spec §7.4)',
    (tester) async {
      final keyStore = InMemoryKeyStore();
      await IdentityService(keyStore).createNew();
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final store = InMemoryDriverProfileStore();

      await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Бат',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileCarField')),
        'Prius 20',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileColorField')),
        'цагаан',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfilePlateField')),
        '1234УНА',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileKmTariffField')),
        '1500',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileWaitTariffField')),
        '300',
      );
      await tester.pump();
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved!.kmTariffMnt, 1500);
      expect(saved.waitTariffMntPerMinute, 300);
      // The published kind-0 carries it too, otherwise a passenger reading
      // the profile off a relay would see only half this driver's price.
      final profileEvent = NostrEvent.fromJson(
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kind":0'),
                  ),
                )
                as List<dynamic>)[1]
            as Map<String, dynamic>,
      );
      expect(parseDriverProfile(profileEvent).waitTariffMntPerMinute, 300);
    },
  );

  testWidgets(
    'the waiting tariff may be left blank -- the profile still saves, and '
    'waiting simply costs nothing',
    (tester) async {
      final keyStore = InMemoryKeyStore();
      await IdentityService(keyStore).createNew();
      final pool = RelayPool([], connect: (u) => FakeRelaySocket());
      final store = InMemoryDriverProfileStore();

      await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Сараа',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileCarField')),
        'Sonata',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileColorField')),
        'улаан',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfilePlateField')),
        '4321ЭЖӨ',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileKmTariffField')),
        '2200',
      );
      await tester.pump();

      // Untouched waiting field: the save button must not be gated on it.
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved!.kmTariffMnt, 2200);
      expect(saved.waitTariffMntPerMinute, 0);
    },
  );

  testWidgets('pre-fills the form from an existing saved profile', (
    tester,
  ) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();
    await store.save(
      const DriverProfile(
        name: 'Сараа',
        car: 'Sonata',
        color: 'улаан',
        plate: '4321ЭЖӨ',
        kmTariffMnt: 2200,
      ),
    );

    await tester.pumpWidget(
      _harness(keyStore: keyStore, pool: pool, store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('Сараа'), findsOneWidget);
    expect(find.text('Sonata'), findsOneWidget);
    expect(find.text('2200'), findsOneWidget);
  });

  testWidgets('pre-fills the saved waiting tariff too, so editing one rate '
      'never silently clears the other', (tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();
    await store.save(
      const DriverProfile(
        name: 'Дорж',
        car: 'Prius 30',
        color: 'хар',
        plate: '9999БАН',
        kmTariffMnt: 1800,
        waitTariffMntPerMinute: 250,
      ),
    );

    await tester.pumpWidget(
      _harness(keyStore: keyStore, pool: pool, store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('1800'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
  });
}
