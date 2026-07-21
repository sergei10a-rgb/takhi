// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_track.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';

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

void main() {
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
            locationPermissionCheckProvider.overrideWithValue(
              () async => true,
            ),
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

      await tester.enterText(find.byType(TextField), '1000');
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();
      expect(await tariffStore.loadMntPerKm(), 1000);

      // Idle step now showing.
      expect(find.text('Эхлүүл'), findsOneWidget);
      expect(find.text('Очих цэг (сонголттой)'), findsOneWidget);

      await tester.tap(find.text('Эхлүүл'));
      await tester.pumpAndSettle();

      // Running step: starts at zero before any fix.
      expect(find.text('0₮'), findsOneWidget);
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
      expect(find.text('0₮'), findsOneWidget);

      fakeLocation.emit(fix2);
      await tester.pump();
      await tester.pump();
      final distanceAfterTwo = trackDistanceMeters([fix1, fix2]);
      final fareAfterTwo = computeFareMnt(
        mntPerKm: 1000,
        distanceMeters: distanceAfterTwo,
      );
      expect(find.text('$fareAfterTwo₮'), findsOneWidget);
      expect(
        find.text('${distanceAfterTwo / 1000} км'),
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
      expect(find.text('$fareAfterThree₮'), findsOneWidget);
      expect(
        find.text('${distanceAfterThree / 1000} км'),
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
      expect(find.text('Тахь — эзэнгүй такси'), findsOneWidget);

      // Resets back to idle for the next passenger.
      await tester.tap(find.text('Эхлүүл'));
      await tester.pumpAndSettle();
      expect(find.text('Очих цэг (сонголттой)'), findsOneWidget);
    },
  );
}
