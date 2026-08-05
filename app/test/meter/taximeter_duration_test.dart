// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The third rate on the offline taximeter: whole trip duration, billed per
// minute from the first GPS fix to the last, moving or not.
//
// `duration_tariff_test.dart` holds the arithmetic. This file holds the
// screen: that the rate can be typed at all (it is settable nowhere else --
// this meter never reads the published driver profile), that it reaches the
// running session, that it is recorded on the run rather than being lost the
// moment the trip ends, and that a driver who does not charge it never sees
// a row about it.
//
// The overlap with the waiting rate was withdrawn in v0.4.0: standing in
// traffic is part of the trip and is charged here, once, while the waiting
// rate covers only the minutes a driver declares the passenger is keeping
// them. The tests below assert exactly that separation.
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
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/widgets/pill_field.dart';
import 'package:takhi/widgets/primary_button.dart';
import 'package:takhi/theme/takhi_theme.dart';

import '../support/fake_location_source.dart';

/// Always throws, so the routed-fare path deterministically falls back to
/// the offline estimate -- same double as `taximeter_page_test.dart`'s.
class _OfflineRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => throw Exception('offline');
}

/// In-memory `DriverQrStore`: the finished step renders `DriverQrDisplay`,
/// which would otherwise reach `path_provider`'s real platform channel.
class _FakeDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}

  @override
  Future<Uint8List?> load() async => null;

  @override
  Future<void> clear() async {}
}

const _kmTariff = 1000;
const _waitTariff = 300;
const _durationTariff = 120;

/// Start of every scripted run.
const _start = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);

/// ~111m north over ten seconds is ~40 km/h -- comfortably the travelling
/// side of [kWaitingSpeedThresholdKmh].
GpsFix _movedFrom(GpsFix from, {required int seconds}) => GpsFix(
  lat: from.lat + 0.001,
  lon: from.lon,
  timestampSeconds: from.timestampSeconds + seconds,
);

/// A vehicle at a standstill as the GPS actually reports one: ~1.1m of drift
/// rather than the same coordinates twice.
GpsFix _jitteredFrom(GpsFix from, {required int seconds}) => GpsFix(
  lat: from.lat + 0.00001,
  lon: from.lon,
  timestampSeconds: from.timestampSeconds + seconds,
);

// The tariff step's three price boxes, in the order they stand on screen.
// Named for the reason spelled out in `taximeter_waiting_test.dart`: `.last`
// meant the stopped-time field until this rate existed.
Finder _kmField() => find.byType(TextField).at(0);
Finder _waitField() => find.byType(TextField).at(1);
Finder _durationField() => find.byType(TextField).at(2);

Future<void> _pumpMeter(
  WidgetTester t, {
  required TariffStore tariffStore,
  required FakeLocationSource location,
  MeterJournalStore? journal,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        tariffStoreProvider.overrideWithValue(tariffStore),
        meterJournalStoreProvider.overrideWithValue(
          journal ?? InMemoryMeterJournalStore(),
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

/// A meter whose driver already charges [durationMntPerMinute] for the
/// trip's length, so it opens on the idle step ready to start.
Future<void> _pumpIdleMeter(
  WidgetTester t,
  FakeLocationSource location, {
  int waitMntPerMinute = 0,
  int durationMntPerMinute = _durationTariff,
  MeterJournalStore? journal,
}) async {
  final tariffStore = InMemoryTariffStore();
  await tariffStore.save(
    DriverTariff(
      mntPerKm: _kmTariff,
      mntPerMinute: waitMntPerMinute,
      durationMntPerMinute: durationMntPerMinute,
    ),
  );
  await _pumpMeter(
    t,
    tariffStore: tariffStore,
    location: location,
    journal: journal,
  );
}

/// Feeds one fix and lets the page settle -- two pumps because `RideMap`'s
/// polyline layer needs the extra frame on some transitions, then a settle
/// so the mode badge's cross-fade has finished.
Future<void> _feed(
  WidgetTester t,
  FakeLocationSource location,
  GpsFix fix,
) async {
  location.emit(fix);
  await t.pump();
  await t.pumpAndSettle();
}

Future<void> _startRun(WidgetTester t) async {
  await t.tap(find.text('Эхлүүл'));
  await t.pumpAndSettle();
}

String _mnt(int value) => '${groupedMnt(value)}\u00A0₮';

void main() {
  group('tariff step', () {
    testWidgets('takes the trip-duration rate and says what it bills, '
        'because this screen is the only place an offline meter\'s rates '
        'can be set at all', (t) async {
      final tariffStore = InMemoryTariffStore();
      await _pumpMeter(
        t,
        tariffStore: tariffStore,
        location: FakeLocationSource(),
      );

      expect(find.text('Аяллын хугацаа (₮/мин)'), findsOneWidget);
      expect(
        find.text(
          'Аялал эхэлснээс дуустал минут тутамд — явж байсан ч, '
          'зогссон ч. 0 бол үнэгүй.',
        ),
        findsOneWidget,
        reason:
            'two boxes both reading «(₮/мин)» are told apart by this line '
            'alone',
      );

      await t.enterText(_kmField(), '$_kmTariff');
      await t.enterText(_durationField(), '$_durationTariff');
      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();

      final saved = await tariffStore.load();
      expect(saved?.mntPerKm, _kmTariff);
      expect(saved?.durationMntPerMinute, _durationTariff);
      // Untouched, so it keeps the value the form opened with. Since
      // v0.4.0 a first-time driver is handed prefilled boxes to check
      // rather than five blanks to invent -- so "left alone" now means
      // "accepted", which is the whole point of showing them.
      expect(saved?.mntPerMinute, kSuggestedWaitMntPerMinute);
    });

    testWidgets('accepts a blank trip-duration rate as "not charged" rather '
        'than refusing to save', (t) async {
      final tariffStore = InMemoryTariffStore();
      await _pumpMeter(
        t,
        tariffStore: tariffStore,
        location: FakeLocationSource(),
      );

      await t.enterText(_kmField(), '$_kmTariff');
      // Cleared deliberately: a driver who does not charge for the trip's
      // length empties the box, and that must save rather than be refused.
      await t.enterText(_durationField(), '');
      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();

      expect(find.text('Зөв тоо оруулна уу (жишээ нь 100)'), findsNothing);
      expect((await tariffStore.load())?.durationMntPerMinute, 0);
      expect(find.text('Аялалд бэлэн'), findsOneWidget);
    });

    testWidgets('reopens a set trip-duration rate prefilled, and an unset '
        'one blank rather than as a 0 nobody typed', (t) async {
      await _pumpIdleMeter(t, FakeLocationSource());

      await t.tap(find.text('Замын хөлс'));
      await t.pumpAndSettle();

      expect(
        t.widget<TextField>(_durationField()).controller?.text,
        '$_durationTariff',
      );
      expect(t.widget<TextField>(_waitField()).controller?.text, isEmpty);
    });
  });

  group('idle step', () {
    testWidgets('states the trip-duration rate in the charges list, so a '
        'mistyped one is caught before the trip rather than after it', (
      t,
    ) async {
      await _pumpIdleMeter(t, FakeLocationSource());

      expect(find.text('Аяллын хугацааны хөлс'), findsOneWidget);
      expect(find.text('${groupedMnt(_durationTariff)} ₮/мин'), findsOneWidget);

      // The row reaches the same edit step every other row does -- every
      // charge is typed on one screen.
      await t.tap(find.text('Аяллын хугацааны хөлс'));
      await t.pumpAndSettle();
      expect(find.text('Аяллын хугацаа (₮/мин)'), findsOneWidget);
    });

    testWidgets('states the trip-duration rate even at zero: a charge nobody '
        'can see is a charge nobody chose', (t) async {
      await _pumpIdleMeter(t, FakeLocationSource(), durationMntPerMinute: 0);

      // The opposite of what this asserted before v0.4.0. Hiding an unset
      // rate was defended as keeping noise off the screen; it is what let a
      // driver run a nineteen-minute ride, lose 2,850₮ and never learn the
      // field existed.
      expect(find.text('Аяллын хугацааны хөлс'), findsOneWidget);
      expect(find.text('0 ₮/мин'), findsWidgets);
      expect(find.text('Замын хөлс'), findsOneWidget);
      expect(find.text('Хүлээлгийн хөлс'), findsOneWidget);
    });

    testWidgets('admits the pre-trip estimate leaves the trip-duration fare '
        'out -- it is a distance-only figure and the driver is the one who '
        'has to explain the gap', (t) async {
      await _pumpIdleMeter(t, FakeLocationSource());

      expect(
        find.text(
          'Аяллын хугацааны хөлс дээр нь нэмэгдэнэ — '
          'урьдчилсан тооцоонд ороогүй.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('drops that caveat when the trip-duration rate is unset -- '
        'a warning about a charge that does not exist', (t) async {
      await _pumpIdleMeter(t, FakeLocationSource(), durationMntPerMinute: 0);

      expect(
        find.text(
          'Аяллын хугацааны хөлс дээр нь нэмэгдэнэ — '
          'урьдчилсан тооцоонд ороогүй.',
        ),
        findsNothing,
      );
    });
  });

  group('running step', () {
    testWidgets('charges the trip-duration rate on a car that never moved: '
        'the km meter reads zero and the fare does not', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);
      await _startRun(t);

      // Two minutes at a standstill. No distance, no stopped-time rate set,
      // so every төгрөг on screen can only have come from the trip's length.
      final second = _jitteredFrom(_start, seconds: 60);
      final third = _jitteredFrom(second, seconds: 60);
      await _feed(t, location, _start);
      await _feed(t, location, second);
      await _feed(t, location, third);

      final durationFare = computeDurationFareMnt(
        mntPerMinute: _durationTariff,
        durationSeconds: 120,
      );
      expect(durationFare, 240);

      expect(find.text('0.0 км'), findsOneWidget);
      expect(find.text(_mnt(durationFare)), findsOneWidget);
      expect(find.text('Хугацаа ${_mnt(durationFare)}'), findsOneWidget);
    });

    testWidgets('a stopped minute is charged by the trip-duration rate and '
        'not by the waiting rate as well', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location, waitMntPerMinute: _waitTariff);
      await _startRun(t);

      final second = _jitteredFrom(_start, seconds: 60);
      await _feed(t, location, _start);
      await _feed(t, location, second);

      final durationFare = computeDurationFareMnt(
        mntPerMinute: _durationTariff,
        durationSeconds: 60,
      );

      // The trip-duration charge, and nothing from the waiting rate: the
      // driver never put the meter into its waiting phase, and a jam is not
      // the passenger keeping them. Until v0.4.0 both rates claimed this
      // same minute and the double count was on screen, unremarked.
      expect(find.text('Хугацаа ${_mnt(durationFare)}'), findsOneWidget);
      expect(find.textContaining('Зогсолт'), findsNothing);
      expect(find.text(_mnt(durationFare)), findsOneWidget);
      // And the standing-still readout instead, which carries no money.
      expect(find.textContaining('Зогссон'), findsWidgets);
    });

    testWidgets(
      'adding the trip-duration charge does not shrink the stopped-time '
      'figures beside it -- `_RunningStatRow` scales to fit, and a third '
      'item on that line took the pair from 10.5 to 6.8 logical pixels at '
      '360dp: smaller than the label it belonged to',
      (t) async {
        // This is a measurement, not a "does it render" check, because the
        // failure it guards was invisible to every widget finder in this
        // file. The text was present, unclipped, in the right place, and
        // too small to read from the driver's seat. Only the rendered size
        // says so.
        await t.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => t.binding.setSurfaceSize(null));

        // Rates high enough that both time fares run to five figures, which
        // is where the shrinking actually bites -- a 600₮ fare fits either
        // way and would have let the bug through.
        const bigWait = 900;
        const bigDuration = 700;

        Future<double> waitingStatHeight({required int durationRate}) async {
          // Unmount whatever the previous pass left mounted. Without this the
          // second `pumpWidget` reuses the same element -- same widget type,
          // same position -- so `TaximeterPage.initState` never runs again,
          // the new tariff store is never read, and the page is still sitting
          // on the first pass's running step.
          await t.pumpWidget(const SizedBox.shrink());
          await t.pumpAndSettle();

          final location = FakeLocationSource();
          await _pumpIdleMeter(
            t,
            location,
            waitMntPerMinute: bigWait,
            durationMntPerMinute: durationRate,
          );
          await _startRun(t);
          await _feed(t, location, _start);
          // Twenty minutes at a standstill.
          await _feed(t, location, _jitteredFrom(_start, seconds: 1200));

          // Measured on the standing-still readout, which is what a stopped
          // car shows since v0.4.0 — the waiting line now belongs to a
          // phase only the driver can enter, and a jam is not it.
          return t.getRect(find.text('Зогссон 20 мин')).height;
        }

        final alone = await waitingStatHeight(durationRate: 0);
        final beside = await waitingStatHeight(durationRate: bigDuration);

        expect(
          beside,
          alone,
          reason:
              'the trip-duration charge has a line of its own precisely so '
              'it cannot squeeze the row above it',
        );
        // A floor as well as a comparison: the two could yet shrink
        // together, and equally illegible is not a pass.
        expect(alone, greaterThan(9.0));
      },
    );

    testWidgets('shows no trip-duration figure when the rate is unset -- an '
        'always-zero readout is noise on the one screen read while driving', (
      t,
    ) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location, durationMntPerMinute: 0);
      await _startRun(t);

      await _feed(t, location, _start);
      await _feed(t, location, _jitteredFrom(_start, seconds: 60));

      expect(find.textContaining('Хугацаа '), findsNothing);
    });

    testWidgets(
      'fits a small phone with every rate running: badge, headline fare, '
      'the statistics and three controls over the map',
      (t) async {
        // 360x640 logical pixels -- the small end of the Android phones this
        // app is actually driven on.
        await t.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => t.binding.setSurfaceSize(null));

        final location = FakeLocationSource();
        await _pumpIdleMeter(t, location, waitMntPerMinute: _waitTariff);
        await _startRun(t);
        await _feed(t, location, _start);
        await _feed(t, location, _jitteredFrom(_start, seconds: 70));

        expect(t.takeException(), isNull);
        // «Зогссон», not «Хүлээж байна»: the car has stopped, but nobody
        // has told the meter the passenger is keeping them.
        expect(find.text('Зогссон'), findsOneWidget);
        expect(find.widgetWithText(PrimaryButton, 'Дуусгах'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Түр зогсоох'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Хүлээж эхлэх'), findsOneWidget);

        // And the summary underneath it, whose row labels are the longest
        // Cyrillic strings this screen ever renders at once.
        await t.tap(find.widgetWithText(PrimaryButton, 'Дуусгах'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Замын хөлс'), findsOneWidget);
        expect(find.text('Зогссон хугацаа'), findsOneWidget);
        expect(find.text('Хугацааны хөлс'), findsOneWidget);
        expect(find.text('Нийт'), findsOneWidget);
      },
    );

    testWidgets('fits a small phone on the tariff step, where eight price '
        'boxes and their explanations now stack', (t) async {
      await t.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));

      await _pumpMeter(
        t,
        tariffStore: InMemoryTariffStore(),
        location: FakeLocationSource(),
      );

      expect(t.takeException(), isNull);
      expect(find.byType(PillField), findsNWidgets(8));
      expect(find.text('Аяллын хугацаа (₮/мин)'), findsOneWidget);
      expect(find.widgetWithText(PrimaryButton, 'Хадгалах'), findsOneWidget);
    });
  });

  group('finished step', () {
    testWidgets('breaks the total into rows that add up to it exactly, so a '
        'passenger checking the arithmetic gets the number they are asked '
        'to pay', (t) async {
      final location = FakeLocationSource();
      final journal = InMemoryMeterJournalStore();
      await _pumpIdleMeter(
        t,
        location,
        waitMntPerMinute: _waitTariff,
        journal: journal,
      );
      await _startRun(t);

      // One travelling leg, then a full minute stopped.
      final second = _movedFrom(_start, seconds: 10);
      final third = _jitteredFrom(second, seconds: 60);
      await _feed(t, location, _start);
      await _feed(t, location, second);
      await _feed(t, location, third);

      await t.tap(find.widgetWithText(PrimaryButton, 'Дуусгах'));
      await t.pumpAndSettle();

      final distanceFare = computeFareMnt(
        mntPerKm: _kmTariff,
        distanceMeters: trackDistanceMeters([_start, second]),
      );
      // 70 seconds of trip: the ten travelling and the sixty stopped. All
      // of it on the trip-duration rate, because a jam is part of the trip
      // — the waiting rate is for the passenger keeping the driver, and
      // nobody invoked it here.
      final durationFare = computeDurationFareMnt(
        mntPerMinute: _durationTariff,
        durationSeconds: 70,
      );
      expect(durationFare, greaterThan(0));

      final total = distanceFare + durationFare;

      final entry = (await journal.loadAll()).single;
      expect(entry.durationFareMnt, durationFare);
      expect(entry.waitingFareMnt, 0);
      expect(entry.stoppedSeconds, 60);
      expect(entry.fareMnt, total);
      // The one the foundation had to fix: an unsubtracted duration charge
      // would land in the distance row as kilometres this car never drove.
      expect(
        entry.distanceFareMnt,
        distanceFare,
        reason: 'the distance row is the total minus every recorded share',
      );

      expect(find.text('Замын хөлс'), findsOneWidget);
      expect(find.text(_mnt(distanceFare)), findsOneWidget);
      // No waiting row: the driver never invoked the waiting phase, so it
      // would print a zero for a charge nobody made.
      expect(find.text('Зогсолтын хөлс'), findsNothing);
      // The standing-still line instead, which accounts for the minute
      // without claiming a second charge for it.
      expect(find.text('Зогссон хугацаа'), findsOneWidget);
      expect(find.text('Хугацааны хөлс'), findsOneWidget);
      expect(find.text(_mnt(durationFare)), findsOneWidget);
      expect(find.text('Нийт'), findsOneWidget);
      // Twice: the headline figure and the row that closes the sum.
      expect(find.text(_mnt(total)), findsNWidgets(2));

      // The rows a passenger can see, added the way a passenger would add
      // them. `fare_calc.dart` sums already-rounded parts precisely so this
      // holds -- a one-төгрөг gap here is small in money and large in trust.
      expect(distanceFare + durationFare, entry.fareMnt);
    });

    testWidgets('leaves the trip-duration row off a run whose driver does '
        'not charge for it, rather than printing a 0 ₮ to be queried', (
      t,
    ) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location, durationMntPerMinute: 0);
      await _startRun(t);

      await _feed(t, location, _start);
      await _feed(t, location, _movedFrom(_start, seconds: 10));

      await t.tap(find.widgetWithText(PrimaryButton, 'Дуусгах'));
      await t.pumpAndSettle();

      expect(find.text('Хугацааны хөлс'), findsNothing);
      expect(find.text('Замын хөлс'), findsOneWidget);
      expect(find.text('Нийт'), findsOneWidget);
    });
  });

  group('the journal', () {
    testWidgets('records the trip-duration charge on the run, so the history '
        'a driver reads next week is the money they actually took', (t) async {
      final location = FakeLocationSource();
      final journal = InMemoryMeterJournalStore();
      await _pumpIdleMeter(t, location, journal: journal);
      await _startRun(t);

      await _feed(t, location, _start);
      await _feed(t, location, _movedFrom(_start, seconds: 60));

      await t.tap(find.widgetWithText(PrimaryButton, 'Дуусгах'));
      await t.pumpAndSettle();

      final entry = (await journal.loadAll()).single;
      expect(
        entry.durationFareMnt,
        computeDurationFareMnt(
          mntPerMinute: _durationTariff,
          durationSeconds: 60,
        ),
      );
      expect(entry.durationFareMnt, greaterThan(0));
      // Recorded as its own share and subtracted from the distance one --
      // the two together are what keeps a week's totals honest.
      expect(
        entry.distanceFareMnt + entry.waitingFareMnt + entry.durationFareMnt,
        entry.fareMnt,
      );
    });
  });
}
