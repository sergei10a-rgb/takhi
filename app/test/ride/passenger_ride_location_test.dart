// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/config/city_config.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/passenger_ride_page.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// Somewhere unmistakably not the configured city centre, so a Plus Code
/// derived from it cannot be confused with the fallback.
const _fix = GpsFix(lat: 47.8721, lon: 106.7503, timestampSeconds: 1000);

const _next = 'Үргэлжлүүл';

/// Opens the ride flow with GPS either available or refused, and returns the
/// fake source so a test can decide when the first fix lands.
Future<FakeLocationSource> _openRideFlow(
  WidgetTester tester, {
  required bool locationGranted,
}) async {
  final store = InMemoryKeyStore();
  await IdentityService(store).createNew();
  final pool = RelayPool(['wss://a'], connect: (_) => FakeRelaySocket());
  final location = FakeLocationSource();
  await pool.connectAll();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(store),
        relayPoolProvider.overrideWithValue(pool),
        locationSourceProvider.overrideWithValue(location),
        locationPermissionCheckProvider.overrideWithValue(
          () async => locationGranted,
        ),
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

/// Walks from the pickup step to the price step, where both picked points
/// are finally stated in a form a test can read.
Future<void> _toPriceStep(WidgetTester tester) async {
  await tester.tap(find.text(_next).first);
  await tester.pump();
  await tester.tap(find.text(_next).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('entering the ride flow puts the pin where the rider actually '
      'is, not on the middle of the city', (tester) async {
    final location = await _openRideFlow(tester, locationGranted: true);

    location.emit(_fix);
    await tester.pumpAndSettle();
    await _toPriceStep(tester);

    // Both ends start at the rider: the pickup because that is where they
    // are, the destination because a map that reopens on the far side of
    // town is a map they have to find their way back across first.
    expect(find.text(plusCodeEncode(_fix.lat, _fix.lon)), findsNWidgets(2));
  });

  testWidgets('a refused permission leaves the manual picker exactly as it '
      'was', (tester) async {
    await _openRideFlow(tester, locationGranted: false);
    await _toPriceStep(tester);

    expect(
      find.text(
        plusCodeEncode(
          defaultCityConfig.centerLat,
          defaultCityConfig.centerLon,
        ),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('a fix that arrives after the rider has already set their '
      'corner does not move it', (tester) async {
    final location = await _openRideFlow(tester, locationGranted: true);

    await tester.drag(find.byType(FlutterMap), const Offset(-150, -100));
    await tester.pumpAndSettle();

    location.emit(_fix);
    await tester.pumpAndSettle();
    await _toPriceStep(tester);

    expect(find.text(plusCodeEncode(_fix.lat, _fix.lon)), findsNothing);
  });
}
