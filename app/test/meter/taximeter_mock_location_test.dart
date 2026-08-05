// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A local, server-less meter cannot re-derive a trip from an independent
// source, so a driver feeding it a "Fake GPS" route is a fraud only the
// device mock flag can catch. `mock_location_test.dart` proves the flag
// reaches the session; this proves the running screen surfaces it to the
// passenger reading over the driver's shoulder — and that a clean run never
// raises the alarm.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/theme/takhi_theme.dart';

import '../support/fake_location_source.dart';

class _OfflineRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => throw Exception('offline');
}

class _FakeDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}
  @override
  Future<Uint8List?> load() async => null;
  @override
  Future<void> clear() async {}
}

const _start = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);

GpsFix _moved(GpsFix from, {required int seconds, bool isMocked = false}) =>
    GpsFix(
      lat: from.lat + 0.001,
      lon: from.lon,
      timestampSeconds: from.timestampSeconds + seconds,
      isMocked: isMocked,
    );

Future<void> _pumpIdleMeter(WidgetTester t, FakeLocationSource location) async {
  final tariffStore = InMemoryTariffStore();
  await tariffStore.save(const DriverTariff(mntPerKm: 1000));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        tariffStoreProvider.overrideWithValue(tariffStore),
        meterJournalStoreProvider.overrideWithValue(
          InMemoryMeterJournalStore(),
        ),
        routingClientProvider.overrideWithValue(_OfflineRoutingClient()),
        locationSourceProvider.overrideWithValue(location),
        locationPermissionCheckProvider.overrideWithValue(() async => true),
        driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
      ],
      child: MaterialApp(
        theme: takhiTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const TaximeterPage(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _feed(WidgetTester t, FakeLocationSource loc, GpsFix fix) async {
  loc.emit(fix);
  await t.pump();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a mocked fix raises the fake-GPS warning on the running '
      'screen', (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);
    await _pumpIdleMeter(t, location);
    await t.tap(find.text('Эхлүүл'));
    await t.pumpAndSettle();

    await _feed(t, location, _start);
    await _feed(t, location, _moved(_start, seconds: 10, isMocked: true));

    expect(
      find.textContaining('Хуурамч GPS'),
      findsOneWidget,
      reason: 'a run that has seen a mocked fix must say so above the fare',
    );
  });

  testWidgets('a clean run never shows the fake-GPS warning', (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);
    await _pumpIdleMeter(t, location);
    await t.tap(find.text('Эхлүүл'));
    await t.pumpAndSettle();

    await _feed(t, location, _start);
    await _feed(t, location, _moved(_start, seconds: 10));
    await _feed(t, location, _moved(_start, seconds: 20));

    expect(find.textContaining('Хуурамч GPS'), findsNothing);
  });
}
