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
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/info_chip.dart';
import 'package:takhi/widgets/pill_field.dart';
import 'package:takhi/widgets/primary_button.dart';
import 'package:takhi/widgets/takhi_sheet.dart';

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

/// Start of every scripted run.
const _start = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);

/// 0.001° of latitude is ~111m; over ten seconds that is ~40 km/h, well
/// clear of [kWaitingSpeedThresholdKmh] on the travelling side.
GpsFix _movedFrom(GpsFix from, {required int seconds}) => GpsFix(
  lat: from.lat + 0.001,
  lon: from.lon,
  timestampSeconds: from.timestampSeconds + seconds,
);

/// A vehicle at a standstill, as the GPS actually reports one: not the same
/// coordinates twice but a metre or so of drift. ~1.1m over ten seconds is
/// ~0.4 km/h -- the jitter the waiting/travelling split exists to refuse to
/// bill as travel.
GpsFix _jitteredFrom(GpsFix from, {required int seconds}) => GpsFix(
  lat: from.lat + 0.00001,
  lon: from.lon,
  timestampSeconds: from.timestampSeconds + seconds,
);

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

/// A meter that already carries both halves of the tariff, so it opens on
/// the idle step ready to start.
Future<void> _pumpIdleMeter(
  WidgetTester t,
  FakeLocationSource location, {
  int waitTariffMntPerMinute = _waitTariff,
  MeterJournalStore? journal,
}) async {
  final tariffStore = InMemoryTariffStore();
  await tariffStore.save(
    DriverTariff(mntPerKm: _kmTariff, mntPerMinute: waitTariffMntPerMinute),
  );
  await _pumpMeter(
    t,
    tariffStore: tariffStore,
    location: location,
    journal: journal,
  );
}

/// Feeds one fix and lets the page settle. Two pumps because `RideMap`'s
/// polyline layer needs the extra frame on some transitions (see
/// `taximeter_page_test.dart`), then a settle so the mode badge's cross-fade
/// has finished -- mid-transition both the outgoing and the incoming mode
/// are in the tree, and an assertion landing there would read the meter as
/// being in two modes at once.
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

/// Taps the pause control and confirms the dialog it raises. The dialog's
/// own confirm carries the same verb as the button that opened it, so the
/// tap is scoped to the dialog rather than matched by label alone.
Future<void> _pauseAndConfirm(WidgetTester t) async {
  await t.tap(find.widgetWithText(TextButton, 'Түр зогсоох'));
  await t.pumpAndSettle();
  expect(find.text('Тоолуурыг түр зогсоох уу?'), findsOneWidget);
  await t.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Түр зогсоох'),
    ),
  );
  await t.pumpAndSettle();
}

// The tariff step's three price boxes, in the order they stand on screen:
// kilometre, stopped time, whole-trip duration.
//
// Named rather than reached for as `.first` / `.last` at each call site,
// because `.last` is exactly what broke the day the third rate arrived: it
// had meant "the stopped-time field" in every one of these tests and
// silently started meaning "the duration field", without a single assertion
// changing its wording. A named finder turns that into a rename a reader can
// see rather than a test that still passes while checking the wrong box.
//
// Anchored on the fields' own keys rather than on their order. Naming the
// helpers alone left the ordinal coupling intact one layer down -- the next
// field inserted above them would move all three indices, and the helpers
// would go on reading exactly as correct as they do now.
Finder _fieldIn(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(TextField));
Finder _kmField() => _fieldIn(kMeterKmTariffFieldKey);
Finder _waitField() => _fieldIn(kMeterWaitTariffFieldKey);
Finder _durationField() => _fieldIn(kMeterDurationTariffFieldKey);

/// The colour the headline fare is currently painted in -- the single
/// strongest signal on this screen of whether the meter is live.
Color? _fareColour(WidgetTester t, int mnt) =>
    t.widget<Text>(find.text('${groupedMnt(mnt)}\u00A0₮')).style?.color;

void main() {
  group('tariff step', () {
    testWidgets('takes both halves of the tariff and says in one line what the '
        'waiting rate is for -- a driver meeting it for the first time must '
        'not have to guess', (t) async {
      final tariffStore = InMemoryTariffStore();
      await _pumpMeter(
        t,
        tariffStore: tariffStore,
        location: FakeLocationSource(),
      );

      expect(find.text('1 км-ийн үнэ (₮)'), findsOneWidget);
      expect(find.text('Түгжрэл/зогсолт (₮/мин)'), findsOneWidget);
      expect(
        find.text('Түгжрэлд зогсох үед энэ үнээр бодно. 0 бол зогсолт үнэгүй.'),
        findsOneWidget,
      );
      // Three capsules: kilometres, stopped time, whole-trip duration.
      expect(find.byType(PillField), findsNWidgets(3));

      await t.enterText(_kmField(), '$_kmTariff');
      await t.enterText(_waitField(), '$_waitTariff');
      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();

      final saved = await tariffStore.load();
      expect(saved?.mntPerKm, _kmTariff);
      expect(saved?.mntPerMinute, _waitTariff);
      // Left blank above, so it stays unset -- typing into the stopped-time
      // box must not spill into the box beside it.
      expect(saved?.durationMntPerMinute, 0);
    });

    testWidgets('accepts a blank waiting rate as "waiting is free" rather than '
        'refusing to save -- a driver who does not charge for waiting has '
        'nothing to type there', (t) async {
      final tariffStore = InMemoryTariffStore();
      await _pumpMeter(
        t,
        tariffStore: tariffStore,
        location: FakeLocationSource(),
      );

      await t.enterText(_kmField(), '$_kmTariff');
      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();

      expect(find.text('Зөв тоо оруулна уу (жишээ нь 300)'), findsNothing);
      expect(find.text('Зөв тоо оруулна уу (жишээ нь 100)'), findsNothing);
      expect((await tariffStore.load())?.mntPerMinute, 0);
      expect((await tariffStore.load())?.durationMntPerMinute, 0);
      expect(find.text('Аялалд бэлэн'), findsOneWidget);
    });

    testWidgets(
      'refuses an unreadable waiting rate, and states both verdicts at once '
      'so two mistakes are fixed in one pass',
      (t) async {
        final tariffStore = InMemoryTariffStore();
        await _pumpMeter(
          t,
          tariffStore: tariffStore,
          location: FakeLocationSource(),
        );

        await t.enterText(_waitField(), 'гурван зуу');
        await t.enterText(_durationField(), 'зуу');
        await t.tap(find.text('Хадгалах'));
        await t.pumpAndSettle();

        // One verdict per box, all three in one pass: a driver who typed
        // three prices as words must not be sent back three times.
        expect(find.text('Зөв тоо оруулна уу (жишээ нь 1000)'), findsOneWidget);
        expect(find.text('Зөв тоо оруулна уу (жишээ нь 300)'), findsOneWidget);
        expect(find.text('Зөв тоо оруулна уу (жишээ нь 100)'), findsOneWidget);
        expect(await tariffStore.load(), isNull);
      },
    );

    testWidgets('reopens both rates prefilled, with a free waiting rate '
        'left blank rather than shown as a 0 nobody typed', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location, waitTariffMntPerMinute: 0);

      await t.tap(
        find.text('Тариф: ${groupedMnt(_kmTariff)}\u00A0₮/км — засах'),
      );
      await t.pumpAndSettle();

      expect(t.widget<TextField>(_kmField()).controller?.text, '$_kmTariff');
      expect(t.widget<TextField>(_waitField()).controller?.text, isEmpty);
      expect(t.widget<TextField>(_durationField()).controller?.text, isEmpty);
    });
  });

  group('idle step', () {
    testWidgets('states the waiting rate beside the km rate, so a mistyped '
        'one is noticed before the trip and not after it', (t) async {
      await _pumpIdleMeter(t, FakeLocationSource());

      expect(
        find.text('Тариф: ${groupedMnt(_kmTariff)}\u00A0₮/км — засах'),
        findsOneWidget,
      );
      expect(
        find.text('Зогсолт: ${groupedMnt(_waitTariff)}\u00A0₮/мин — засах'),
        findsOneWidget,
      );

      // Either pill reaches the same edit step -- the two rates are typed
      // on one screen, so both are entry points to it.
      await t.tap(
        find.text('Зогсолт: ${groupedMnt(_waitTariff)}\u00A0₮/мин — засах'),
      );
      await t.pumpAndSettle();
      expect(find.text('Түгжрэл/зогсолт (₮/мин)'), findsOneWidget);
    });

    testWidgets(
      'qualifies the pre-trip estimate as distance-only: what a trip will '
      'spend stopped is exactly what cannot be known before it starts',
      (t) async {
        final location = FakeLocationSource();
        await _pumpIdleMeter(t, location);

        expect(
          find.text(
            'Түгжрэлд зогсвол зогсолтын хөлс нэмэгдэнэ — '
            'урьдчилсан тооцоонд ороогүй.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('drops the waiting caveat when waiting is free -- there is '
        'nothing for traffic to add', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location, waitTariffMntPerMinute: 0);

      expect(
        find.text(
          'Түгжрэлд зогсвол зогсолтын хөлс нэмэгдэнэ — '
          'урьдчилсан тооцоонд ороогүй.',
        ),
        findsNothing,
      );
      expect(find.text('Зогсолт: 0\u00A0₮/мин — засах'), findsOneWidget);
    });
  });

  group('running step', () {
    testWidgets(
      'while stopped the distance does not move and the waiting fare does: '
      'GPS drift at a standstill is not travel, and billing it as well as '
      'the wait would charge one stop twice',
      (t) async {
        final location = FakeLocationSource();
        await _pumpIdleMeter(t, location);
        await _startRun(t);

        final second = _jitteredFrom(_start, seconds: 10);
        final third = _jitteredFrom(second, seconds: 60);
        await _feed(t, location, _start);
        await _feed(t, location, second);
        await _feed(t, location, third);

        // 70 seconds waited, charged by the second (fare_calc.dart).
        final waitingFare = computeWaitingFareMnt(
          mntPerMinute: _waitTariff,
          waitingSeconds: 70,
        );
        expect(waitingFare, greaterThan(0));

        expect(find.text('Хүлээж байна'), findsOneWidget);
        expect(find.text('Явж байна'), findsNothing);
        expect(find.text('${groupedMnt(waitingFare)}\u00A0₮'), findsOneWidget);
        expect(
          find.text('Зогсолт ${groupedMnt(waitingFare)}\u00A0₮'),
          findsOneWidget,
        );
        expect(find.text('1 мин зогссон'), findsOneWidget);
        expect(
          find.text('0.0 км'),
          findsOneWidget,
          reason: 'jitter accumulated as distance is the double charge',
        );
      },
    );

    testWidgets(
      'while travelling the waiting side stays at zero -- the two meters '
      'never run at once',
      (t) async {
        final location = FakeLocationSource();
        await _pumpIdleMeter(t, location);
        await _startRun(t);

        final second = _movedFrom(_start, seconds: 10);
        final third = _movedFrom(second, seconds: 10);
        await _feed(t, location, _start);
        await _feed(t, location, second);
        await _feed(t, location, third);

        final distance = trackDistanceMeters([_start, second, third]);
        final fare = computeFareMnt(
          mntPerKm: _kmTariff,
          distanceMeters: distance,
        );

        expect(find.text('Явж байна'), findsOneWidget);
        expect(find.text('Хүлээж байна'), findsNothing);
        expect(find.text('${groupedMnt(fare)}\u00A0₮'), findsOneWidget);
        expect(find.text('Зогсолт 0\u00A0₮'), findsOneWidget);
        expect(find.text('0 мин зогссон'), findsOneWidget);
      },
    );

    testWidgets('pausing stops both meters at once, and only after the driver '
        'confirms -- a stray tap on a screen held while driving must not '
        'silently stop the fare', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);
      await _startRun(t);

      final second = _movedFrom(_start, seconds: 10);
      await _feed(t, location, _start);
      await _feed(t, location, second);

      final fare = computeFareMnt(
        mntPerKm: _kmTariff,
        distanceMeters: trackDistanceMeters([_start, second]),
      );
      expect(fare, greaterThan(0));
      expect(find.text('${groupedMnt(fare)}\u00A0₮'), findsOneWidget);

      // Opening the dialog and backing out changes nothing.
      await t.tap(find.widgetWithText(TextButton, 'Түр зогсоох'));
      await t.pumpAndSettle();
      await t.tap(find.text('Цуцлах'));
      await t.pumpAndSettle();
      expect(find.text('Түр зогссон'), findsNothing);

      await _pauseAndConfirm(t);

      // One travelling and one stopped segment after the pause: neither
      // may reach either meter. (The segment straddling the pause is
      // discarded by `MeterSession`, hence three fixes rather than two.)
      final third = _movedFrom(second, seconds: 10);
      final fourth = _movedFrom(third, seconds: 10);
      final fifth = _jitteredFrom(fourth, seconds: 60);
      await _feed(t, location, third);
      await _feed(t, location, fourth);
      await _feed(t, location, fifth);

      expect(find.text('${groupedMnt(fare)}\u00A0₮'), findsOneWidget);
      expect(find.text('Зогсолт 0\u00A0₮'), findsOneWidget);
      expect(find.text('0 мин зогссон'), findsOneWidget);

      // Resuming needs no second confirmation: a meter that is off costs
      // the driver money for every second it stays off.
      await t.tap(find.widgetWithText(PrimaryButton, 'Үргэлжлүүлэх'));
      await t.pumpAndSettle();
      expect(find.text('Түр зогссон'), findsNothing);
    });

    testWidgets(
      'a paused meter looks unmistakably stopped: the live figure goes '
      'muted, the mode says so, and the loud button offers to start it '
      'again rather than to end the trip',
      (t) async {
        final location = FakeLocationSource();
        await _pumpIdleMeter(t, location);
        await _startRun(t);

        final second = _movedFrom(_start, seconds: 10);
        await _feed(t, location, _start);
        await _feed(t, location, second);
        final fare = computeFareMnt(
          mntPerKm: _kmTariff,
          distanceMeters: trackDistanceMeters([_start, second]),
        );

        final surfaces = TakhiSurfaces.of(
          t.element(find.byType(PrimaryButton)),
        );
        expect(_fareColour(t, fare), surfaces.onSheet);

        await _pauseAndConfirm(t);

        expect(find.text('Түр зогссон'), findsOneWidget);
        expect(find.text('Явж байна'), findsNothing);
        expect(find.text('Хүлээж байна'), findsNothing);
        expect(
          _fareColour(t, fare),
          surfaces.muted,
          reason: 'a live-looking number on a stopped meter is a lie',
        );

        // Finishing stays reachable while paused -- a trip that ended
        // during a stop must not force the driver to restart the meter
        // first -- but it is no longer the emphasised button.
        expect(
          find.widgetWithText(PrimaryButton, 'Үргэлжлүүлэх'),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextButton, 'Дуусгах'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps the pause control a full-thumb target inside the sheet, and '
      'the mode badge a chip rather than a banner across it',
      (t) async {
        final location = FakeLocationSource();
        await _pumpIdleMeter(t, location);
        await _startRun(t);
        await _feed(t, location, _start);
        await _feed(t, location, _movedFrom(_start, seconds: 10));

        final sheet = t.getRect(find.byType(TakhiSheet));
        final pause = t.getRect(find.widgetWithText(TextButton, 'Түр зогсоох'));
        expect(pause.height, greaterThanOrEqualTo(TakhiTouch.minTarget));
        expect(
          pause.top,
          greaterThan(sheet.top),
          reason: 'a control over the map is a control a resting thumb hits',
        );

        final badge = t.getRect(find.widgetWithText(InfoChip, 'Явж байна'));
        expect(
          badge.width,
          lessThan(sheet.width / 2),
          reason: 'stretched to the sheet it stops reading as a chip',
        );
      },
    );

    testWidgets(
      'fits a small phone: the sheet now carries a mode badge, a waiting '
      'pair and two buttons above the map, and none of it may overflow the '
      'one screen a driver reads at a junction',
      (t) async {
        // 360x640 logical pixels -- the small end of the Android phones this
        // app is actually driven on, and well under the 800x600 the test
        // binding defaults to.
        await t.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => t.binding.setSurfaceSize(null));

        final location = FakeLocationSource();
        await _pumpIdleMeter(t, location);
        await _startRun(t);
        await _feed(t, location, _start);
        await _feed(t, location, _jitteredFrom(_start, seconds: 70));

        expect(t.takeException(), isNull);
        expect(find.text('Хүлээж байна'), findsOneWidget);
        expect(find.widgetWithText(PrimaryButton, 'Дуусгах'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Түр зогсоох'), findsOneWidget);

        await _pauseAndConfirm(t);
        expect(t.takeException(), isNull);
        expect(find.text('Түр зогссон'), findsOneWidget);

        // And the breakdown the passenger reads afterwards, whose row
        // labels are the longest Cyrillic strings on the screen.
        await t.tap(find.widgetWithText(TextButton, 'Дуусгах'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Нийт'), findsOneWidget);
        expect(find.text('Зогсолтын хугацаа'), findsOneWidget);
      },
    );

    testWidgets('hides the waiting readout when waiting is free -- an '
        'always-zero row is noise on the one screen read while driving', (
      t,
    ) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location, waitTariffMntPerMinute: 0);
      await _startRun(t);

      await _feed(t, location, _start);
      await _feed(t, location, _jitteredFrom(_start, seconds: 10));

      expect(find.text('Зогсолт 0\u00A0₮'), findsNothing);
      expect(find.text('0 мин зогссон'), findsNothing);
      // The mode still shows: "why is the number not moving?" is exactly
      // the question a free wait raises.
      expect(find.text('Хүлээж байна'), findsOneWidget);
    });
  });

  group('finished step', () {
    testWidgets(
      'breaks the total into distance, waiting and the sum of the two, so a '
      'passenger can check the arithmetic instead of taking it on trust',
      (t) async {
        final location = FakeLocationSource();
        final journal = InMemoryMeterJournalStore();
        await _pumpIdleMeter(t, location, journal: journal);
        await _startRun(t);

        // One travelling leg, then a full minute stopped.
        final second = _movedFrom(_start, seconds: 10);
        final third = _jitteredFrom(second, seconds: 60);
        await _feed(t, location, _start);
        await _feed(t, location, second);
        await _feed(t, location, third);

        await t.tap(find.widgetWithText(PrimaryButton, 'Дуусгах'));
        await t.pumpAndSettle();

        final distance = trackDistanceMeters([_start, second]);
        final distanceFare = computeFareMnt(
          mntPerKm: _kmTariff,
          distanceMeters: distance,
        );
        final waitingFare = computeWaitingFareMnt(
          mntPerMinute: _waitTariff,
          waitingSeconds: 60,
        );
        final total = distanceFare + waitingFare;

        final entry = (await journal.loadAll()).single;
        expect(entry.distanceFareMnt, distanceFare);
        expect(entry.waitingFareMnt, waitingFare);
        expect(entry.fareMnt, total);

        expect(find.text('Замын хөлс'), findsOneWidget);
        expect(find.text('${groupedMnt(distanceFare)}\u00A0₮'), findsOneWidget);
        expect(find.text('Зогсолтын хөлс'), findsOneWidget);
        expect(find.text('${groupedMnt(waitingFare)}\u00A0₮'), findsOneWidget);
        expect(find.text('Зогсолтын хугацаа'), findsOneWidget);
        expect(find.text('1 мин'), findsOneWidget);
        expect(find.text('Нийт'), findsOneWidget);
        // Twice: the headline figure and the row that closes the sum.
        expect(find.text('${groupedMnt(total)}\u00A0₮'), findsNWidgets(2));
        // The km arithmetic now explains the distance row only.
        expect(
          find.text(
            '${(distance / 1000).toStringAsFixed(1)} км × '
            '${groupedMnt(_kmTariff)}\u00A0₮/км',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('leaves the waiting rows off a run that never stopped, '
        'rather than printing two zeroes to be queried', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);
      await _startRun(t);

      final second = _movedFrom(_start, seconds: 10);
      await _feed(t, location, _start);
      await _feed(t, location, second);

      await t.tap(find.widgetWithText(PrimaryButton, 'Дуусгах'));
      await t.pumpAndSettle();

      expect(find.text('Зогсолтын хөлс'), findsNothing);
      expect(find.text('Зогсолтын хугацаа'), findsNothing);
      expect(find.text('Замын хөлс'), findsOneWidget);
      expect(find.text('Нийт'), findsOneWidget);
    });
  });
}
