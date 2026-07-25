// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/main.dart';
import 'package:takhi/map/location_picker.dart';
import 'package:takhi/map/nearby_requests_layer.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';

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

RelayPool _fakeRelayPool() =>
    RelayPool(defaultRelayUrls, connect: (u) => _FakeRelaySocket());

/// Always throws -- forces `TaximeterPage` down its offline path
/// deterministically, mirroring `router_redirect_test.dart`'s own fake.
class _AlwaysFailingRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => throw Exception('offline');
}

/// In-memory `DriverQrStore` so no test touches `path_provider`'s real
/// platform channel.
class _FakeDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}

  @override
  Future<Uint8List?> load() async => null;

  @override
  Future<void> clear() async {}
}

/// Boots the real app straight onto `/home` (a stored identity makes
/// `redirect` skip onboarding, see `router_redirect_test.dart`).
Future<void> _pumpHome(
  WidgetTester t, {
  List<Override> overrides = const [],
}) async {
  final store = InMemoryKeyStore();
  await IdentityService(store).createNew();

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(store),
        relayPoolProvider.overrideWithValue(_fakeRelayPool()),
        ...overrides,
      ],
      child: const TakhiApp(),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets("HomePage's passenger CTA pushes -- so PassengerRidePage gets "
      'a back arrow that returns to home instead of stranding the user '
      'there (a `go` would have replaced the whole stack)', (t) async {
    await _pumpHome(t);

    await t.tap(find.text('Дуудлага өгөх'));
    await t.pumpAndSettle();
    expect(find.byType(LocationPickerField), findsOneWidget);

    expect(find.byType(BackButton), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text('Дуудлага өгөх'), findsOneWidget); // home's CTA again
    expect(find.byType(LocationPickerField), findsNothing);
  });

  testWidgets("HomePage's driver CTA pushes -- DriverInboxPage gets a back "
      'arrow that returns to home', (t) async {
    await _pumpHome(t);

    await t.tap(find.text('Жолооч')); // switch the mode toggle
    await t.pumpAndSettle();
    await t.tap(find.text('Дуудлага сонсох'));
    await t.pumpAndSettle();
    expect(find.byType(NearbyRequestsLayer), findsOneWidget);

    expect(find.byType(BackButton), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text('Дуудлага сонсох'), findsOneWidget);
    expect(find.byType(NearbyRequestsLayer), findsNothing);
  });

  testWidgets("HomePage's meter CTA pushes -- TaximeterPage gets a back "
      'arrow that returns to home instead of trapping the driver in the '
      'meter', (t) async {
    await _pumpHome(
      t,
      overrides: [
        tariffStoreProvider.overrideWithValue(InMemoryTariffStore()),
        meterJournalStoreProvider.overrideWithValue(
          InMemoryMeterJournalStore(),
        ),
        routingClientProvider.overrideWithValue(_AlwaysFailingRoutingClient()),
        locationSourceProvider.overrideWithValue(FakeLocationSource()),
        locationPermissionCheckProvider.overrideWithValue(() async => true),
        driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
      ],
    );

    await t.tap(find.text('Жолооч'));
    await t.pumpAndSettle();
    await t.tap(find.text('Таксиметр'));
    await t.pumpAndSettle();
    expect(find.text('1 км-ийн үнэ (₮)'), findsOneWidget);

    expect(find.byType(BackButton), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text('Таксиметр'), findsOneWidget); // home's meter CTA
    expect(find.text('1 км-ийн үнэ (₮)'), findsNothing);
  });
}
