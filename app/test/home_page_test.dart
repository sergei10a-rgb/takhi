// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi/config/city_config.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/home/home_page.dart';
import 'package:takhi/home/home_status_row.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/ride_map.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/onboarding/onboarding_page.dart' show TakhiMode;
import 'package:takhi/safety/emergency_contact_store.dart';
import 'package:takhi/safety/safety_providers.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/address_row.dart';
import 'package:takhi/widgets/category_tile.dart';
import 'package:takhi/widgets/section_heading.dart';
import 'package:takhi/widgets/takhi_sheet.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import 'support/fake_location_source.dart';
import 'support/fake_relay_socket.dart';

/// Home never dials the real network in tests — every scenario below
/// overrides [relayPoolProvider] with a pool wired to [FakeRelaySocket].
RelayPool _fakeRelayPool() =>
    RelayPool(defaultRelayUrls, connect: (u) => FakeRelaySocket());

/// Stands in for a destination screen. The point of the navigation tests
/// below is *which route home reaches*, not what that route renders, and
/// the real ride/meter pages each need their own stack of provider
/// overrides to build at all — pulling them in here would make these tests
/// fail for reasons that have nothing to do with home.
class _StubPage extends StatelessWidget {
  final String name;

  const _StubPage(this.name);

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(name)));
}

/// What a wedged location service throws on a real device — geolocator
/// surfaces platform failures as exceptions rather than as a `false`.
class _LocationCheckFailure implements Exception {
  const _LocationCheckFailure();
}

/// The accessibility floor the key chip is measured against. Deliberately
/// the *guideline* minimum rather than [TakhiTouch.minTarget], matching
/// `widgets/design_system_test.dart`: if the token is ever lowered, this
/// still fails.
const _kMinTapTarget = 44.0;

const _kPassengerStub = 'стуб-зорчигч';
const _kDriverStub = 'стуб-жолооч';
const _kMeterStub = 'стуб-тоолуур';
const _kSettingsStub = 'стуб-тохиргоо';

Widget _harness({
  required KeyStore keyStore,
  RelayPool? relayPool,
  List<Override> overrides = const [],
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/ride/passenger',
        builder: (context, state) => const _StubPage(_kPassengerStub),
      ),
      GoRoute(
        path: '/ride/driver',
        builder: (context, state) => const _StubPage(_kDriverStub),
      ),
      GoRoute(
        path: '/meter',
        builder: (context, state) => const _StubPage(_kMeterStub),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const _StubPage(_kSettingsStub),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      keyStoreProvider.overrideWithValue(keyStore),
      relayPoolProvider.overrideWithValue(relayPool ?? _fakeRelayPool()),
      emergencyContactStoreProvider.overrideWithValue(
        InMemoryEmergencyContactStore(),
      ),
      ...overrides,
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('mn'),
      routerConfig: router,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
    ),
  );
}

/// Every string the clipboard is handed while the returned list is alive.
///
/// Without a handler installed, `Clipboard.setData` reaches an absent
/// platform channel; with one, the test can also assert *what* was copied,
/// which is the whole promise of an abbreviated key chip.
List<String> _captureClipboard(WidgetTester t) {
  final copied = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('lays the map out full-bleed under floating brand and city '
      'markers', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    expect(find.byType(RideMap), findsOneWidget);

    // The map is the screen, not a panel on it: it fills the whole
    // Scaffold body rather than a fixed-height box like the ride pages'
    // pickers do.
    final mapSize = t.getSize(find.byType(RideMap));
    expect(mapSize, t.getSize(find.byType(Scaffold)));

    expect(find.text('Тахь'), findsOneWidget);
    expect(find.text(defaultCityConfig.name), findsOneWidget);
  });

  testWidgets('offers exactly four service tiles, one per thing the app '
      'does', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    expect(find.byType(CategoryTile), findsNWidgets(4));
    expect(find.text('Унаа дуудах'), findsOneWidget);
    expect(find.text('Жолоочоор'), findsOneWidget);
    expect(find.text('Таксиметр'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
  });

  testWidgets('drops the passenger/driver mode toggle — the tiles are the '
      'way in, so no destination is one mode-switch away from being '
      'invisible', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    expect(find.byType(SegmentedButton<TakhiMode>), findsNothing);
    // The meter used to be driver-mode-only; from a cold start it is now
    // one tap away, exactly like every other service.
    expect(find.text('Таксиметр'), findsOneWidget);
  });

  testWidgets('the destination row opens the passenger flow', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    expect(find.text('Очих газар'), findsOneWidget);

    await t.tap(find.text('Хаашаа явах вэ?'));
    await t.pumpAndSettle();

    expect(find.text(_kPassengerStub), findsOneWidget);
  });

  testWidgets('asks where the rider is going exactly once -- the display-size '
      'headline that used to sit above the destination row said the same '
      'thing the row itself says', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    // No heading block at the top of the sheet at all: the two address
    // rows are the sheet's opening move, the way the reference apps do it.
    expect(find.byType(SectionHeading), findsNothing);
    expect(
      find.text('Суух цэгээ шалгаад очих газраа оруулна уу'),
      findsNothing,
    );

    // The question survives, once, where the answer is typed.
    expect(find.text('Хаашаа явах вэ?'), findsOneWidget);
    final prompt = t.widget<Text>(find.text('Хаашаа явах вэ?'));
    expect(prompt.style?.fontSize, TakhiType.title.fontSize);
  });

  testWidgets('the pickup and destination rows are one block, tied together '
      'by the rail between their markers', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    final rows = find.byType(AddressRow);
    expect(rows, findsNWidgets(2));

    // Same left edge and same marker axis: two rows in one block, not two
    // unrelated controls that happen to be stacked.
    expect(t.getTopLeft(rows.first).dx, t.getTopLeft(rows.last).dx);
    expect(t.getSize(rows.first).width, t.getSize(rows.last).width);
  });

  testWidgets('once located, the pickup row leads with a name a person can '
      'read and keeps the Plus Code beneath it', (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    await t.pumpWidget(
      _harness(
        keyStore: InMemoryKeyStore(),
        overrides: [
          locationSourceProvider.overrideWithValue(location),
          locationPermissionCheckProvider.overrideWithValue(() async => true),
        ],
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Байршлаа тогтоох'));
    await t.pumpAndSettle();

    const fix = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);
    location.emit(fix);
    await t.pump();
    await t.pump();

    final code = plusCodeEncode(fix.lat, fix.lon);
    expect(find.text('Одоогийн байршил'), findsOneWidget);
    // The code is kept -- SOS and trip sharing transmit exactly this string
    // -- but it is the fine print, not the address.
    expect(find.text(code), findsOneWidget);

    final name = t.widget<Text>(find.text('Одоогийн байршил'));
    final detail = t.widget<Text>(find.text(code));
    expect(name.style?.color, TakhiSurfaces.light.onSheet);
    expect(detail.style?.color, TakhiSurfaces.light.muted);
    expect(name.style!.fontSize!, greaterThan(detail.style!.fontSize!));
  });

  testWidgets('a pickup point the rider has named leads with that name and '
      'demotes the Plus Code to the line beneath it', (t) async {
    // The tier above "Одоогийн байршил": a landmark the rider typed for
    // themselves. `LocationPickerField` is where that text comes from, and
    // no geocoding service is consulted for any of it (spec §6).
    const code = '8PV8WW99+C2X';
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AddressRow(
            icon: Icons.trip_origin,
            label: 'Суух хаяг',
            value: 'Централ Парк',
            detail: code,
          ),
        ),
      ),
    );

    final name = t.widget<Text>(find.text('Централ Парк'));
    final detail = t.widget<Text>(find.text(code));
    expect(name.style?.color, TakhiSurfaces.light.onSheet);
    expect(detail.style?.color, TakhiSurfaces.light.muted);
    expect(name.style!.fontSize!, greaterThan(detail.style!.fontSize!));
  });

  testWidgets('the «Унаа дуудах» tile opens the passenger flow', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    await t.tap(find.text('Унаа дуудах'));
    await t.pumpAndSettle();

    expect(find.text(_kPassengerStub), findsOneWidget);
  });

  testWidgets('the «Жолоочоор» tile opens the driver inbox', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    await t.tap(find.text('Жолоочоор'));
    await t.pumpAndSettle();

    expect(find.text(_kDriverStub), findsOneWidget);
  });

  testWidgets('the «Таксиметр» tile opens the meter', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    await t.tap(find.text('Таксиметр'));
    await t.pumpAndSettle();

    expect(find.text(_kMeterStub), findsOneWidget);
  });

  testWidgets('the settings control opens settings', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.settings));
    await t.pumpAndSettle();

    expect(find.text(_kSettingsStub), findsOneWidget);
  });

  testWidgets('the SOS tile opens the emergency actions in place, without '
      'navigating away from the map', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    await t.tap(find.text('SOS'));
    await t.pumpAndSettle();

    expect(find.text('102 — цагдаа'), findsOneWidget);
    expect(find.text('103 — түргэн тусламж'), findsOneWidget);
    // Still home underneath: an emergency must never cost a screen
    // transition.
    expect(find.byType(RideMap), findsOneWidget);
  });

  testWidgets('the pickup row starts honest about not knowing where the '
      'rider is', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    expect(find.text('Суух хаяг'), findsOneWidget);
    expect(find.text('Байршил тогтоогоогүй'), findsOneWidget);
  });

  testWidgets('locating adopts the first GPS fix as the pickup point', (
    t,
  ) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    await t.pumpWidget(
      _harness(
        keyStore: InMemoryKeyStore(),
        overrides: [
          locationSourceProvider.overrideWithValue(location),
          locationPermissionCheckProvider.overrideWithValue(() async => true),
        ],
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Байршлаа тогтоох'));
    await t.pumpAndSettle();

    const fix = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);
    location.emit(fix);
    await t.pump();
    await t.pump();

    expect(find.text(plusCodeEncode(fix.lat, fix.lon)), findsOneWidget);
    expect(find.text('Байршил тогтоогоогүй'), findsNothing);
  });

  testWidgets('a refused location permission is stated on the pickup row '
      'instead of leaving the rider tapping a dead button', (t) async {
    await t.pumpWidget(
      _harness(
        keyStore: InMemoryKeyStore(),
        overrides: [
          locationSourceProvider.overrideWithValue(FakeLocationSource()),
          locationPermissionCheckProvider.overrideWithValue(() async => false),
        ],
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Байршлаа тогтоох'));
    await t.pumpAndSettle();

    expect(find.text('Байршлын зөвшөөрөл өгөөгүй байна'), findsOneWidget);
  });

  testWidgets('a permission check that throws is treated as a refusal, not '
      'as an unhandled error on the home screen', (t) async {
    await t.pumpWidget(
      _harness(
        keyStore: InMemoryKeyStore(),
        overrides: [
          locationSourceProvider.overrideWithValue(FakeLocationSource()),
          locationPermissionCheckProvider.overrideWithValue(
            () async => throw const _LocationCheckFailure(),
          ),
        ],
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Байршлаа тогтоох'));
    await t.pumpAndSettle();

    expect(find.text('Байршлын зөвшөөрөл өгөөгүй байна'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('locating without any GPS stub leaves home standing — which '
      'is what lets the rest of the suite reach home without mocking the '
      'location plugin at all', (t) async {
    // No location overrides: `ensureLocationPermission` runs for real
    // against a plugin channel that is absent under `flutter_test`, so its
    // reply never arrives. Home must simply carry on saying it does not
    // know where the rider is.
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Байршлаа тогтоох'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.text('Байршил тогтоогоогүй'), findsOneWidget);
    expect(find.byType(RideMap), findsOneWidget);
  });

  testWidgets(
    'connects relayPoolProvider on reaching home and shows the connected '
    'status once connectAll resolves',
    (t) async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool(
        defaultRelayUrls,
        connect: (u) => sockets[u] = FakeRelaySocket(),
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

  testWidgets('abbreviates the stored npub instead of printing all 63 '
      'characters, and copies the whole thing on tap', (t) async {
    final copied = _captureClipboard(t);
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();

    await t.pumpWidget(_harness(keyStore: store));
    await t.pumpAndSettle();

    expect(find.text(identity.npub), findsNothing);
    expect(find.text(shortenNpub(identity.npub)), findsOneWidget);

    await t.tap(find.text(shortenNpub(identity.npub)));
    await t.pumpAndSettle();

    expect(copied, [identity.npub]);
    expect(find.text('Нийтийн түлхүүр хуулагдлаа'), findsOneWidget);
  });

  testWidgets('the key chip clears the touch floor -- it is the one control '
      'on home that is not a shared component, so nothing else measures '
      'it', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();

    await t.pumpWidget(_harness(keyStore: store));
    await t.pumpAndSettle();

    // The gesture area, not the painted pill: `InfoChip` is a label with
    // chip-sized padding, and the whole point of the wrapper in
    // `home_status_row.dart` is that the target is bigger than the artwork.
    final target = find.ancestor(
      of: find.text(shortenNpub(identity.npub)),
      matching: find.byType(InkWell),
    );
    expect(target, findsOneWidget);
    expect(t.getSize(target).height, greaterThanOrEqualTo(_kMinTapTarget));
  });

  testWidgets('shows no key chip at all when there is no identity', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    expect(find.textContaining('npub1'), findsNothing);
  });

  testWidgets('the sheet swallows the gestures that land on it instead of '
      'letting them pan the map underneath', (t) async {
    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    // A painted surface is transparent to hit-testing in Flutter, so
    // without an opaque barrier a swipe across the sheet would reach the
    // map behind it and drag the city out from under the rider's thumb.
    final hits = t.hitTestOnBinding(t.getCenter(find.byType(TakhiSheet)));
    final map = t.renderObject(find.byType(RideMap));
    final reachedMap = hits.path.any((entry) {
      final target = entry.target;
      if (target is! RenderObject) return false;
      for (RenderObject? node = target; node != null; node = node.parent) {
        if (identical(node, map)) return true;
      }
      return false;
    });

    expect(reachedMap, isFalse);
  });

  testWidgets('fits the narrowest phone this app targets without '
      'overflowing', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore()));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.byType(CategoryTile), findsNWidgets(4));
  });

  testWidgets('scrolls the sheet contents rather than growing past the top '
      'of the screen at a doubled text scale', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_harness(keyStore: InMemoryKeyStore(), textScale: 2));
    await t.pumpAndSettle();

    // No RenderFlex overflow, and the map is still the ground the sheet
    // sits on rather than something the sheet has pushed off screen.
    expect(t.takeException(), isNull);
    expect(find.byType(RideMap), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  group('shortenNpub', () {
    test('keeps the head and the tail, elides the unreadable middle', () {
      const npub =
          'npub1abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvw';
      final short = shortenNpub(npub);

      expect(short.length, lessThan(npub.length));
      expect(short, startsWith('npub1abcde'));
      expect(short, endsWith('rstuvw'));
      expect(short, contains('…'));
    });

    test('leaves a key too short to elide exactly as it is', () {
      expect(shortenNpub('npub1abc'), 'npub1abc');
    });
  });
}
