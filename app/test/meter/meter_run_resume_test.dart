// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A fare must survive the app dying.
//
// A taximeter that loses its run halfway leaves the driver with no record,
// no way to reconstruct the distance, and a passenger waiting for a number.
// There is no remedy for that after the fact, which is why the snapshot is
// written as the run goes rather than at the end of it.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/meter_run_snapshot.dart';
import 'package:takhi/meter/meter_run_store.dart';
import 'package:takhi/meter/meter_session.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
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

const _interrupted = MeterRunSnapshot(
  mntPerKm: 1500,
  waitTariffMntPerMinute: 150,
  durationTariffMntPerMinute: 150,
  startedAtSeconds: 1000,
  distanceMeters: 4200,
  waitingSeconds: 120,
  billableDurationSeconds: 900,
  pausedSeconds: 0,
  isPaused: false,
  lastFixSeconds: 1900,
);

void main() {
  group('MeterRunSnapshot', () {
    test('survives a round trip through storage', () {
      final decoded = MeterRunSnapshot.decode(_interrupted.encode())!;

      expect(decoded.mntPerKm, 1500);
      expect(decoded.distanceMeters, 4200);
      expect(decoded.waitingSeconds, 120);
      expect(decoded.billableDurationSeconds, 900);
      expect(decoded.startedAtSeconds, 1000);
      expect(decoded.lastFixSeconds, 1900);
    });

    test('refuses garbage instead of throwing at app start', () {
      // Read on launch. A parse error that propagated would turn one corrupt
      // preference into a phone that cannot open its own taximeter.
      expect(MeterRunSnapshot.decode('not json'), isNull);
      expect(MeterRunSnapshot.decode('[]'), isNull);
      expect(MeterRunSnapshot.decode('{"mntPerKm":"lots"}'), isNull);
    });

    test('a missing field reads as zero rather than as an error', () {
      final partial = MeterRunSnapshot.decode(
        '{"mntPerKm":1500,"startedAt":1000}',
      )!;
      expect(partial.distanceMeters, 0);
      expect(partial.isPaused, isFalse);
    });
  });

  group('isResumable', () {
    test('a run from minutes ago comes back', () {
      expect(isResumable(_interrupted, 1900 + 300), isTrue);
    });

    test('a run from before the last shift does not', () {
      // Resuming this would put a stranger's kilometres on the next
      // passenger's bill.
      expect(isResumable(_interrupted, 1900 + kMaxResumeAgeSeconds + 1),
          isFalse);
    });

    test('a clock that stepped backwards is not treated as a stale run', () {
      expect(isResumable(_interrupted, 500), isTrue);
    });
  });

  group('MeterSession.resumed', () {
    test('carries the totals back and bills nothing for the gap', () {
      final session = MeterSession.resumed(_interrupted);

      expect(session.distanceMeters, 4200);
      expect(session.waitingSeconds, 120);
      expect(session.billableDurationSeconds, 900);
      expect(session.mntPerKm, 1500);
      // Nothing measured the stretch driven while the app was gone, and
      // inventing it would be inventing money.
      expect(session.fixes, isEmpty);
      expect(session.durationSeconds, 0);
    });

    test('keeps counting from where it left off', () {
      final session = MeterSession.resumed(_interrupted);
      const a = GpsFix(
        lat: 47.9186,
        lon: 106.9176,
        timestampSeconds: 2000,
        accuracyMeters: 5,
      );
      // 60 seconds apart, not 10: ~1112m in 10s implies 400 km/h, which
      // `classifyMovement` rightly throws out as a bad fix rather than a
      // fast car.
      const b = GpsFix(
        lat: 47.9286,
        lon: 106.9176,
        timestampSeconds: 2060,
        accuracyMeters: 5,
      );
      session
        ..addFix(a)
        ..addFix(b);

      // ~1112m added to the 4200m it came back with.
      expect(session.distanceMeters, greaterThan(5200));
      expect(session.distanceMeters, lessThan(5400));
    });

    test('a paused run comes back paused', () {
      final session = MeterSession.resumed(
        const MeterRunSnapshot(
          mntPerKm: 1500,
          waitTariffMntPerMinute: 0,
          durationTariffMntPerMinute: 0,
          startedAtSeconds: 1000,
          distanceMeters: 100,
          waitingSeconds: 0,
          billableDurationSeconds: 0,
          pausedSeconds: 60,
          isPaused: true,
          lastFixSeconds: 1100,
        ),
      );
      // Coming back un-paused would silently restart a meter the driver
      // deliberately stopped, and bill for a fuel stop.
      expect(session.isPaused, isTrue);
      expect(session.pausedSeconds, 60);
    });
  });

  group('the taximeter page', () {
    Future<void> pump(
      WidgetTester t, {
      required MeterRunStore runStore,
      required FakeLocationSource location,
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
            meterRunStoreProvider.overrideWithValue(runStore),
            routingClientProvider.overrideWithValue(_NoRoutingClient()),
            locationSourceProvider.overrideWithValue(location),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
            screenAwakeProvider.overrideWithValue(RecordingScreenAwake()),
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
    }

    testWidgets('opens straight into a run the app died in the middle of', (
      t,
    ) async {
      final location = FakeLocationSource();
      addTearDown(location.dispose);
      final runStore = InMemoryMeterRunStore();
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await runStore.save(
        MeterRunSnapshot(
          mntPerKm: 1500,
          waitTariffMntPerMinute: 0,
          durationTariffMntPerMinute: 0,
          startedAtSeconds: nowSeconds - 600,
          distanceMeters: 4200,
          waitingSeconds: 0,
          billableDurationSeconds: 600,
          pausedSeconds: 0,
          isPaused: false,
          lastFixSeconds: nowSeconds - 30,
        ),
      );

      await pump(t, runStore: runStore, location: location);

      // Straight to the running step, carrying the fare it had reached:
      // 4.2km at 1500₮/km.
      // Asserted on the figure rather than the whole label: both the
      // thousands separator and the gap before ₮ are non-breaking spaces,
      // and a test that re-types the label's punctuation breaks on a
      // wording change that costs the driver nothing.
      expect(find.textContaining('6 300'), findsOneWidget);
      expect(find.text('Дуусгах'), findsOneWidget);
      // And it says why, including the half that costs the driver.
      expect(find.textContaining('сэргээгдлээ'), findsOneWidget);
      // A restored run must re-arm the foreground service, or the rest of
      // the trip under-measures exactly like the part that was lost.
      expect(location.requestedBackgroundDelivery, isTrue);
    });

    testWidgets('a run from days ago is discarded, not resumed', (t) async {
      final location = FakeLocationSource();
      addTearDown(location.dispose);
      final runStore = InMemoryMeterRunStore();
      await runStore.save(_interrupted); // lastFix at unix second 1900

      await pump(t, runStore: runStore, location: location);

      expect(find.text('Эхлүүл'), findsOneWidget);
      expect(await runStore.load(), isNull);
    });

    testWidgets('finishing clears the snapshot so it cannot come back', (
      t,
    ) async {
      final location = FakeLocationSource();
      addTearDown(location.dispose);
      final runStore = InMemoryMeterRunStore();

      await pump(t, runStore: runStore, location: location);
      await t.tap(find.text('Эхлүүл'));
      await t.pumpAndSettle();

      // Started runs are written down immediately, not only once a fix
      // lands -- a crash in the first five seconds still loses a run
      // otherwise, and the driver has no idea one was ever started.
      expect(await runStore.load(), isNotNull);

      await t.tap(find.text('Дуусгах'));
      await t.pumpAndSettle();

      expect(await runStore.load(), isNull);
    });
  });
}
