// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/device_location_layer.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';

import '../support/fake_location_source.dart';

/// The running meter's map, on the same terms as every other map in the app.
///
/// The driven track was drawn here from the beginning; the car was not. The
/// head of a gold polyline is not a "you are here" mark -- it is one end of
/// a shape, in the same colour as the rest of it -- and on the first fix of
/// a run there is no polyline at all, which is precisely the second a driver
/// looks at the screen to check the meter has found them.
const _kFirstFix = GpsFix(
  lat: 47.9186,
  lon: 106.9176,
  timestampSeconds: 1000,
  accuracyMeters: 45,
);

const _kSecondFix = GpsFix(
  lat: 47.9276,
  lon: 106.9176,
  timestampSeconds: 1120,
  accuracyMeters: 25,
);

/// The real store reads a file through `path_provider`, whose platform
/// channel is absent under `flutter_test`.
class _StubDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}

  @override
  Future<Uint8List?> load() async => null;

  @override
  Future<void> clear() async {}
}

Future<FakeLocationSource> _startMeter(WidgetTester tester) async {
  final tariffStore = InMemoryTariffStore();
  await tariffStore.save(const DriverTariff(mntPerKm: 1000));
  final location = FakeLocationSource();
  addTearDown(location.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tariffStoreProvider.overrideWithValue(tariffStore),
        meterJournalStoreProvider.overrideWithValue(
          InMemoryMeterJournalStore(),
        ),
        locationSourceProvider.overrideWithValue(location),
        locationPermissionCheckProvider.overrideWithValue(() async => true),
        driverQrStoreProvider.overrideWithValue(_StubDriverQrStore()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const TaximeterPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Эхлүүл'));
  await tester.pumpAndSettle();
  return location;
}

Future<void> _emit(
  WidgetTester tester,
  FakeLocationSource location,
  GpsFix fix,
) async {
  location.emit(fix);
  await tester.pump();
  await tester.pumpAndSettle();
}

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(DeviceLocationLayer)));

void main() {
  testWidgets('the running meter marks where the car IS, from the very first '
      'fix -- before there is any line to read it off', (tester) async {
    final location = await _startMeter(tester);
    expect(find.byType(DeviceLocationLayer), findsNothing);

    await _emit(tester, location, _kFirstFix);

    final layer = tester.widget<DeviceLocationLayer>(
      find.byType(DeviceLocationLayer),
    );
    expect(layer.position, ll.LatLng(_kFirstFix.lat, _kFirstFix.lon));
    expect(layer.accuracyMeters, _kFirstFix.accuracyMeters);
    expect(
      _camera(tester).visibleBounds.contains(layer.position),
      isTrue,
      reason: 'a mark off the edge of the screen is no mark at all',
    );
  });

  testWidgets('the mark moves to the newest reading, with that reading\'s '
      'own accuracy', (tester) async {
    final location = await _startMeter(tester);
    await _emit(tester, location, _kFirstFix);
    await _emit(tester, location, _kSecondFix);

    final layer = tester.widget<DeviceLocationLayer>(
      find.byType(DeviceLocationLayer),
    );
    expect(layer.position, ll.LatLng(_kSecondFix.lat, _kSecondFix.lon));
    expect(
      layer.accuracyMeters,
      _kSecondFix.accuracyMeters,
      reason:
          'A ring sized by an older fix would claim a certainty this one '
          'never reported.',
    );
  });
}
