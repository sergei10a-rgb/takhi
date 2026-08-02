// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_track.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/location_picker.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/widgets/pill_field.dart';

import '../support/fake_location_source.dart';

/// Always throws -- forces `estimateTripFare`'s offline-estimate fallback
/// path deterministically, mirroring `fare_estimate_test.dart`'s own
/// `_FakeRoutingClient`. Unused by this test's scripted taps (which never
/// pick a destination), but kept so every provider `TaximeterPage` reads is
/// overridden with a deterministic double, never the real HTTP client.
class _AlwaysFailingRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => throw Exception('offline');
}

/// Records every `routeDistanceMeters` call as a pending, manually
/// completed `Completer` instead of resolving immediately -- lets a test
/// drive two in-flight requests to completion in either order, which is
/// exactly the race `_estimateDestinationFare`'s request-sequence guard
/// (`taximeter_page.dart`) exists to survive. Counting entries in
/// [requests] also proves how many actual routing calls a burst of
/// destination changes produced, i.e. whether debouncing worked.
class _ControllableRoutingClient implements RoutingClient {
  final requests = <Completer<double?>>[];

  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) {
    final completer = Completer<double?>();
    requests.add(completer);
    return completer.future;
  }
}

/// In-memory `DriverQrStore` test double -- the `finished` step always
/// renders `DriverQrDisplay` (this screen is driver-only by construction),
/// which reads this provider; without an override it would hit
/// `path_provider`'s real platform channel, which throws under
/// `flutter_test`. Mirrors `driver_qr_display_test.dart`'s own
/// `_FakeDriverQrStore`.
class _FakeDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}

  @override
  Future<Uint8List?> load() async => null;

  @override
  Future<void> clear() async {}
}

/// Opens the idle step's destination picker and returns the `onChanged`
/// callback a map pan or a landmark keystroke fires.
///
/// The picker is no longer mounted permanently on the idle step -- it sits
/// behind the destination pill, so a test reaches it the same way a driver
/// does. The sheet is left open afterwards: it is a `PopupRoute`, so the
/// idle step underneath stays mounted and its estimate chips remain
/// findable.
Future<ValueChanged<PickedLocation>> _openDestinationPicker(
  WidgetTester tester,
) async {
  await tester.tap(find.byType(PillField));
  await tester.pumpAndSettle();
  return tester
      .widget<LocationPickerField>(find.byType(LocationPickerField))
      .onChanged;
}

/// The Mongolian strings, loaded once, so the expectations below name the
/// same key the screen renders rather than a copy of its current wording.
/// They were spelled out inline until `estimatedFareLabel` changed and three
/// of them started looking for a string nothing produces any more.
late AppLocalizations _l;

void main() {
  setUpAll(() async {
    _l = await AppLocalizations.delegate.load(const Locale('mn'));
  });

  testWidgets(
    'tariff -> idle -> running (growing fare/distance) -> finished appends '
    'exactly one journal entry, all without a relayPoolProvider override',
    (tester) async {
      final tariffStore = InMemoryTariffStore();
      final journalStore = InMemoryMeterJournalStore();
      final fakeLocation = FakeLocationSource();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tariffStoreProvider.overrideWithValue(tariffStore),
            meterJournalStoreProvider.overrideWithValue(journalStore),
            routingClientProvider.overrideWithValue(
              _AlwaysFailingRoutingClient(),
            ),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
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

      // No tariff saved yet -- starts on the tariff-entry step.
      expect(find.text('1 км-ийн үнэ (₮)'), findsOneWidget);
      expect(find.text('Эхлүүл'), findsNothing);

      // `.first` throughout: the tariff step takes five charges now and
      // this scenario is about the km one. The time rates are cleared
      // rather than left alone, because since v0.4.0 the form opens
      // prefilled — a driver checks five numbers instead of inventing
      // them — so an untouched box is an accepted charge, not a blank one,
      // and this test's fare has to stay distance-only to mean anything.
      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.enterText(find.byType(TextField).at(2), '');
      await tester.enterText(find.byType(TextField).at(3), '');
      await tester.enterText(find.byType(TextField).at(4), '');
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();
      expect((await tariffStore.load())?.mntPerKm, 1000);

      // Idle step now showing.
      expect(find.text('Эхлүүл'), findsOneWidget);
      expect(find.text('Очих цэг (сонголттой)'), findsOneWidget);

      await tester.tap(find.text('Эхлүүл'));
      await tester.pumpAndSettle();

      // Running step: starts at zero before any fix.
      expect(find.text('0\u00A0₮'), findsOneWidget);
      expect(find.text('0.0 км'), findsOneWidget);

      const fix1 = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);
      const fix2 = GpsFix(lat: 47.9196, lon: 106.9176, timestampSeconds: 1010);
      const fix3 = GpsFix(lat: 47.9206, lon: 106.9176, timestampSeconds: 1020);

      // Every emit gets two pumps -- `RideMap`'s tile/polyline layer needs
      // an extra frame to settle on some fix transitions (e.g. the one
      // where the polyline first spans more than one point), so a single
      // `pump()` is not always enough to observe the resulting rebuild.
      fakeLocation.emit(fix1);
      await tester.pump();
      await tester.pump();
      // A single fix has no distance yet.
      expect(find.text('0\u00A0₮'), findsOneWidget);

      fakeLocation.emit(fix2);
      await tester.pump();
      await tester.pump();
      final distanceAfterTwo = trackDistanceMeters([fix1, fix2]);
      final fareAfterTwo = computeFareMnt(
        mntPerKm: 1000,
        distanceMeters: distanceAfterTwo,
      );
      expect(find.text('${groupedMnt(fareAfterTwo)}\u00A0₮'), findsOneWidget);
      // One decimal on screen, full precision in the fare: the running
      // step rounds the kilometre figure for display only (`_displayKm`),
      // because "0.111 км" is not what a driver can read at a junction.
      expect(
        find.text('${(distanceAfterTwo / 1000).toStringAsFixed(1)} км'),
        findsOneWidget,
      );

      fakeLocation.emit(fix3);
      await tester.pump();
      await tester.pump();
      final distanceAfterThree = trackDistanceMeters([fix1, fix2, fix3]);
      final fareAfterThree = computeFareMnt(
        mntPerKm: 1000,
        distanceMeters: distanceAfterThree,
      );
      expect(fareAfterThree, greaterThan(fareAfterTwo));
      expect(find.text('${groupedMnt(fareAfterThree)}\u00A0₮'), findsOneWidget);
      expect(
        find.text('${(distanceAfterThree / 1000).toStringAsFixed(1)} км'),
        findsOneWidget,
      );

      expect(await journalStore.loadAll(), isEmpty);

      await tester.tap(find.text('Дуусгах'));
      await tester.pumpAndSettle();

      // Finished step: exactly one journal entry with the expected numbers.
      final entries = await journalStore.loadAll();
      expect(entries, hasLength(1));
      expect(entries.single.distanceMeters, distanceAfterThree);
      expect(entries.single.fareMnt, fareAfterThree);

      expect(find.text('Аяллын дүн'), findsOneWidget);
      // Absent while the driver has no bank QR: see `_FinishedStep`.
      expect(find.text('Тахь — эзэнгүй такси'), findsNothing);

      // Resets back to idle for the next passenger. The button says so:
      // «Эхлүүл» under a finished total read as though the same trip were
      // about to start again.
      await tester.tap(find.text('Дараагийн зорчигч'));
      await tester.pumpAndSettle();
      expect(find.text('Очих цэг (сонголттой)'), findsOneWidget);
    },
  );

  testWidgets(
    'denied location permission on start shows the retry view instead of '
    'silently doing nothing, and retrying with permission granted reaches '
    'the running step',
    (tester) async {
      final tariffStore = InMemoryTariffStore();
      await tariffStore.save(DriverTariff(mntPerKm: 1000));
      final journalStore = InMemoryMeterJournalStore();
      final fakeLocation = FakeLocationSource();

      // First call (the "Эхлүүл" tap) denies; every call after (the retry
      // tap) grants -- exercises both the `_locationPermissionDenied = true`
      // branch (`LocationPermissionDeniedView`) and the retry path back
      // into `_start`, neither of which the scenario above covers (it
      // overrides this provider with a constant `() async => true`).
      // Mirrors `active_trip_view_test.dart`'s own denied-permission test.
      var callCount = 0;
      Future<bool> checkPermission() async {
        callCount++;
        return callCount > 1;
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tariffStoreProvider.overrideWithValue(tariffStore),
            meterJournalStoreProvider.overrideWithValue(journalStore),
            routingClientProvider.overrideWithValue(
              _AlwaysFailingRoutingClient(),
            ),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(checkPermission),
            driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
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

      // Tariff already saved -- starts directly on the idle step.
      expect(find.text('Эхлүүл'), findsOneWidget);

      await tester.tap(find.text('Эхлүүл'));
      await tester.pumpAndSettle();

      // Denied: the retry view is shown, not the idle destination picker.
      expect(
        find.text('Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай'),
        findsOneWidget,
      );
      expect(find.text('Очих цэг (сонголттой)'), findsNothing);

      // Retry: permission now granted, idle step's controls return.
      await tester.tap(find.text('Зөвшөөрөл өгөх'));
      await tester.pumpAndSettle();

      expect(
        find.text('Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай'),
        findsNothing,
      );
      expect(find.text('Очих цэг (сонголттой)'), findsOneWidget);

      // The retry only re-checks permission -- it does not itself start the
      // meter -- so a second tap on "Эхлүүл" is what actually reaches the
      // running step, confirming the flag reset didn't leave the page stuck.
      await tester.tap(find.text('Эхлүүл'));
      await tester.pumpAndSettle();
      expect(find.text('0\u00A0₮'), findsOneWidget);
    },
  );

  testWidgets(
    'rapid destination changes (a map pan or fast typing) are debounced '
    'into exactly one routed-fare request, not one per intermediate value',
    (tester) async {
      final tariffStore = InMemoryTariffStore();
      await tariffStore.save(DriverTariff(mntPerKm: 1000));
      final fakeLocation = FakeLocationSource();
      final routing = _ControllableRoutingClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tariffStoreProvider.overrideWithValue(tariffStore),
            meterJournalStoreProvider.overrideWithValue(
              InMemoryMeterJournalStore(),
            ),
            routingClientProvider.overrideWithValue(routing),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
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

      final onChanged = await _openDestinationPicker(tester);

      // Three destination changes in quick succession, each well inside
      // the debounce window -- mirrors a continuous map drag or fast
      // landmark typing (`LocationPickerField.onChanged` fires on every
      // pan frame and keystroke, per its own doc comment).
      onChanged(const PickedLocation(lat: 47.92, lon: 106.92));
      await tester.pump(const Duration(milliseconds: 200));
      onChanged(const PickedLocation(lat: 47.93, lon: 106.93));
      await tester.pump(const Duration(milliseconds: 200));
      onChanged(const PickedLocation(lat: 47.94, lon: 106.94));
      await tester.pump(const Duration(milliseconds: 200));

      // Still inside the debounce window from the last change -- nothing
      // sent to the routing client yet.
      expect(routing.requests, isEmpty);

      // Past the debounce window: the chain fires, reaching the point
      // where it awaits a GPS fix.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      fakeLocation.emit(
        const GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000),
      );
      await tester.pump();

      expect(routing.requests, hasLength(1));

      routing.requests.single.complete(3000);
      await tester.pumpAndSettle();

      final expectedMnt = computeFareMnt(mntPerKm: 1000, distanceMeters: 3000);
      expect(
        find.text(_l.estimatedFareLabel(groupedMnt(expectedMnt))),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a stale routed-fare response from an earlier destination change is '
    'ignored once a newer destination change has already resolved',
    (tester) async {
      final tariffStore = InMemoryTariffStore();
      await tariffStore.save(DriverTariff(mntPerKm: 1000));
      final fakeLocation = FakeLocationSource();
      final routing = _ControllableRoutingClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tariffStoreProvider.overrideWithValue(tariffStore),
            meterJournalStoreProvider.overrideWithValue(
              InMemoryMeterJournalStore(),
            ),
            routingClientProvider.overrideWithValue(routing),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            driverQrStoreProvider.overrideWithValue(_FakeDriverQrStore()),
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

      final onChanged = await _openDestinationPicker(tester);

      // First destination settles past its own debounce window, issuing
      // request #1's full chain (permission + GPS fix + routing call).
      onChanged(const PickedLocation(lat: 47.92, lon: 106.92));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      fakeLocation.emit(
        const GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000),
      );
      await tester.pump();
      expect(routing.requests, hasLength(1));

      // Second destination change, issued only after request #1 is
      // already in flight -- also settles past its own debounce window,
      // issuing request #2's chain. The debounce Timer alone already
      // guarantees a change *within* the window collapses into one
      // request (previous test); a genuine two-in-flight race needs two
      // full settle cycles like this.
      onChanged(const PickedLocation(lat: 47.95, lon: 106.95));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      fakeLocation.emit(
        const GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1001),
      );
      await tester.pump();
      expect(routing.requests, hasLength(2));

      // Resolve the NEWER request first (as if it genuinely finished
      // faster) -- its estimate is what should be on screen.
      routing.requests[1].complete(9000);
      await tester.pumpAndSettle();
      final newerMnt = computeFareMnt(mntPerKm: 1000, distanceMeters: 9000);
      expect(
        find.text(_l.estimatedFareLabel(groupedMnt(newerMnt))),
        findsOneWidget,
      );

      // Resolve the OLDER, now-stale request afterwards -- it must be
      // silently dropped rather than clobbering the newer estimate.
      routing.requests[0].complete(1000);
      await tester.pumpAndSettle();
      expect(
        find.text(_l.estimatedFareLabel(groupedMnt(newerMnt))),
        findsOneWidget,
      );
      final staleMnt = computeFareMnt(mntPerKm: 1000, distanceMeters: 1000);
      expect(
        find.text(_l.estimatedFareLabel(groupedMnt(staleMnt))),
        findsNothing,
      );
    },
  );
}
