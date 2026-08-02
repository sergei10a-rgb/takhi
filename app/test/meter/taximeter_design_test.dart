// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_track.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/location_picker.dart';
import 'package:takhi/map/ride_map.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/payment/driver_qr_display.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/info_chip.dart';
import 'package:takhi/widgets/pill_field.dart';
import 'package:takhi/widgets/primary_button.dart';
import 'package:takhi/widgets/qr_card.dart';
import 'package:takhi/widgets/section_heading.dart';
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

/// In-memory [DriverQrStore]: the finished step renders [DriverQrDisplay],
/// which would otherwise reach `path_provider`'s real platform channel.
class _FakeDriverQrStore implements DriverQrStore {
  Uint8List? _bytes;

  @override
  Future<void> save(Uint8List pngBytes) async => _bytes = pngBytes;

  @override
  Future<Uint8List?> load() async => _bytes;

  @override
  Future<void> clear() async => _bytes = null;
}

const _fix1 = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);
const _fix2 = GpsFix(lat: 47.9196, lon: 106.9176, timestampSeconds: 1010);
const _fix3 = GpsFix(lat: 47.9206, lon: 106.9176, timestampSeconds: 1020);

const _tariff = 1000;

/// The kilometre figure the screen is expected to print for [meters] --
/// one decimal, because a driver reading a nine-digit fraction at a
/// junction is reading nothing at all.
String _km(int meters) => (meters / 1000).toStringAsFixed(1);

/// A driver who has saved a bank QR.
///
/// A 1x1 PNG is enough: nothing here reads the picture, only whether one
/// exists — which is what decides whether the app's own invitation code may
/// appear beside it on the payment screen.
DriverQrStore _qrStoreWithCode() {
  final store = _FakeDriverQrStore();
  store.save(
    Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]),
  );
  return store;
}

Future<void> _pumpMeter(
  WidgetTester t, {
  required TariffStore tariffStore,
  required FakeLocationSource location,
  MeterJournalStore? journal,
  Brightness brightness = Brightness.light,
  DriverQrStore? qrStore,
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
        driverQrStoreProvider.overrideWithValue(
          qrStore ?? _FakeDriverQrStore(),
        ),
      ],
      child: MaterialApp(
        theme: takhiTheme(brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const TaximeterPage(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// Pumps a meter that already has a tariff, so it opens on the idle step.
Future<void> _pumpIdleMeter(
  WidgetTester t,
  FakeLocationSource location, {
  Brightness brightness = Brightness.light,
  MeterJournalStore? journal,
  DriverQrStore? qrStore,
}) async {
  final tariffStore = InMemoryTariffStore();
  await tariffStore.save(DriverTariff(mntPerKm: _tariff));
  await _pumpMeter(
    t,
    tariffStore: tariffStore,
    location: location,
    journal: journal,
    brightness: brightness,
    qrStore: qrStore,
  );
}

/// Idle -> running, with three fixes' worth of distance on the clock.
Future<void> _runThreeFixes(WidgetTester t, FakeLocationSource location) async {
  await t.tap(find.text('Эхлүүл'));
  await t.pumpAndSettle();
  for (final fix in [_fix1, _fix2, _fix3]) {
    location.emit(fix);
    // Two pumps: `RideMap`'s polyline layer needs an extra frame on some
    // transitions (see `taximeter_page_test.dart`).
    await t.pump();
    await t.pump();
  }
}

/// Runs [body] once per brightness. Every step of this screen has to hold up
/// at night as well as in the sun, and the dark surfaces are not the light
/// ones inverted -- mirrors `widgets/design_system_test.dart`'s own helper.
void forBothBrightnesses(
  String description,
  Future<void> Function(WidgetTester t, Brightness brightness) body,
) {
  for (final brightness in Brightness.values) {
    testWidgets('$description (${brightness.name})', (t) async {
      await body(t, brightness);
      expect(t.takeException(), isNull);
    });
  }
}

void main() {
  group('tariff step', () {
    testWidgets('takes the rates in PillFields under a heading that says '
        'what the numbers are for', (t) async {
      await _pumpMeter(
        t,
        tariffStore: InMemoryTariffStore(),
        location: FakeLocationSource(),
      );

      expect(find.byType(SectionHeading), findsOneWidget);
      // The heading has to describe the whole form, not one of its boxes.
      // It read «Км-ийн үнээ тохируул» / «Тоолуур явсан зайг энэ үнээр
      // бодно.» while three independent prices sat underneath it -- telling
      // a driver the screen sets the km price and nothing else.
      expect(find.text('Үнээ тохируул'), findsOneWidget);
      expect(
        find.text(
          'Тоолуур эдгээр үнээр бодно. Аль нэгийг хоосон эсвэл 0 орхивол '
          'тэр хөлс бодогдохгүй.',
        ),
        findsOneWidget,
      );
      // Five capsules: the km rate, the waiting rate, the trip-duration
      // rate, the street flag-fall and the booked-ride base fare. They are
      // one decision -- what this driver charges -- so they are typed on
      // one screen rather than split across five. And every charge being
      // visible on that screen is the point: the one that was missing from
      // it cost a driver 2,850₮ on a single ride.
      expect(find.byType(PillField), findsNWidgets(5));
      expect(find.byType(PrimaryButton), findsOneWidget);
    });

    testWidgets(
      'keeps the field label on screen while the field holds a value -- a '
      'floating Material label disappears exactly when the driver wants to '
      'check whether 15000 is the per-km rate or the whole fare',
      (t) async {
        final tariffStore = InMemoryTariffStore();
        await tariffStore.save(DriverTariff(mntPerKm: 1500));
        await _pumpMeter(
          t,
          tariffStore: tariffStore,
          location: FakeLocationSource(),
        );

        await t.tap(find.text('Замын хөлс'));
        await t.pumpAndSettle();

        expect(
          t.widget<TextField>(find.byType(TextField).first).controller?.text,
          '1500',
        );
        expect(find.text('1 км-ийн үнэ (₮)'), findsOneWidget);
      },
    );

    testWidgets('states a refused rate in the error colour, under the field', (
      t,
    ) async {
      await _pumpMeter(
        t,
        tariffStore: InMemoryTariffStore(),
        location: FakeLocationSource(),
      );

      // Cleared first: the form opens prefilled since v0.4.0, so a save
      // with an untouched km box now succeeds and there is no verdict to
      // read the colour of.
      await t.enterText(find.byType(TextField).first, '');
      await t.tap(find.text('Хадгалах'));
      await t.pumpAndSettle();

      final error = t.widget<Text>(
        find.text('Зөв тоо оруулна уу (жишээ нь 1000)'),
      );
      final scheme = Theme.of(
        t.element(find.byType(PillField).first),
      ).colorScheme;
      expect(error.style?.color, scheme.error);
    });
  });

  group('idle step', () {
    testWidgets(
      'puts the destination behind a tappable pill instead of an always-on '
      'map -- the driver is parked and looking at the start button',
      (t) async {
        await _pumpIdleMeter(t, FakeLocationSource());

        expect(find.text('Аялалд бэлэн'), findsOneWidget);
        expect(find.byType(TakhiSheet), findsOneWidget);
        expect(find.byType(PillField), findsOneWidget);
        expect(find.text('Очих газраа сонгох'), findsOneWidget);
        expect(find.byType(LocationPickerField), findsNothing);

        await t.tap(find.byType(PillField));
        await t.pumpAndSettle();

        expect(find.byType(LocationPickerField), findsOneWidget);
      },
    );

    testWidgets('shows the landmark the driver typed on the pill once the '
        'picker is closed', (t) async {
      await _pumpIdleMeter(t, FakeLocationSource());

      await t.tap(find.byType(PillField));
      await t.pumpAndSettle();
      final onChanged = t
          .widget<LocationPickerField>(find.byType(LocationPickerField))
          .onChanged;
      onChanged(
        const PickedLocation(
          lat: 47.92,
          lon: 106.92,
          landmarkText: 'Их дэлгүүр',
        ),
      );
      await t.pump(const Duration(milliseconds: 700));
      await t.tap(find.text('Болсон'));
      await t.pumpAndSettle();

      expect(find.byType(LocationPickerField), findsNothing);
      expect(find.text('Их дэлгүүр'), findsOneWidget);
    });

    testWidgets('renders a settled estimate as chips rather than a loose '
        'line of body text', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);

      await t.tap(find.byType(PillField));
      await t.pumpAndSettle();
      final onChanged = t
          .widget<LocationPickerField>(find.byType(LocationPickerField))
          .onChanged;
      onChanged(const PickedLocation(lat: 47.95, lon: 106.95));
      await t.pump(const Duration(milliseconds: 700));
      await t.pump();
      location.emit(_fix1);
      await t.pumpAndSettle();

      await t.tap(find.text('Болсон'));
      await t.pumpAndSettle();

      // The offline client always throws, so this estimate is the
      // straight-line fallback and must say so.
      final chips = t.widgetList<InfoChip>(find.byType(InfoChip)).toList();
      expect(chips, hasLength(2));
      expect(
        chips.map((c) => c.label),
        contains('ойролцоогоор'),
        reason: 'an approximate estimate must keep saying it is one',
      );
      expect(find.byType(InfoChip), findsNWidgets(2));
    });

    testWidgets('gives the start button the full width of the sheet and a '
        'generous height', (t) async {
      await _pumpIdleMeter(t, FakeLocationSource());

      final button = t.getRect(find.byType(PrimaryButton));
      expect(button.height, greaterThanOrEqualTo(TakhiTouch.minTarget));
      final sheet = t.getRect(find.byType(TakhiSheet));
      expect(button.width, greaterThan(sheet.width / 2));
    });
  });

  group('running step', () {
    testWidgets(
      'prints the fare in the tabular display face -- the one number a '
      'driver reads at speed',
      (t) async {
        final location = FakeLocationSource();
        await _pumpIdleMeter(t, location);
        await _runThreeFixes(t, location);

        final fare = computeFareMnt(
          mntPerKm: _tariff,
          distanceMeters: trackDistanceMeters([_fix1, _fix2, _fix3]),
        );
        final text = t.widget<Text>(find.text('${groupedMnt(fare)}\u00A0₮'));
        expect(text.style?.fontSize, TakhiType.meterHeadline.fontSize);
        expect(text.style?.fontWeight, TakhiType.meterHeadline.fontWeight);
        expect(
          text.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'proportional digits reflow the number under the eye',
        );
      },
    );

    testWidgets('sets distance and duration below the fare, secondary but '
        'still in the numeric face', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);
      await _runThreeFixes(t, location);

      final distance = trackDistanceMeters([_fix1, _fix2, _fix3]);
      final km = t.widget<Text>(find.text('${_km(distance)} км'));
      expect(km.style?.fontSize, TakhiType.numeric.fontSize);
      expect(
        km.style!.fontSize!,
        lessThan(TakhiType.meterHeadline.fontSize!),
        reason: 'the fare has to win the glance',
      );
      expect(find.text('0 мин'), findsOneWidget);
    });

    testWidgets('rounds the kilometre figure to one decimal instead of '
        'printing the raw GPS fraction', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);
      await _runThreeFixes(t, location);

      final distance = trackDistanceMeters([_fix1, _fix2, _fix3]);
      expect(
        '${distance / 1000}',
        isNot(_km(distance)),
        reason:
            'the fixture must actually produce a long fraction, or this '
            'test proves nothing',
      );
      expect(find.text('${distance / 1000} км'), findsNothing);
      expect(find.text('${_km(distance)} км'), findsOneWidget);
    });

    testWidgets('floats the sheet over a full-bleed map rather than '
        'stacking the two', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);
      await _runThreeFixes(t, location);

      final map = t.getRect(find.byType(RideMap));
      final sheet = t.getRect(find.byType(TakhiSheet));
      expect(
        sheet.bottom,
        closeTo(map.bottom, 0.5),
        reason: 'a Column would end the map where the sheet starts',
      );
      expect(map.top, lessThan(sheet.top));
    });

    testWidgets('never animates the live number: a fare that cross-fades is '
        'a fare nobody can read', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);

      await t.tap(find.text('Эхлүүл'));
      await t.pumpAndSettle();
      expect(find.text('0\u00A0₮'), findsOneWidget);

      location.emit(_fix1);
      await t.pump();
      await t.pump();
      location.emit(_fix2);
      await t.pump();
      await t.pump();

      final grown = computeFareMnt(
        mntPerKm: _tariff,
        distanceMeters: trackDistanceMeters([_fix1, _fix2]),
      );
      expect(grown, greaterThan(0));
      expect(find.text('${groupedMnt(grown)}\u00A0₮'), findsOneWidget);
      expect(
        find.text('0\u00A0₮'),
        findsNothing,
        reason: 'the previous value must be gone the same frame, not fading',
      );
    });

    testWidgets('keeps the finish button large and away from the map, so a '
        'thumb resting on the screen cannot end a run', (t) async {
      final location = FakeLocationSource();
      await _pumpIdleMeter(t, location);
      await _runThreeFixes(t, location);

      final button = t.getRect(find.widgetWithText(PrimaryButton, 'Дуусгах'));
      expect(button.height, greaterThanOrEqualTo(TakhiTouch.minTarget));
      final sheet = t.getRect(find.byType(TakhiSheet));
      expect(button.top, greaterThan(sheet.top));
    });
  });

  group('finished step', () {
    Future<void> pumpFinished(
      WidgetTester t,
      FakeLocationSource location, {
      Brightness brightness = Brightness.light,
      DriverQrStore? qrStore,
    }) async {
      await _pumpIdleMeter(
        t,
        location,
        brightness: brightness,
        qrStore: qrStore,
      );
      await _runThreeFixes(t, location);
      await t.tap(find.text('Дуусгах'));
      await t.pumpAndSettle();
    }

    testWidgets('leads with the total and explains it underneath', (t) async {
      final location = FakeLocationSource();
      await pumpFinished(t, location);

      final distance = trackDistanceMeters([_fix1, _fix2, _fix3]);
      final fare = computeFareMnt(mntPerKm: _tariff, distanceMeters: distance);
      expect(find.text('Аяллын дүн'), findsOneWidget);
      // Twice on screen: the headline figure, and the row that closes the
      // breakdown underneath it. `.first` is the headline -- the one this
      // check is about.
      final total = t.widget<Text>(
        find.text('${groupedMnt(fare)}\u00A0₮').first,
      );
      expect(total.style?.fontSize, TakhiType.numericDisplay.fontSize);
      expect(
        find.text('${_km(distance)} км × ${groupedMnt(_tariff)}\u00A0₮/км'),
        findsOneWidget,
        reason: 'a passenger who queries the fare needs the arithmetic',
      );
    });

    testWidgets('gives the payment section its own heading and puts the '
        'bank QR on a light plate a camera can read', (t) async {
      final location = FakeLocationSource();
      await pumpFinished(t, location);

      expect(find.text('Төлбөр'), findsOneWidget);
      expect(
        find.text('Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү'),
        findsOneWidget,
      );
      expect(find.byType(DriverQrDisplay), findsOneWidget);
      // Absent, and deliberately: this driver has no bank QR saved, so the
      // app's own invitation code would be the only scannable thing on a
      // screen headed «Төлбөр» — and a passenger holding out their phone
      // to pay would install Takhi instead of paying.
      expect(find.text('Тахь — эзэнгүй такси'), findsNothing);
    });

    testWidgets('puts the bank QR on a light plate a camera can read', (
      t,
    ) async {
      final location = FakeLocationSource();
      await pumpFinished(t, location, qrStore: _qrStoreWithCode());

      final plate = t.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(QrCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((plate.decoration as BoxDecoration).color, Colors.white);
    });

    testWidgets('keeps the QR plate white in the dark theme -- a scanner '
        'reads the plate, not the theme', (t) async {
      final location = FakeLocationSource();
      await pumpFinished(
        t,
        location,
        brightness: Brightness.dark,
        qrStore: _qrStoreWithCode(),
      );

      final plate = t.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(QrCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((plate.decoration as BoxDecoration).color, Colors.white);
    });
  });

  group('step transitions', () {
    testWidgets('cross-fade for a token duration inside the 150-300ms band', (
      t,
    ) async {
      await _pumpIdleMeter(t, FakeLocationSource());

      final durations = t
          .widgetList<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
          .map((s) => s.duration);
      expect(durations, contains(TakhiMotion.normal));
      expect(TakhiMotion.normal.inMilliseconds, inInclusiveRange(150, 300));
    });
  });

  forBothBrightnesses('every step renders', (t, brightness) async {
    final location = FakeLocationSource();
    final tariffStore = InMemoryTariffStore();
    await _pumpMeter(
      t,
      tariffStore: tariffStore,
      location: location,
      brightness: brightness,
    );

    // Tariff -> idle.
    await t.enterText(find.byType(TextField).first, '$_tariff');
    await t.tap(find.text('Хадгалах'));
    await t.pumpAndSettle();
    expect(find.text('Аялалд бэлэн'), findsOneWidget);

    // Idle -> running.
    await _runThreeFixes(t, location);
    expect(find.byType(RideMap), findsOneWidget);

    // Running -> finished.
    await t.tap(find.text('Дуусгах'));
    await t.pumpAndSettle();
    expect(find.text('Аяллын дүн'), findsOneWidget);
  });
}
