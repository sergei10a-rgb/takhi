// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A zero is allowed. An invisible zero is not.
//
// A driver ran a nineteen-minute ride and lost 2,850₮ because the
// trip-duration rate defaulted to zero and no screen he ever opened
// mentioned it. He did not choose that zero; he had no idea the field
// existed. These tests pin the fix — every charge, with its amount, on the
// screen a driver reads before starting a run.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/widgets/pill_field.dart';

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

Future<void> _pump(WidgetTester t, TariffStore tariffStore) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        tariffStoreProvider.overrideWithValue(tariffStore),
        meterJournalStoreProvider.overrideWithValue(
          InMemoryMeterJournalStore(),
        ),
        routingClientProvider.overrideWithValue(_NoRoutingClient()),
        locationSourceProvider.overrideWithValue(FakeLocationSource()),
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

void main() {
  testWidgets('the ready screen lists every charge, including the ones set '
      'to zero', (t) async {
    final store = InMemoryTariffStore();
    // A tariff with four of the six charges left at nothing — exactly the
    // shape the field-tested build produced, where the zeros were silent.
    await store.save(const DriverTariff(mntPerKm: 1500));
    await store.markChargesSeen();

    await _pump(t, store);

    expect(find.text('Замын хөлс'), findsOneWidget);
    expect(find.text('Аяллын хугацааны хөлс'), findsOneWidget);
    expect(find.text('Хүлээлгийн хөлс'), findsOneWidget);
    expect(find.text('Суултын хөлс'), findsOneWidget);
    expect(find.text('Дуудлагын суурь хөлс'), findsOneWidget);
    expect(find.text('Доод хязгаар'), findsOneWidget);
    // The two free allowances belong to "every charge" as much as the rest:
    // an invisible allowance is one a driver never checks. Shown even at
    // zero, like the charges above them.
    expect(find.text('Үнэгүй зай'), findsOneWidget);
    expect(find.text('Үнэгүй хугацаа'), findsOneWidget);

    // And their amounts, zeros and all. This is the assertion the old
    // screen could not have passed: it hid the trip-duration rate whenever
    // it was zero, which is every install that never knew to set it.
    // Matched loosely on the unit: the thousands separator is a
    // non-breaking space (money_format.dart), and a test that re-types that
    // breaks on a punctuation change that costs a driver nothing.
    expect(find.textContaining('₮/км'), findsOneWidget);
    expect(find.text('0 ₮/мин'), findsNWidgets(2));
    // `meterFareLabel` puts a non-breaking space before the sign. Three:
    // the flag-fall, the booked-ride base, and the minimum fare, unset.
    expect(find.text('0 ₮'), findsNWidgets(3));
    // The allowances read in their own units, never as money — an unset
    // free distance is «0 м» and an unset free time «0 мин», so neither is
    // a 0 ₮ charge.
    expect(find.text('0 м'), findsOneWidget);
    expect(find.text('0 мин'), findsOneWidget);
  });

  testWidgets('a driver meeting the meter for the first time gets the boxes '
      'filled in, and is told the figures are only a starting point', (
    t,
  ) async {
    await _pump(t, InMemoryTariffStore());

    // Eight boxes, prefilled — a driver should have to *check* the numbers,
    // not invent them before they can work. The last three (minimum fare and
    // the two free allowances) are empty by default: each is a choice, not a
    // suggestion.
    expect(find.byType(PillField), findsNWidgets(8));
    // 1500 twice: the km rate and the booked-ride base fare. 150 twice:
    // the trip-duration and waiting rates.
    expect(find.text('1500'), findsNWidgets(2));
    expect(find.text('150'), findsNWidgets(2));

    // And the app claims nothing about them. It must not: the moment it
    // calls these a market rate, a passenger can point at the app to argue
    // a driver down once the market has moved, and somebody has to keep the
    // number current — which an ownerless app cannot have.
    expect(
      find.text('Эдгээр нь зөвхөн эхлэх утга. Өөрийнхөө үнийг бич.'),
      findsOneWidget,
    );
    expect(find.textContaining('зах зээл'), findsNothing);
  });

  testWidgets('the ready screen prints a set free allowance in its own units, '
      'the metres and whole minutes the driver entered', (t) async {
    final store = InMemoryTariffStore();
    // 500 metres and two minutes folded into the base fare. The seconds are
    // stored (120) but the driver set — and reads back — whole minutes.
    await store.save(
      const DriverTariff(
        mntPerKm: 1500,
        freeDistanceMeters: 500,
        freeDurationSeconds: 120,
      ),
    );
    await store.markChargesSeen();

    await _pump(t, store);

    expect(find.text('Үнэгүй зай'), findsOneWidget);
    expect(find.text('500 м'), findsOneWidget);
    expect(find.text('Үнэгүй хугацаа'), findsOneWidget);
    expect(find.text('2 мин'), findsOneWidget);
  });

  testWidgets('a tariff saved by an older build sends the driver through the '
      'whole list once', (t) async {
    final store = InMemoryTariffStore();
    // Saved, but never marked as seen: the build that wrote it knew about
    // fewer charges than this one has.
    await store.save(const DriverTariff(mntPerKm: 1500, mntPerMinute: 150));

    await _pump(t, store);

    expect(find.textContaining('Шинэ хөлс нэмэгдлээ'), findsOneWidget);
  });

  testWidgets('the notice goes away once the driver has saved the charges', (
    t,
  ) async {
    final store = InMemoryTariffStore();
    await store.save(const DriverTariff(mntPerKm: 1500, mntPerMinute: 150));

    await _pump(t, store);
    expect(find.textContaining('Шинэ хөлс нэмэгдлээ'), findsOneWidget);

    // Scrolled to first: five charge rows and a notice push the edit
    // action below the fold on the default test surface. Every row opens
    // the same form, so a driver on a small phone is never stuck — but a
    // test that taps blind would pass while hitting nothing.
    await t.ensureVisible(find.text('Дүн өөрчлөх'));
    await t.pumpAndSettle();
    await t.tap(find.text('Дүн өөрчлөх'));
    await t.pumpAndSettle();
    expect(find.text('Хадгалах'), findsOneWidget);
    await t.tap(find.text('Хадгалах'));
    await t.pumpAndSettle();

    expect(find.textContaining('Шинэ хөлс нэмэгдлээ'), findsNothing);
    expect(find.text('Эхлүүл'), findsOneWidget);
  });
}
