// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two things that only fail on a real phone, pinned here instead.
//
// A driver ran v0.3.0 beside a commercial meter, switching between the two
// apps on one handset, and ours came back 26% short. Android had throttled
// location delivery the moment Тахь left the screen; nothing in the app
// said so, because a fake GPS in a test has no operating system to be
// throttled by. The fixes still arrive, the meter still draws, and the only
// symptom is a total that is too small.
//
// The same driver reported the display going dark mid-run.
//
// Both fixes are one line each and both are invisible to every other test
// in this repo, which is exactly why they need their own.
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
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';

import '../support/fake_location_source.dart';
import '../support/recording_screen_awake.dart';

class _NoRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async => null;
}

class _FakeDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}

  @override
  Future<Uint8List?> load() async => null;

  @override
  Future<void> clear() async {}
}

const _fix1 = GpsFix(
  lat: 47.9186,
  lon: 106.9176,
  timestampSeconds: 1000,
  accuracyMeters: 5,
);
const _fix2 = GpsFix(
  lat: 47.9286,
  lon: 106.9176,
  timestampSeconds: 1010,
  accuracyMeters: 5,
);

Future<void> _pumpRunningMeter(
  WidgetTester t, {
  required FakeLocationSource location,
  required RecordingScreenAwake screen,
}) async {
  final tariffStore = InMemoryTariffStore();
  await tariffStore.save(const DriverTariff(mntPerKm: 1500));

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        tariffStoreProvider.overrideWithValue(tariffStore),
        meterJournalStoreProvider.overrideWithValue(
          InMemoryMeterJournalStore(),
        ),
        routingClientProvider.overrideWithValue(_NoRoutingClient()),
        locationSourceProvider.overrideWithValue(location),
        locationPermissionCheckProvider.overrideWithValue(() async => true),
        driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
        screenAwakeProvider.overrideWithValue(screen),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const TaximeterPage(),
      ),
    ),
  );
  await t.pumpAndSettle();

  await t.tap(find.text('Эхлүүл'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a running meter asks for location that survives the app '
      'leaving the screen', (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);
    final screen = RecordingScreenAwake();

    await _pumpRunningMeter(t, location: location, screen: screen);

    // Passing a notice is the ONLY thing that makes the stream a foreground
    // service. Drop it and every test in this repo still passes, while the
    // meter loses a quarter of its distance on a real phone.
    expect(location.requestedBackgroundDelivery, isTrue);

    final notice = location.requestedNotices.whereType<Object>().first;
    expect(notice, isNotNull);
  });

  testWidgets('the notice tells the driver the meter is still reading their '
      'position', (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    await _pumpRunningMeter(
      t,
      location: location,
      screen: RecordingScreenAwake(),
    );

    final notice = location.requestedNotices.nonNulls.first;
    // The persistent notification is the only thing a backgrounded driver
    // has telling them their location is being read. An empty one is worse
    // than none: it occupies the slot where the disclosure should be.
    expect(notice.title, isNotEmpty);
    expect(notice.text, isNotEmpty);
    expect(notice.channelName, isNotEmpty);
  });

  testWidgets('the screen is held for the run and given back when it ends', (
    t,
  ) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);
    final screen = RecordingScreenAwake();

    await _pumpRunningMeter(t, location: location, screen: screen);
    expect(screen.isHeld, isTrue, reason: 'a running meter must stay lit');

    location
      ..emit(_fix1)
      ..emit(_fix2);
    await t.pumpAndSettle();

    await t.tap(find.text('Дуусгах'));
    await t.pumpAndSettle();

    // The half everyone forgets. A wakelock that outlives its run is a flat
    // battery, and a driver whose phone dies mid-shift uninstalls rather
    // than reports.
    expect(screen.isHeld, isFalse);
    expect(screen.releaseCount, greaterThan(0));
  });

  testWidgets('leaving a running meter without finishing still gives the '
      'screen back', (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);
    final screen = RecordingScreenAwake();

    await _pumpRunningMeter(t, location: location, screen: screen);
    expect(screen.isHeld, isTrue);

    // Tearing the page down is the untidy exit -- the one a driver takes by
    // backing out mid-run rather than by finishing.
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();

    expect(screen.isHeld, isFalse);
  });
}
