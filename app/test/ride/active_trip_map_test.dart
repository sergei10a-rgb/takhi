// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/config/city_config.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/device_location_layer.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// The trip screen's map, in the app, driven by real GPS fixes.
///
/// `trip_tracking_map_test.dart` covers the widget on its own; this file
/// covers the wiring, because the bug that prompted both lived precisely in
/// the wiring. `ActiveTripView` handed a `RideMap` `initialCenter:
/// selfPosition ?? cityCentre` and nothing else -- an expression that reads
/// as "follow me" and is honoured on exactly one frame, the frame before any
/// fix exists. Every screenshot and every widget test of that screen passed,
/// because none of them ever asked whether the mark was inside the picture.
///
/// The staged trip therefore starts where a real one does: two and a half
/// kilometres from the map's opening centre.
const _kAwayFromCentre = GpsFix(
  lat: 47.9411,
  lon: 106.9444,
  timestampSeconds: 1000,
  accuracyMeters: 30,
);

/// A second fix further out again -- the trip moving, which is the state
/// this screen spends nearly all of its life in.
const _kFurtherOut = GpsFix(
  lat: 47.9600,
  lon: 106.9800,
  timestampSeconds: 1300,
);

ll.LatLng _at(GpsFix fix) => ll.LatLng(fix.lat, fix.lon);

/// The camera the trip map is actually showing, read from inside the map's
/// own subtree.
MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(DeviceLocationLayer)));

Future<FakeLocationSource> _pumpTrip(WidgetTester tester) async {
  final store = InMemoryKeyStore();
  await IdentityService(store).createNew();
  final counterparty = generateKeyPair(List<int>.filled(32, 41));
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
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: Scaffold(
          body: ActiveTripView(
            role: TripRole.passenger,
            tripId: 'trip-map-1',
            counterpartyPubHex: counterparty.publicHex,
            agreedPriceMnt: 9000,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return location;
}

/// Feeds one fix and lets the map settle, as `_driveRoute` does for the
/// screenshots.
Future<void> _emit(
  WidgetTester tester,
  FakeLocationSource location,
  GpsFix fix,
) async {
  location.emit(fix);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the trip map shows the rider WHERE THEY ARE, not where the '
      'city centre is', (tester) async {
    final location = await _pumpTrip(tester);

    // Before any fix: no mark at all. An app that has not found you must
    // not draw a dot that says it has.
    expect(find.byType(DeviceLocationLayer), findsNothing);

    await _emit(tester, location, _kAwayFromCentre);

    expect(find.byType(DeviceLocationLayer), findsOneWidget);
    expect(
      _camera(tester).visibleBounds.contains(_at(_kAwayFromCentre)),
      isTrue,
      reason:
          'The mark exists but is off screen -- which is what the rider '
          'reported: "there is no pin showing where I actually am".',
    );
    expect(
      _camera(tester).visibleBounds.contains(
        ll.LatLng(defaultCityConfig.centerLat, defaultCityConfig.centerLon),
      ),
      isFalse,
      reason:
          'Still framing the city centre means the camera never moved and '
          'the assertion above only passed by luck of the zoom.',
    );
  });

  testWidgets('the trip map keeps following as the car moves', (tester) async {
    final location = await _pumpTrip(tester);
    await _emit(tester, location, _kAwayFromCentre);
    await _emit(tester, location, _kFurtherOut);

    expect(
      _camera(tester).visibleBounds.contains(_at(_kFurtherOut)),
      isTrue,
      reason:
          'A trip is twenty minutes long. A camera that frames only the '
          'first fix is a map of where the ride started.',
    );
  });

  testWidgets('the own-position mark on the trip map is the SAME one the '
      'booking maps use', (tester) async {
    final location = await _pumpTrip(tester);
    await _emit(tester, location, _kAwayFromCentre);

    // It used to be a flat gold `Icons.my_location` cross, unique to this
    // screen -- so the one fact a rider orients by had two different shapes
    // depending on which step of the app they were on, and gold meant both
    // "you are here" and "this is the point you are setting".
    expect(find.byIcon(Icons.my_location), findsNothing);
    final layer = tester.widget<DeviceLocationLayer>(
      find.byType(DeviceLocationLayer),
    );
    expect(layer.position, _at(_kAwayFromCentre));
    expect(
      layer.accuracyMeters,
      _kAwayFromCentre.accuracyMeters,
      reason:
          'The ring comes off the same fix as the dot, so the two can '
          'never disagree about how sure the phone is.',
    );
  });
}
