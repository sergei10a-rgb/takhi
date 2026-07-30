// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_track.dart';
import 'package:takhi/geo/location_source.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';

/// Always throws -- keeps the routed-fare path deterministic and offline,
/// mirroring `taximeter_page_test.dart`'s own fake. None of these
/// scenarios picks a destination; the override only guarantees the real
/// HTTP client is never reachable.
class _AlwaysFailingRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => throw Exception('offline');
}

/// A [LocationSource] whose subscriptions are observable: every `watch()`
/// hands out its own single-subscription controller, so
/// [hasActiveSubscription] answers the question these tests actually care
/// about -- did leaving a running meter release the GPS stream, or is the
/// radio still feeding a page nobody can see any more.
class _TrackedLocationSource implements LocationSource {
  final _controllers = <StreamController<GpsFix>>[];
  int cancelCount = 0;

  @override
  Stream<GpsFix> watch({Duration interval = const Duration(seconds: 5)}) {
    late final StreamController<GpsFix> controller;
    controller = StreamController<GpsFix>(
      onCancel: () {
        cancelCount++;
        _controllers.remove(controller);
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }

  bool get hasActiveSubscription => _controllers.isNotEmpty;

  void emit(GpsFix fix) {
    // Copied first: delivering a fix can complete a `.first` subscription,
    // which removes its controller from the list mid-iteration.
    for (final controller in List.of(_controllers)) {
      controller.add(fix);
    }
  }
}

/// In-memory `DriverQrStore` -- the finished step renders
/// `DriverQrDisplay`, which would otherwise hit `path_provider`'s real
/// platform channel and throw under `flutter_test`.
class _FakeDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}

  @override
  Future<Uint8List?> load() async => null;

  @override
  Future<void> clear() async {}
}

const _fix1 = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);
const _fix2 = GpsFix(lat: 47.9196, lon: 106.9176, timestampSeconds: 1010);
const _fix3 = GpsFix(lat: 47.9206, lon: 106.9176, timestampSeconds: 1020);

/// Pushes `TaximeterPage` on top of a plain first route, exactly as
/// `router.dart`'s meter CTA does. Only a pushed route gets the `AppBar`'s
/// automatic back arrow -- and that arrow, Android's hardware back and the
/// iOS back swipe all funnel through the same `Navigator.maybePop` the
/// page's pop guards intercept.
Future<void> _pumpPushedMeter(
  WidgetTester t, {
  required TariffStore tariffStore,
  required MeterJournalStore journalStore,
  required LocationSource location,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        tariffStoreProvider.overrideWithValue(tariffStore),
        meterJournalStoreProvider.overrideWithValue(journalStore),
        routingClientProvider.overrideWithValue(_AlwaysFailingRoutingClient()),
        locationSourceProvider.overrideWithValue(location),
        locationPermissionCheckProvider.overrideWithValue(() async => true),
        driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TaximeterPage(),
                  ),
                ),
                child: const Text('нүүр'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await t.tap(find.text('нүүр'));
  await t.pumpAndSettle();
  expect(find.text('Таксиметр'), findsOneWidget); // the page's AppBar title
}

/// Drives a freshly pushed meter from the idle step into a running one
/// carrying three fixes' worth of distance, and returns the fare then on
/// screen -- the number the driver stands to lose to a stray back press.
Future<int> _runMeterWithThreeFixes(
  WidgetTester t,
  _TrackedLocationSource location, {
  required int mntPerKm,
}) async {
  await t.tap(find.text('Эхлүүл'));
  await t.pumpAndSettle();

  for (final fix in [_fix1, _fix2, _fix3]) {
    location.emit(fix);
    // Two pumps: `RideMap`'s polyline layer needs an extra frame to settle
    // on some transitions (see `taximeter_page_test.dart`).
    await t.pump();
    await t.pump();
  }

  final fare = computeFareMnt(
    mntPerKm: mntPerKm,
    distanceMeters: trackDistanceMeters([_fix1, _fix2, _fix3]),
  );
  expect(find.text('${groupedMnt(fare)}\u00A0₮'), findsOneWidget);
  return fare;
}

void main() {
  testWidgets(
    'backing out of a running meter asks first -- and choosing «Үлдэх» '
    'leaves the run untouched, still ticking up with new fixes',
    (t) async {
      final tariffStore = InMemoryTariffStore();
      await tariffStore.save(DriverTariff(mntPerKm: 1000));
      final journalStore = InMemoryMeterJournalStore();
      final location = _TrackedLocationSource();

      await _pumpPushedMeter(
        t,
        tariffStore: tariffStore,
        journalStore: journalStore,
        location: location,
      );
      final fare = await _runMeterWithThreeFixes(t, location, mntPerKm: 1000);

      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();

      // The pop was intercepted: the meter is still on screen behind the
      // dialog, still holding the fare it had.
      expect(find.text('Тоолуурыг зогсоох уу?'), findsOneWidget);
      expect(find.text('${groupedMnt(fare)}\u00A0₮'), findsOneWidget);

      await t.tap(find.text('Үлдэх'));
      await t.pumpAndSettle();

      expect(find.text('Тоолуурыг зогсоох уу?'), findsNothing);

      // Still the *same* run, not a restarted one: a further fix keeps
      // adding to the fare it already had, which only holds if the GPS
      // subscription survived the near-miss.
      const fix4 = GpsFix(lat: 47.9216, lon: 106.9176, timestampSeconds: 1030);
      location.emit(fix4);
      await t.pump();
      await t.pump();

      final grownFare = computeFareMnt(
        mntPerKm: 1000,
        distanceMeters: trackDistanceMeters([_fix1, _fix2, _fix3, fix4]),
      );
      expect(grownFare, greaterThan(fare));
      expect(find.text('${groupedMnt(grownFare)}\u00A0₮'), findsOneWidget);
      expect(location.hasActiveSubscription, isTrue);
      expect(await journalStore.loadAll(), isEmpty);
    },
  );

  testWidgets(
    'choosing «Гарах» on a running meter leaves the page and releases the '
    'GPS subscription instead of tracking on behind an invisible screen',
    (t) async {
      final tariffStore = InMemoryTariffStore();
      await tariffStore.save(DriverTariff(mntPerKm: 1000));
      final journalStore = InMemoryMeterJournalStore();
      final location = _TrackedLocationSource();

      await _pumpPushedMeter(
        t,
        tariffStore: tariffStore,
        journalStore: journalStore,
        location: location,
      );
      await _runMeterWithThreeFixes(t, location, mntPerKm: 1000);
      expect(location.hasActiveSubscription, isTrue);

      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await t.tap(find.text('Гарах'));
      await t.pumpAndSettle();

      // Back on the first route, meter gone.
      expect(find.text('Таксиметр'), findsNothing);
      expect(find.text('нүүр'), findsOneWidget);

      // The GPS stream and the fare tick timer are both released -- an
      // abandoned run must not keep the radio (and the battery) busy.
      expect(location.hasActiveSubscription, isFalse);
      expect(location.cancelCount, 1);

      // Nothing written: the dialog promised this run is discarded and
      // pointed at "Дуусгах" as the way to record one, so a half-run must
      // not appear in the day's takings either.
      expect(await journalStore.loadAll(), isEmpty);
    },
  );

  testWidgets(
    'a driver who mistyped the tariff can reopen it from the idle step and '
    'back out of the edit to idle -- not out of the meter entirely',
    (t) async {
      final tariffStore = InMemoryTariffStore();
      await tariffStore.save(DriverTariff(mntPerKm: 1500));
      final location = _TrackedLocationSource();

      await _pumpPushedMeter(
        t,
        tariffStore: tariffStore,
        journalStore: InMemoryMeterJournalStore(),
        location: location,
      );

      // The idle step now states the rate it will charge -- the only way a
      // driver notices 1500 where they meant 15000.
      expect(
        find.text('Тариф: ${groupedMnt(1500)}\u00A0₮/км — засах'),
        findsOneWidget,
      );

      await t.tap(find.text('Тариф: ${groupedMnt(1500)}\u00A0₮/км — засах'));
      await t.pumpAndSettle();

      // Tariff step, pre-filled with the current rate so it can be
      // corrected rather than retyped from nothing. `.first` here and
      // below: the step carries two fields now, the km rate and the
      // waiting rate, and these scenarios are about the km half
      // (`taximeter_waiting_test.dart` covers the other).
      expect(find.text('1 км-ийн үнэ (₮)'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller?.text,
        '1500',
      );

      // Back here means "cancel the edit", not "leave the meter".
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();

      expect(find.text('Очих цэг (сонголттой)'), findsOneWidget);
      expect(find.text('Таксиметр'), findsOneWidget); // still on the page
      expect((await tariffStore.load())?.mntPerKm, 1500); // unchanged

      // The visible cancel button is the same escape hatch for anyone who
      // does not think in back gestures.
      await t.tap(find.text('Тариф: ${groupedMnt(1500)}\u00A0₮/км — засах'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '15000');
      await t.tap(find.text('Цуцлах'));
      await t.pumpAndSettle();

      expect(
        find.text('Тариф: ${groupedMnt(1500)}\u00A0₮/км — засах'),
        findsOneWidget,
      );
      expect((await tariffStore.load())?.mntPerKm, 1500);

      // And saving the correction does take effect.
      await t.tap(find.text('Тариф: ${groupedMnt(1500)}\u00A0₮/км — засах'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '15000');
      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();

      expect(
        find.text('Тариф: ${groupedMnt(15000)}\u00A0₮/км — засах'),
        findsOneWidget,
      );
      expect((await tariffStore.load())?.mntPerKm, 15000);
    },
  );

  testWidgets(
    'on the very first run the tariff step has nothing to cancel back to, '
    'so back leaves the meter for the home page',
    (t) async {
      final location = _TrackedLocationSource();

      await _pumpPushedMeter(
        t,
        tariffStore: InMemoryTariffStore(),
        journalStore: InMemoryMeterJournalStore(),
        location: location,
      );

      expect(find.text('1 км-ийн үнэ (₮)'), findsOneWidget);
      expect(find.text('Цуцлах'), findsNothing);

      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();

      expect(find.text('нүүр'), findsOneWidget);
      expect(find.text('1 км-ийн үнэ (₮)'), findsNothing);
    },
  );

  testWidgets(
    'an unparseable tariff says so instead of leaving the save button '
    'looking broken, and a spaced-out number is still accepted',
    (t) async {
      final tariffStore = InMemoryTariffStore();
      final location = _TrackedLocationSource();

      await _pumpPushedMeter(
        t,
        tariffStore: tariffStore,
        journalStore: InMemoryMeterJournalStore(),
        location: location,
      );

      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();

      // Empty input: still on the tariff step, but now saying why.
      expect(find.text('Зөв тоо оруулна уу (жишээ нь 1000)'), findsOneWidget);
      expect(find.text('1 км-ийн үнэ (₮)'), findsOneWidget);
      expect((await tariffStore.load())?.mntPerKm, isNull);

      // Zero is just as unusable as no number at all.
      await t.enterText(find.byType(TextField).first, '0');
      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();
      expect(find.text('Зөв тоо оруулна уу (жишээ нь 1000)'), findsOneWidget);
      expect((await tariffStore.load())?.mntPerKm, isNull);

      // "15 000" is how a price gets typed by hand -- accepted, and the
      // error clears with it.
      await t.enterText(find.byType(TextField).first, '15 000');
      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();

      expect((await tariffStore.load())?.mntPerKm, 15000);
      expect(find.text('Зөв тоо оруулна уу (жишээ нь 1000)'), findsNothing);
      expect(find.text('Очих цэг (сонголттой)'), findsOneWidget);
    },
  );

  testWidgets(
    'the finished step lets back out unchallenged -- the run is already in '
    'the journal, so there is nothing left to lose',
    (t) async {
      final tariffStore = InMemoryTariffStore();
      await tariffStore.save(DriverTariff(mntPerKm: 1000));
      final journalStore = InMemoryMeterJournalStore();
      final location = _TrackedLocationSource();

      await _pumpPushedMeter(
        t,
        tariffStore: tariffStore,
        journalStore: journalStore,
        location: location,
      );
      await _runMeterWithThreeFixes(t, location, mntPerKm: 1000);

      await t.tap(find.text('Дуусгах'));
      await t.pumpAndSettle();
      expect(find.text('Аяллын дүн'), findsOneWidget);
      expect(await journalStore.loadAll(), hasLength(1));

      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();

      // No dialog, straight out.
      expect(find.text('Тоолуурыг зогсоох уу?'), findsNothing);
      expect(find.text('Аяллын дүн'), findsNothing);
      expect(find.text('нүүр'), findsOneWidget);
    },
  );
}
