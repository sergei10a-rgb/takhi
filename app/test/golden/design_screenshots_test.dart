// SPDX-License-Identifier: AGPL-3.0-or-later

/// Design screenshots, not a verification test.
///
/// Nothing in this file asserts anything about the app. It exists to produce
/// **PNG pictures of real screens** that a human can look at, because there is
/// no other way to see this app: the plugins it depends on (geolocator,
/// flutter_secure_storage, flutter_webrtc, ...) have no web implementation, so
/// `flutter run -d chrome` cannot boot it, and there is no emulator on this
/// machine. Flutter's own widget renderer is therefore the only renderer
/// available — `matchesGoldenFile` is being used here as a screenshot tool,
/// with `--update-goldens` as the shutter.
///
/// Because of that, these are **excluded from the ordinary test run**: every
/// case is tagged `golden`, and `dart_test.yaml` marks that tag skipped, so a
/// plain `flutter test` neither runs nor fails on them. Pixel output differs
/// between platforms and Flutter versions, so treating them as assertions
/// would turn every framework bump into a red suite.
///
/// The tag is applied per case (`tags: _kGoldenTag`) rather than as a
/// library-level `@Tags(['golden'])`, which would be tidier but does not
/// compile here: `flutter_test` does not re-export `Tags`, so the annotation
/// would mean adding `test_api` to `dev_dependencies` and eating a
/// `depend_on_referenced_packages` lint. The runner treats the two the same.
///
/// ## Regenerating the pictures
///
/// ```sh
/// cd app
/// flutter test --update-goldens --run-skipped \
///     test/golden/design_screenshots_test.dart --concurrency=1
/// ```
///
/// `--run-skipped` is what defeats the `dart_test.yaml` skip; `--concurrency=1`
/// avoids the socket flakiness this repo sees on Windows. The PNGs land in
/// `test/golden/images/`. To *view* the current set without touching it, drop
/// `--update-goldens` — but expect failures if the host differs from the
/// machine that last wrote them, which is exactly why they are not assertions.
///
/// ## What is real here and what is staged
///
/// * The widgets are the production ones — `HomePage` and `TaximeterPage` are
///   imported and pumped, not reimplemented. Nothing under `lib/` is touched.
/// * The type is the real bundled NotoSans, loaded through [FontLoader] the
///   same way `test/typography_weight_test.dart` does it. Without that, every
///   glyph renders as a filled box (the test renderer's fallback face) and the
///   pictures would be worthless.
/// * The **numbers are staged**, deliberately. A meter fed no GPS reads 0₮ /
///   0.0 км, which shows nothing about the design, so the running and finished
///   steps are driven by a scripted eight-kilometre route (see [_kRunRoute]).
///   The figures on screen are what the production fare/distance code computes
///   from those fixes — they are not painted on.
/// * The **map tiles are genuinely absent**. `RideMap` is the real widget and
///   it really does lay out and paint; `flutter_test` blocks its HTTP tile
///   fetches, so it paints flutter_map's own empty-canvas colour. The map
///   *area* is therefore honest about its position and size, and blank about
///   its content. No stub was substituted.
/// * The finished step's duration chip reads `0 мин`. That figure comes from
///   `DateTime.now()` inside `TaximeterPage._finish`, i.e. wall-clock time
///   between two taps in the same test — there is no seam to inject a clock
///   through, and inventing one would mean editing production code.
/// * The estimate chip used to read `≈ 9 322 ₮` and photographed as
///   `▯ 9 322 ₮`: U+2248 is genuinely absent from the bundled
///   `NotoSans-Regular.ttf` subset. That was written off here as a
///   limitation of the picture, on the grounds that a device's font
///   fallback would supply the glyph — which is exactly the reasoning that
///   let «Түр зогсоох» ship as `▯▯▯ ▯▯▯▯▯▯▯`. The screen carries the word
///   «Урьдчилсан» now instead; `app/test/font_coverage_test.dart` checks
///   every string in both `.arb` files against the bundled font's cmap, so
///   the next character nobody's face has cannot get in by the same door.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/home/home_page.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/location_picker.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/payment/driver_qr_display.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/safety/emergency_contact_store.dart';
import 'package:takhi/safety/safety_providers.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/pill_field.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// The tag `dart_test.yaml` skips. Every case here carries it.
const _kGoldenTag = 'golden';

/// A modern handset's logical size (iPhone 14 / Pixel 7 class). Not the test
/// binding's 800x600 default, which is a tablet nobody holds and which lets
/// the sheet sprawl in a way no rider ever sees.
const _kLogicalSize = Size(390, 844);

/// Written into the pictures: at 1.0 the PNGs would be 390px wide and every
/// hairline, radius and letterform would be judged at half the density a
/// phone actually shows.
const _kDevicePixelRatio = 2.0;

/// Fonts the pictures need, family -> asset key in the test bundle.
///
/// NotoSans is the app's own bundled face (`pubspec.yaml`); MaterialIcons is
/// the one Flutter ships, which every `Icon` in the app resolves against.
/// Neither is registered by default in a widget test, and an unregistered
/// family falls back to the test renderer's blank face — filled rectangles
/// where the text and glyphs should be.
const _kFonts = <String, String>{
  'NotoSans': 'assets/fonts/NotoSans-Regular.ttf',
  'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
};

/// The two cuts of the brand mark `HomeTopBar` picks between, one per
/// brightness (see `home/home_top_bar.dart`). Named here because the picture
/// has to warm the image cache with the *same* file the widget will ask for.
const _kBrandMarkLight = 'assets/brand/takhi_horse_ink.png';
const _kBrandMarkDark = 'assets/brand/takhi_horse_gold.png';

/// The rate the staged meter runs are metered at.
const _kTariffMntPerKm = 1500;

/// A scripted cross-town run: five legs, roughly 8.3 km, over 862 seconds.
///
/// Chosen so the running step reads like a real fare rather than a zero —
/// 8.3 км at [_kTariffMntPerKm] comes out near 12 450₮, and 862s reads as
/// `14 мин`. The legs alternate north and east so the polyline drawn over the
/// map has corners in it instead of being one straight line.
const _kRunRoute = <GpsFix>[
  GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000),
  GpsFix(lat: 47.9276, lon: 106.9176, timestampSeconds: 1120),
  GpsFix(lat: 47.9276, lon: 106.9444, timestampSeconds: 1360),
  GpsFix(lat: 47.9411, lon: 106.9444, timestampSeconds: 1540),
  GpsFix(lat: 47.9411, lon: 106.9779, timestampSeconds: 1780),
  GpsFix(lat: 47.9528, lon: 106.9779, timestampSeconds: 1862),
];

/// Where the staged rider is standing on the home screen.
const _kPickupFix = GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000);

/// Where the staged meter trip is headed — far enough out that the offline
/// estimate is a four-figure number worth looking at.
const _kDestination = PickedLocation(
  lat: 47.9600,
  lon: 106.9176,
  landmarkText: 'Их дэлгүүр',
);

/// Stand-in payload for the driver's saved bank QR. Deliberately not a real
/// bank string: this renders into a picture that gets shown to people.
const _kSampleBankQrPayload = 'takhi:demo-driver-qr';

/// BIP-39's all-zero test vector, the same seed the onboarding tests use.
///
/// Restored rather than minted: `IdentityService.createNew` draws fresh
/// entropy, so the npub chip on home would read differently on every run and
/// the two home pictures would never be reproducible — every regeneration
/// would show a diff that means nothing.
const _kDemoMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

/// Always throws, so the idle step's estimate deterministically falls back to
/// the offline straight-line guess instead of reaching the public OSRM demo
/// server from a test — same double as `meter/taximeter_design_test.dart`'s.
class _OfflineRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => throw Exception('offline');
}

/// In-memory [DriverQrStore] that can start out already holding a QR, so the
/// finished step paints the driver's code rather than the "not set yet" hint.
/// The real store reads a file through `path_provider`, whose platform channel
/// is absent under `flutter_test`.
class _StubDriverQrStore implements DriverQrStore {
  Uint8List? _bytes;

  _StubDriverQrStore([this._bytes]);

  @override
  Future<void> save(Uint8List pngBytes) async => _bytes = pngBytes;

  @override
  Future<Uint8List?> load() async => _bytes;

  @override
  Future<void> clear() async => _bytes = null;
}

/// Answers `path_provider` with a scratch directory for the whole file.
///
/// `flutter_map`'s tile layer asks for the application cache directory on
/// first build, and that plugin's channel is absent under `flutter_test`, so
/// without this the very first screen that mounts a [RideMap] fails the test
/// with a `MissingPluginException` before it can be photographed. Nothing is
/// ever read back out of the directory here -- the tiles it would cache never
/// download in the first place.
void _stubPathProvider() {
  final scratch = Directory.systemTemp.createTempSync('takhi_golden').path;
  TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => scratch,
      );
}

/// Registers [_kFonts] with the engine for the rest of the file.
Future<void> _loadRealFonts() async {
  for (final font in _kFonts.entries) {
    final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
    await loader.load();
  }
}

/// Puts the test surface on a phone-shaped screen at phone density, and puts
/// it back afterwards so nothing leaks into the next case.
void _useHandsetScreen(WidgetTester t) {
  t.view.physicalSize = _kLogicalSize * _kDevicePixelRatio;
  t.view.devicePixelRatio = _kDevicePixelRatio;
  addTearDown(t.view.reset);
}

/// The app shell every picture is taken through: the same theme, locale and
/// delegates `main.dart` configures, minus the router (none of these screens
/// navigates during a shoot).
Widget _screen(Widget home, Brightness brightness, List<Override> overrides) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: takhiTheme(brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: home,
      ),
    );

/// Label on the throwaway first route the pushed screens open from -- the
/// same device `call_safety_settings_test.dart` uses.
const _kLauncherLabel = 'нүүр';

/// Pumps [page] as a *pushed* route rather than as `home:`.
///
/// Not cosmetic: a `Scaffold`'s `AppBar` grows a back button exactly when the
/// `Navigator` under it can pop. `/meter` is only ever reached from `/home`,
/// so shooting it as the root left `meter_idle_light` and
/// `meter_running_light` without the back arrow that
/// `call_safety_settings_test.dart` -- which pushes the same page -- shows on
/// every other meter picture. Two pictures of one screen disagreeing about
/// its chrome is worse than either being wrong on its own.
Future<void> _pumpPushed(
  WidgetTester t,
  Widget page,
  Brightness brightness,
  List<Override> overrides,
) async {
  await t.pumpWidget(
    _screen(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => page)),
              child: const Text(_kLauncherLabel),
            ),
          ),
        ),
      ),
      brightness,
      overrides,
    ),
  );
  await t.tap(find.text(_kLauncherLabel));
  await t.pumpAndSettle();
}

/// Writes the whole screen to `test/golden/images/<name>.png`.
///
/// The finder is [MaterialApp] on purpose: `matchesGoldenFile` walks up to the
/// nearest repaint boundary, which is the render view, whose paint bounds are
/// already scaled by [_kDevicePixelRatio] — so the file comes out at the
/// device's physical resolution rather than at logical size.
Future<void> _shoot(WidgetTester t, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('images/$name.png'),
);

/// Renders a QR into PNG bytes the way `DriverQrCapturePage` would have saved
/// them. Runs outside the fake-async zone because encoding an image is real
/// asynchronous work the test clock cannot drive.
Future<Uint8List> _sampleBankQrPng(WidgetTester t) async {
  final painter = QrPainter(
    data: _kSampleBankQrPayload,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: TakhiColors.ink,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: TakhiColors.ink,
    ),
  );
  final encoded = await t.runAsync(() => painter.toImageData(480));
  return encoded == null ? Uint8List(0) : encoded.buffer.asUint8List();
}

/// Decodes [bytes] into the image cache so the next frame can paint it.
///
/// `Image.memory` decodes asynchronously, and a widget test's fake clock never
/// lets that finish — without this the driver's QR would be a 240x240 hole.
Future<void> _precacheDriverQr(WidgetTester t, Uint8List bytes) async {
  final context = t.element(find.byType(DriverQrDisplay));
  await t.runAsync(() => precacheImage(MemoryImage(bytes), context));
  await t.pumpAndSettle();
}

/// Home, with an identity in the keystore, relays connected and the rider
/// located — i.e. every row on the sheet carrying a real value rather than a
/// placeholder.
Future<void> _pumpHome(WidgetTester t, Brightness brightness) async {
  final keyStore = InMemoryKeyStore();
  await IdentityService(keyStore).restore(_kDemoMnemonic);
  final location = FakeLocationSource();
  addTearDown(location.dispose);

  await t.pumpWidget(
    _screen(const HomePage(), brightness, [
      keyStoreProvider.overrideWithValue(keyStore),
      relayPoolProvider.overrideWithValue(
        RelayPool(defaultRelayUrls, connect: (_) => FakeRelaySocket()),
      ),
      emergencyContactStoreProvider.overrideWithValue(
        InMemoryEmergencyContactStore(),
      ),
      locationSourceProvider.overrideWithValue(location),
      locationPermissionCheckProvider.overrideWithValue(() async => true),
    ]),
  );
  await t.pumpAndSettle();

  await t.tap(find.byIcon(Icons.my_location));
  await t.pumpAndSettle();
  location.emit(_kPickupFix);
  await t.pumpAndSettle();
  await _precacheBrandMark(t, brightness);
}

/// Decodes the brand mark `HomeTopBar` paints beside the wordmark.
///
/// `Image.asset` decodes on the real clock, which a widget test's fake one
/// never reaches, so without this the pill holds the word «Тахь» and an
/// empty space where the horse belongs -- and the app's two flagship
/// pictures were the only ones in the whole set missing it, while
/// `home_denied_light` and the SOS sheet (whose file already warms the cache
/// this way) had it. Same helper, same reason, as
/// `onboarding_and_identity_test.dart`'s `_precacheAsset`.
Future<void> _precacheBrandMark(WidgetTester t, Brightness brightness) async {
  final asset = brightness == Brightness.dark
      ? _kBrandMarkDark
      : _kBrandMarkLight;
  final context = t.element(find.byType(Scaffold).first);
  await t.runAsync(() => precacheImage(AssetImage(asset), context));
  await t.pumpAndSettle();
}

/// The meter, already holding a tariff, so it opens on the idle step.
Future<void> _pumpMeter(
  WidgetTester t,
  Brightness brightness, {
  required FakeLocationSource location,
  Uint8List? driverQr,
}) async {
  final tariffStore = InMemoryTariffStore();
  await tariffStore.save(const DriverTariff(mntPerKm: _kTariffMntPerKm));

  // Pushed, not `home:` -- `/meter` is reached from `/home` and from nowhere
  // else, so the real screen always has a route under it and an AppBar back
  // button on top of it.
  await _pumpPushed(t, const TaximeterPage(), brightness, [
    tariffStoreProvider.overrideWithValue(tariffStore),
    meterJournalStoreProvider.overrideWithValue(InMemoryMeterJournalStore()),
    routingClientProvider.overrideWithValue(_OfflineRoutingClient()),
    locationSourceProvider.overrideWithValue(location),
    locationPermissionCheckProvider.overrideWithValue(() async => true),
    driverQrStoreProvider.overrideWithValue(_StubDriverQrStore(driverQr)),
  ]);
}

/// Drives the idle step's destination picker to a settled destination, so the
/// pill names a place and the estimate chips appear underneath it.
Future<void> _pickDestination(
  WidgetTester t,
  FakeLocationSource location,
) async {
  await t.tap(find.byType(PillField));
  await t.pumpAndSettle();

  t
      .widget<LocationPickerField>(find.byType(LocationPickerField))
      .onChanged(_kDestination);
  // Past the page's 600ms destination debounce, then a frame for the estimate
  // chain to subscribe before the fix it is waiting on arrives.
  await t.pump(const Duration(milliseconds: 700));
  await t.pump();
  location.emit(_kPickupFix);
  await t.pumpAndSettle();

  await t.tap(find.text('Болсон'));
  await t.pumpAndSettle();
}

/// Starts the meter and feeds it [_kRunRoute].
Future<void> _runStagedRoute(
  WidgetTester t,
  FakeLocationSource location,
) async {
  await t.tap(find.text('Эхлүүл'));
  await t.pumpAndSettle();
  for (final fix in _kRunRoute) {
    location.emit(fix);
    // Two frames: `RideMap`'s polyline layer needs the extra one on some
    // transitions (see `meter/taximeter_page_test.dart`).
    await t.pump();
    await t.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Note on shadows: the test binding sets `debugDisableShadows`, which turns
  // Material *elevation* shadows into stroked outlines. It is deliberately
  // left alone -- flipping it trips the framework's "a painting debug variable
  // was changed by the test" invariant, and this design carries its depth in
  // `BoxDecoration` shadows (`TakhiSurfaces.sheetShadow` / `.floatShadow`),
  // which that flag does not touch. The sheet's lift is therefore real here.
  setUpAll(() async {
    _stubPathProvider();
    await _loadRealFonts();
  });

  testWidgets('home, light', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpHome(t, Brightness.light);
    await _shoot(t, 'home_light');
  });

  testWidgets('home, dark', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpHome(t, Brightness.dark);
    await _shoot(t, 'home_dark');
  });

  testWidgets('meter, ready to start', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    await _pumpMeter(t, Brightness.light, location: location);
    await _pickDestination(t, location);
    await _shoot(t, 'meter_idle_light');
  });

  testWidgets('meter, running', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    await _pumpMeter(t, Brightness.light, location: location);
    await _runStagedRoute(t, location);
    await _shoot(t, 'meter_running_light');
  });

  testWidgets('meter, running (dark)', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    await _pumpMeter(t, Brightness.dark, location: location);
    await _runStagedRoute(t, location);
    await _shoot(t, 'meter_running_dark');
  });

  testWidgets('meter, finished', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    final qr = await _sampleBankQrPng(t);
    await _pumpMeter(t, Brightness.light, location: location, driverQr: qr);
    await _runStagedRoute(t, location);
    await t.tap(find.text('Дуусгах'));
    await t.pumpAndSettle();
    await _precacheDriverQr(t, qr);

    await _shoot(t, 'meter_finished_light');
  });
}
