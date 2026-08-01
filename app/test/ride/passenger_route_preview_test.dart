// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/trip_route_map.dart';
import 'package:takhi/widgets/address_row.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/passenger_ride_page.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

late final AppLocalizations _l;

const _pickupFix = GpsFix(
  lat: 47.9186,
  lon: 106.9176,
  timestampSeconds: 1000,
  accuracyMeters: 18,
);

/// The point the rider pans the destination map to. Chosen a real distance
/// from the pickup so the figures under the map are worth printing.
const _destinationBend = ll.LatLng(47.9000, 106.8600);

/// The driving time the staged router reports: 12.5 minutes, deliberately
/// not a whole number of minutes, so the rounding the screen does is the
/// thing being checked rather than an identity.
const _routedDurationSeconds = 750.0;

/// The logical screen every design screenshot is taken at -- kept in step
/// with `test/golden/ride_flow_test.dart`'s own constant.
const _kGoldenHandset = Size(390, 844);

/// Answers every route request with a real three-point road.
class _RoutedPathClient implements RoutePathClient {
  @override
  Future<RoutedPath?> routePath({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async => RoutedPath(
    distanceMeters: 7000,
    durationSeconds: _routedDurationSeconds,
    points: [
      ll.LatLng(fromLat, fromLon),
      _destinationBend,
      ll.LatLng(toLat, toLon),
    ],
  );
}

/// A phone with no signal: every attempt to reach the router throws.
class _OfflinePathClient implements RoutePathClient {
  @override
  Future<RoutedPath?> routePath({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async => throw Exception('offline');
}

Future<FakeLocationSource> _openRideFlow(
  WidgetTester tester, {
  required RoutePathClient pathClient,
}) async {
  final store = InMemoryKeyStore();
  await IdentityService(store).createNew();
  final pool = RelayPool(['wss://a'], connect: (_) => FakeRelaySocket());
  final location = FakeLocationSource();
  addTearDown(location.dispose);
  await pool.connectAll();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(store),
        relayPoolProvider.overrideWithValue(pool),
        locationSourceProvider.overrideWithValue(location),
        locationPermissionCheckProvider.overrideWithValue(() async => true),
        routePathClientProvider.overrideWithValue(pathClient),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const PassengerRidePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return location;
}

/// Pickup -> destination -> price, dragging the destination map so the two
/// ends are genuinely different places.
Future<void> _pickBothEnds(WidgetTester tester) async {
  await tester.tap(find.text(_l.nextStep).first);
  await tester.pumpAndSettle();
  await tester.drag(find.byType(FlutterMap), const Offset(-160, 120));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_l.nextStep).first);
  await tester.pumpAndSettle();
}

List<Marker> _markers(WidgetTester tester) => tester
    .widgetList<MarkerLayer>(find.byType(MarkerLayer))
    .expand((layer) => layer.markers)
    .toList();

void main() {
  setUpAll(() async {
    _l = await AppLocalizations.delegate.load(const Locale('mn'));
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the step where the ride is priced finally SHOWS the trip: both '
      'points and the road between them', (tester) async {
    final location = await _openRideFlow(
      tester,
      pathClient: _RoutedPathClient(),
    );
    location.emit(_pickupFix);
    await tester.pumpAndSettle();

    await _pickBothEnds(tester);

    expect(
      find.byType(TripRouteMap),
      findsOneWidget,
      reason:
          'The rider had picked two points and had never seen either of '
          'them on a map.',
    );
    // Two ends, both drawn, at two different places.
    final points = _markers(tester).map((m) => m.point).toSet();
    expect(points.length, greaterThanOrEqualTo(2));

    final lines = tester
        .widgetList<PolylineLayer>(find.byType(PolylineLayer))
        .expand((layer) => layer.polylines);
    expect(lines.single.points, contains(_destinationBend));
  });

  testWidgets('states how long the drive takes, not what it should cost', (
    tester,
  ) async {
    final location = await _openRideFlow(
      tester,
      pathClient: _RoutedPathClient(),
    );
    location.emit(_pickupFix);
    await tester.pumpAndSettle();
    await _pickBothEnds(tester);

    // 750 s rounds up to 13 minutes -- up, because "arrives a minute early"
    // is the error nobody complains about.
    expect(find.text(_l.routePreviewDurationLabel(13)), findsOneWidget);
    // And says whose job pricing is, on the very screen that asks the rider
    // to name one.
    expect(find.text(_l.routePreviewNoQuoteHint), findsOneWidget);
  });

  testWidgets('never prints a ₮ figure of its own on the review step', (
    tester,
  ) async {
    // The regression guard for the whole point of this change. A reference
    // rate lived in `CityConfig` with nothing behind it, was multiplied by
    // the routed distance, and was printed directly above the field where a
    // rider types what they are willing to pay -- which is not information,
    // it is an anchor. Any ₮ amount reappearing on this step has to be a
    // deliberate decision made again, not a default that crept back.
    final location = await _openRideFlow(
      tester,
      pathClient: _RoutedPathClient(),
    );
    location.emit(_pickupFix);
    await tester.pumpAndSettle();
    await _pickBothEnds(tester);

    // An AMOUNT in төгрөг -- digits followed by the mark. Not the bare
    // symbol -- there is no price on this step at all any more
    // («Санал үнэ (₮)»): naming the currency the rider should type in is
    // the opposite of quoting them a number.
    final quotedAmounts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .where((data) => RegExp(r'\d[\s ]*₮').hasMatch(data))
        .toList();
    expect(
      quotedAmounts,
      isEmpty,
      reason:
          'Takhi has no tariff of its own. A ₮ amount here is the app '
          'quoting a fare it invented: $quotedAmounts',
    );
  });

  testWidgets('says out loud that an offline guess is only a guess', (
    tester,
  ) async {
    final location = await _openRideFlow(
      tester,
      pathClient: _OfflinePathClient(),
    );
    location.emit(_pickupFix);
    await tester.pumpAndSettle();
    await _pickBothEnds(tester);

    // The distance is still offered -- a rider naming a price needs to know
    // how far they are going -- but never dressed up as a routed one.
    expect(find.text(_l.estimatedFareApproxLabel), findsOneWidget);
    expect(find.byType(TripRouteMap), findsOneWidget);
    // And no minutes at all: nobody drove the straight line, so nobody
    // timed it.
    expect(
      find.textContaining(RegExp('мин')),
      findsNothing,
      reason:
          'A duration offline could only have been invented from an assumed '
          'speed.',
    );
  });

  testWidgets('a routed answer is NOT labelled approximate', (tester) async {
    final location = await _openRideFlow(
      tester,
      pathClient: _RoutedPathClient(),
    );
    location.emit(_pickupFix);
    await tester.pumpAndSettle();
    await _pickBothEnds(tester);

    expect(find.text(_l.estimatedFareApproxLabel), findsNothing);
  });

  testWidgets('both ends of the trip are on screen without scrolling', (
    tester,
  ) async {
    // The guard for what a screenshot caught and every assertion missed:
    // adding the map pushed the content below the fold. A widget test
    // cannot see a layout, but it can measure one.
    //
    // It used to measure the PRICE FIELD, which was the one thing this
    // step asked for. The passenger no longer names a price, so what has
    // to survive the fold is what the step is now for: the two addresses
    // being confirmed before the request goes out to every driver nearby.
    // A rider who cannot see the destination cannot check it.
    //
    // Measured at the size the design screenshots are taken at
    // (`test/golden/ride_flow_test.dart`), deliberately: that is the frame
    // the layout is judged in, so a check on any other size would pass or
    // fail for reasons nobody is looking at. The worst case is staged --
    // offline, so the extra caveat chip and the "no connection" sentence
    // are both in the column pushing the field down.
    await tester.binding.setSurfaceSize(_kGoldenHandset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final location = await _openRideFlow(
      tester,
      pathClient: _OfflinePathClient(),
    );
    location.emit(_pickupFix);
    await tester.pumpAndSettle();
    await _pickBothEnds(tester);

    // The destination row is the last thing in the scrolling column, so
    // if it fits, everything above it did too.
    final summary = find.byType(AddressRow);
    expect(summary, findsNWidgets(2));
    expect(
      tester.getRect(summary.last).bottom,
      lessThanOrEqualTo(_kGoldenHandset.height),
      reason:
          'the trip being confirmed runs off the bottom -- the rider has to '
          'guess that the step scrolls before they can check where they '
          'are actually going',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('while choosing the destination, the pickup already picked is '
      'visible on the same map', (tester) async {
    final location = await _openRideFlow(
      tester,
      pathClient: _RoutedPathClient(),
    );
    location.emit(_pickupFix);
    await tester.pumpAndSettle();

    await tester.tap(find.text(_l.nextStep).first); // -> destination step
    await tester.pumpAndSettle();

    // Otherwise the rider is asked "where to?" on a map with no "from" on
    // it, and has nothing to judge the distance against.
    final points = _markers(tester).map((m) => m.point);
    expect(points, contains(ll.LatLng(_pickupFix.lat, _pickupFix.lon)));
  });
}
