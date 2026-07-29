// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/main.dart';
import 'package:takhi/map/location_picker.dart';
import 'package:takhi/map/nearby_requests_layer.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/call/phone_share_settings_page.dart';
import 'package:takhi/legal/legal_notice_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/profile/driver_profile_page.dart';
import 'package:takhi/router.dart';
import 'package:takhi/settings/settings_page.dart';

import 'support/fake_location_source.dart';

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

/// Always throws -- forces `TaximeterPage` down its offline path
/// deterministically, mirroring `taximeter_page_test.dart`'s own fake.
class _AlwaysFailingRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => throw Exception('offline');
}

/// In-memory `DriverQrStore` test double so `TaximeterPage`'s `finished`
/// step never hits `path_provider`'s real platform channel under
/// `flutter_test`, mirroring `taximeter_page_test.dart`'s own fake.
class _FakeDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}

  @override
  Future<Uint8List?> load() async => null;

  @override
  Future<void> clear() async {}
}

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
      expect(find.text('Унаа дуудах'), findsOneWidget); // home's service row
      expect(find.text('Жолоочоор'), findsOneWidget);
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

  testWidgets('reaching /ride/passenger with no stored identity renders the '
      'passenger flow instead of crashing or redirecting away', (t) async {
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

    router.go('/ride/passenger');
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.byType(LocationPickerField), findsOneWidget);
    expect(find.byType(NearbyRequestsLayer), findsNothing);
  });

  testWidgets(
    'reaching /ride/driver with no stored identity renders the driver '
    'flow instead of crashing or redirecting away',
    (t) async {
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

      router.go('/ride/driver');
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.byType(NearbyRequestsLayer), findsOneWidget);
      expect(find.byType(LocationPickerField), findsNothing);
    },
  );

  testWidgets("HomePage's passenger tile navigates to /ride/passenger", (
    t,
  ) async {
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

    // Redirected straight to /home (see the first test above), where every
    // service is on screen at once.
    expect(find.text('Унаа дуудах'), findsOneWidget);

    await t.tap(find.text('Унаа дуудах'));
    await t.pumpAndSettle();

    expect(find.byType(LocationPickerField), findsOneWidget);
    expect(find.byType(NearbyRequestsLayer), findsNothing);
  });

  testWidgets("HomePage's driver tile navigates to /ride/driver", (t) async {
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

    expect(find.text('Жолоочоор'), findsOneWidget);
    await t.tap(find.text('Жолоочоор'));
    await t.pumpAndSettle();

    expect(find.byType(NearbyRequestsLayer), findsOneWidget);
    expect(find.byType(LocationPickerField), findsNothing);
  });

  testWidgets(
    "HomePage's meter tile navigates to /meter from a cold start -- it used "
    'to be hidden behind a passenger/driver toggle, so a driver who never '
    'found the toggle never found the meter either -- and it actually '
    'reaches TaximeterPage, not just some route that happens not to crash',
    (t) async {
      final store = InMemoryKeyStore();
      await IdentityService(store).createNew();

      await t.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(store),
            relayPoolProvider.overrideWithValue(_fakeRelayPool()),
            tariffStoreProvider.overrideWithValue(InMemoryTariffStore()),
            meterJournalStoreProvider.overrideWithValue(
              InMemoryMeterJournalStore(),
            ),
            routingClientProvider.overrideWithValue(
              _AlwaysFailingRoutingClient(),
            ),
            locationSourceProvider.overrideWithValue(FakeLocationSource()),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
          ],
          child: const TakhiApp(),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Таксиметр'), findsOneWidget);
      await t.tap(find.text('Таксиметр'));
      await t.pumpAndSettle();

      // Reached the real `TaximeterPage`, not merely "no exception" --
      // this is its tariff-entry step, unreachable from anywhere else in
      // the app.
      expect(t.takeException(), isNull);
      expect(find.text('1 км-ийн үнэ (₮)'), findsOneWidget);
    },
  );

  testWidgets(
    "HomePage's settings entry point navigates to /settings, actually "
    'reaching SettingsPage (Plan 5 review CRITICAL-2 fix -- previously '
    'there was no way to reach any settings screen at all); from there, '
    'the phone-share tile reaches PhoneShareSettingsPage',
    (t) async {
      SharedPreferences.setMockInitialValues({});
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

      await t.tap(find.byIcon(Icons.settings));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.byType(SettingsPage), findsOneWidget);

      await t.tap(find.text('Утасны дугаар'));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.byType(PhoneShareSettingsPage), findsOneWidget);
    },
  );

  testWidgets("SettingsPage's driver-profile tile navigates to "
      '/settings/driver-profile, actually reaching DriverProfilePage', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
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

    await t.tap(find.byIcon(Icons.settings));
    await t.pumpAndSettle();
    await t.tap(find.text('Жолоочийн профайл'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.byType(DriverProfilePage), findsOneWidget);
  });

  testWidgets("SettingsPage's legal-notice tile navigates to /settings/legal, "
      'actually reaching LegalNoticePage (spec §4)', (t) async {
    SharedPreferences.setMockInitialValues({});
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

    await t.tap(find.byIcon(Icons.settings));
    await t.pumpAndSettle();
    await t.tap(find.text('Хууль зүйн сануулга'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.byType(LegalNoticePage), findsOneWidget);
  });
}
