// SPDX-License-Identifier: AGPL-3.0-or-later

/// Design screenshots of the ride flow, not a verification test.
///
/// The sibling of `design_screenshots_test.dart`, using the same harness for
/// the same reason: the plugins these screens depend on (geolocator,
/// flutter_secure_storage, flutter_webrtc, ...) have no web implementation,
/// so `flutter run -d chrome` cannot boot the app, and there is no emulator
/// on this machine. Flutter's own widget renderer is the only renderer
/// available, so `matchesGoldenFile` is used as a screenshot tool with
/// `--update-goldens` as the shutter.
///
/// Where `design_screenshots_test.dart` photographs home and the driver's
/// taximeter, this file photographs the sixteen screens between "call a
/// ride" and "the money changed hands": the passenger's booking wizard
/// (`ride/passenger_ride_page.dart`) and every step of the shared in-trip
/// view (`ride/active_trip_view.dart`), plus the two full-screen states
/// that only ever appear on top of it -- the incoming-call overlay and the
/// location-permission refusal.
///
/// Every case is tagged `golden`, which `dart_test.yaml` marks skipped, so a
/// plain `flutter test` neither runs nor fails on them. Pixel output differs
/// between platforms and Flutter versions; treating these as assertions
/// would turn every framework bump into a red suite.
///
/// ## Regenerating the pictures
///
/// ```sh
/// cd app
/// flutter test --update-goldens --run-skipped \
///     test/golden/ride_flow_test.dart --concurrency=1
/// ```
///
/// `--run-skipped` defeats the `dart_test.yaml` skip; `--concurrency=1`
/// avoids the socket flakiness this repo sees on Windows. The PNGs land in
/// `test/golden/images/`.
///
/// ## What is real here and what is staged
///
/// * The widgets are the production ones. `PassengerRidePage` and
///   `ActiveTripView` are imported and pumped, driven through their real
///   state machines by real taps and real relay frames. Nothing under
///   `lib/` is touched, and no screen is reimplemented.
/// * The type is the real bundled NotoSans, loaded through [FontLoader].
///   Without it every glyph renders as a filled box (the test renderer's
///   fallback face) and the pictures would be worthless.
/// * **Every string on screen comes from `lib/l10n/app_mn.arb`**, read back
///   here through [AppLocalizations] rather than retyped -- see [_l]. A
///   screenshot that invented its own Mongolian would prove nothing about
///   the app's own wording, and finding widgets by a hardcoded label would
///   quietly rot the moment a translation changed.
/// * The **data** is staged: driver names, vehicle descriptions, prices,
///   ETAs, tariffs and GPS tracks are invented here so no screen is
///   photographed empty or reading zero. A screen full of blanks and `0₮`
///   shows nothing about the design.
/// * Nothing random or clock-derived reaches the pixels. The passenger's
///   identity is *restored* from [_kDemoMnemonic] rather than minted, the
///   drivers' keys come from fixed seeds ([_driver]), and every staged DM
///   carries [_kWireNow] rather than `DateTime.now()`. The figures the
///   metered screens show are what the production fare code computes from
///   the scripted fixes in [_kMeteredRoute] -- they are not painted on.
/// * The **map tiles are genuinely absent**. `RideMap` is the real widget
///   and it really does lay out and paint; `flutter_test` blocks its HTTP
///   tile fetches, so it paints flutter_map's own empty-canvas colour. The
///   map *area* is honest about its position and size, and blank about its
///   content. No stub was substituted.
/// * `ActiveTripView` owns no route of its own, so [_TripHost] supplies the
///   `Scaffold` + `AppBar` + `SafeArea` frame its two real hosts
///   (`PassengerRidePage`, `DriverInboxPage`) both put it in. Without it
///   the pictures would show the trip screens starting at y=0, which is not
///   where any of them start in the app.
/// * No text is ever typed into a field here. Every step is reached by
///   tapping, which keeps a blinking caret -- a pixel that differs by which
///   half of its blink the shutter caught -- out of the frame entirely.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/call/call_providers.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/payment/driver_qr_display.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/driver_offer_view.dart';
import 'package:takhi/ride/passenger_ride_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/driver_portrait.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';
import '../support/fake_voice_note_player.dart';
import '../support/staged_portrait.dart';

/// The tag `dart_test.yaml` skips. Every case here carries it.
const _kGoldenTag = 'golden';

/// A modern handset's logical size (iPhone 14 / Pixel 7 class), matching
/// `design_screenshots_test.dart` so the two sets are comparable.
const _kLogicalSize = Size(390, 844);

/// At 1.0 the PNGs would be 390px wide and every hairline, radius and
/// letterform would be judged at half the density a phone actually shows.
const _kDevicePixelRatio = 2.0;

/// Fonts the pictures need, family -> asset key in the test bundle.
const _kFonts = <String, String>{
  'NotoSans': 'assets/fonts/NotoSans-Regular.ttf',
  'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
};

/// The single staged relay. One is enough: nothing here exercises
/// multi-relay fan-out, and one socket keeps "which frame carried the
/// subscription id" answerable.
const _kRelayUrl = 'wss://a';

/// BIP-39's all-zero test vector, the same seed the onboarding tests use.
///
/// Restored rather than minted: `IdentityService.createNew` draws fresh
/// entropy, so anything derived from the passenger's key would differ on
/// every run and every regeneration would show a diff that means nothing.
const _kDemoMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

/// The `created_at` every staged relay frame carries. A fixed second rather
/// than `DateTime.now()`, for the same reproducibility reason as
/// [_kDemoMnemonic] -- nothing on screen shows it, but a wire timestamp that
/// moves is a wire timestamp that can start mattering later.
const _kWireNow = 1700000000;

/// Where the staged rider is standing: Ulaanbaatar's centre, which is also
/// `defaultCityConfig`'s, so a marker dropped here lands inside the map
/// viewport rather than off its edge.
const _kOriginLat = 47.9186;
const _kOriginLon = 106.9176;

/// A scripted metered leg: drive, then stand still.
///
/// The first pair is ~3.2 km in 300 s (38 km/h -- comfortably travelling),
/// the third fix moves 1.3 m in 360 s, which is a parked car's GPS jitter
/// and puts `MeterSession` into its waiting mode. The tracking screen is
/// therefore photographed with *both* meters having run: a real distance
/// fare underneath a live waiting fare, which is the busiest state that
/// screen has.
const _kMeteredRoute = <GpsFix>[
  GpsFix(lat: _kOriginLat, lon: _kOriginLon, timestampSeconds: 1000),
  GpsFix(lat: 47.9411, lon: 106.9444, timestampSeconds: 1300),
  GpsFix(lat: 47.94111, lon: 106.94441, timestampSeconds: 1660),
];

/// The driver's own short approach track, for the fixed-price driver
/// screenshot -- enough for the map to carry a positioned marker rather
/// than an empty canvas.
const _kApproachRoute = <GpsFix>[
  GpsFix(lat: _kOriginLat, lon: _kOriginLon, timestampSeconds: 1000),
  GpsFix(lat: 47.9203, lon: 106.9214, timestampSeconds: 1120),
];

/// The metered driver's rates, as they were offered and accepted.
const _kKmTariffMnt = 1500;
const _kWaitTariffMntPerMinute = 300;

/// The fare the staged metered trip settles at, and its waiting half --
/// what the driver's device measured and sent, so the passenger's confirm
/// screen shows one agreed breakdown rather than two nearly-equal ones.
const _kFinalFareMnt = 12450;
const _kFinalWaitingFareMnt = 1800;
const _kFinalWaitingSeconds = 360;

/// The fixed price the staged non-metered trip was agreed at.
const _kAgreedPriceMnt = 9500;

/// Stand-in payload for the driver's saved bank QR. Deliberately not a real
/// bank string: this renders into a picture that gets shown to people.
const _kSampleBankQrPayload = 'takhi:demo-driver-qr';

/// Every user-visible string in these pictures, read out of the app's own
/// `.arb` rather than retyped here. Loaded once in `setUpAll`.
late final AppLocalizations _l;

/// A driver's keypair from a fixed seed, so the same driver is the same
/// pubkey on every run -- which is what keeps `rankRideOffers`' ordering
/// (and therefore the offer list's row order) reproducible.
KeyPair _driver(int seed) => generateKeyPair(List<int>.filled(32, seed));

/// The staged drivers' portraits, on the wire: base64 JPEG, exactly as
/// `RideOfferPayload.driverPhotoJpegBase64` carries them.
///
/// Drawn and encoded once for the whole file rather than per case. The
/// pictures are deterministic (see [stagedPortraitJpeg]), so hoisting them
/// changes no pixel; it only stops six identical JPEG encodes from running
/// per shoot.
final _kStagedPortraitsBase64 = <String>[
  base64Encode(stagedPortraitJpeg(variant: 0)),
  base64Encode(stagedPortraitJpeg(variant: 1)),
];

/// In-memory [DriverQrStore] that can start out already holding a QR, so
/// the finished screen paints the driver's code rather than the "not set
/// yet" hint. The real store reads a file through `path_provider`, whose
/// platform channel is absent under `flutter_test`.
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

/// The frame `ActiveTripView`'s two real hosts both put it in.
///
/// `PassengerRidePage` and `DriverInboxPage` each wrap it in a `Scaffold`
/// with the app-name `AppBar`; the passenger side adds a `SafeArea`, which
/// is a no-op at the test view's zero insets. Photographing the view bare
/// would show every trip screen starting at y=0 -- a framing no user ever
/// sees, and one that would make the map look taller than it is.
class _TripHost extends StatelessWidget {
  final Widget child;
  const _TripHost({required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(title: Text(AppLocalizations.of(context)!.appName)),
    body: SafeArea(child: child),
  );
}

/// Everything a staged screen needs to keep talking to its fake relay after
/// it has been pumped.
class _Rig {
  final Identity identity;
  final FakeRelaySocket socket;
  final FakeLocationSource location;

  const _Rig({
    required this.identity,
    required this.socket,
    required this.location,
  });
}

/// Answers `path_provider` with a scratch directory for the whole file.
///
/// `flutter_map`'s tile layer asks for the application cache directory on
/// first build, and that plugin's channel is absent under `flutter_test`,
/// so without this the first screen mounting a `RideMap` dies with a
/// `MissingPluginException` before it can be photographed. Nothing is ever
/// read back out -- the tiles it would cache never download in the first
/// place.
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

/// Puts the test surface on a phone-shaped screen at phone density, and
/// puts it back afterwards so nothing leaks into the next case.
void _useHandsetScreen(WidgetTester t) {
  t.view.physicalSize = _kLogicalSize * _kDevicePixelRatio;
  t.view.devicePixelRatio = _kDevicePixelRatio;
  addTearDown(t.view.reset);
}

/// The app shell every picture is taken through: the same theme, locale and
/// delegates `main.dart` configures, minus the router (none of these
/// screens navigates during a shoot).
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

/// Writes the whole screen to `test/golden/images/<name>.png`.
///
/// The finder is [MaterialApp] on purpose: `matchesGoldenFile` walks up to
/// the nearest repaint boundary, which is the render view, whose paint
/// bounds are already scaled by [_kDevicePixelRatio] -- so the file comes
/// out at the device's physical resolution rather than at logical size. It
/// also means anything in the app's overlay (a dialog, the incoming-call
/// layer) is in the frame, which is the point of two of these pictures.
Future<void> _shoot(WidgetTester t, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('images/$name.png'),
);

/// Renders a QR into PNG bytes the way `DriverQrCapturePage` would have
/// saved them. Runs outside the fake-async zone because encoding an image
/// is real asynchronous work the test clock cannot drive.
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
/// `Image.memory` decodes asynchronously, and a widget test's fake clock
/// never lets that finish -- without this the driver's QR would be a
/// 240x240 hole.
Future<void> _precacheDriverQr(WidgetTester t, Uint8List bytes) async {
  final context = t.element(find.byType(DriverQrDisplay));
  await t.runAsync(() => precacheImage(MemoryImage(bytes), context));
  await t.pumpAndSettle();
}

/// The same trick as [_precacheDriverQr], applied to every [Image] on
/// screen instead of to one known byte list.
///
/// Needed wherever a driver's portrait is in frame. Those bytes arrive
/// base64 inside an offer and are decoded by `driverPhotoBytes` at build
/// time, so the caller has no `Uint8List` to hand in -- and handing in a
/// *copy* would warm the wrong cache entry, since `MemoryImage`'s equality
/// is the identity of its byte list. Reading the providers back off the
/// live elements is what guarantees the key matches.
///
/// A portrait that is not precached photographs as an empty circle while
/// every assertion in the suite stays green, which is the exact failure
/// `docs/design/SCREENSHOT_RULE.md` exists for.
Future<void> _precacheOnScreenImages(WidgetTester t) async {
  final elements = find.byType(Image).evaluate().toList();
  await t.runAsync(() async {
    for (final element in elements) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await t.pumpAndSettle();
}

/// The subscription id of the first / last kind-1059 (NIP-17 gift wrap)
/// `REQ` this device sent -- which subscription that is depends on the
/// screen and is documented at each call site.
String _firstWrapSubId(FakeRelaySocket socket) => _subIdOf(
  socket.sent.firstWhere((frame) => frame.contains('"kinds":[1059]')),
);

String _lastWrapSubId(FakeRelaySocket socket) => _subIdOf(
  socket.sent.lastWhere((frame) => frame.contains('"kinds":[1059]')),
);

String _subIdOf(String reqFrame) =>
    (jsonDecode(reqFrame) as List<dynamic>)[1] as String;

/// Delivers [payload] to the screen under test as if [sender] had DM'd it,
/// through the subscription [subId] identifies.
void _emitDm(
  FakeRelaySocket socket, {
  required String subId,
  required KeyPair sender,
  required String recipientPubHex,
  required RideDmPayload payload,
}) {
  final wrap = nip17Wrap(
    senderPrivHex: sender.privateHex,
    recipientPubHex: recipientPubHex,
    rumorKind: kRumorKindRideDm,
    content: payload.encode(),
    now: _kWireNow,
  );
  socket.emit(jsonEncode(['EVENT', subId, wrap.toJson()]));
}

/// Pumps `PassengerRidePage` with an identity in the keystore and a
/// connected (fake) relay, i.e. sitting on its first step.
Future<_Rig> _pumpPassengerRide(WidgetTester t) async {
  final keyStore = InMemoryKeyStore();
  final identity = await IdentityService(keyStore).restore(_kDemoMnemonic);
  final sockets = <String, FakeRelaySocket>{};
  final pool = RelayPool([
    _kRelayUrl,
  ], connect: (url) => sockets[url] = FakeRelaySocket());
  final location = FakeLocationSource();
  addTearDown(location.dispose);

  await t.pumpWidget(
    _screen(const PassengerRidePage(), Brightness.light, [
      keyStoreProvider.overrideWithValue(keyStore),
      relayPoolProvider.overrideWithValue(pool),
      locationSourceProvider.overrideWithValue(location),
      locationPermissionCheckProvider.overrideWithValue(() async => true),
    ]),
  );
  await pool.connectAll();
  await t.pumpAndSettle();

  return _Rig(
    identity: identity,
    socket: sockets[_kRelayUrl]!,
    location: location,
  );
}

/// Walks the wizard pickup -> destination -> price without typing a price,
/// then publishes. Leaves the page on its offers step, with the published
/// request's id returned so offers can be addressed against it.
Future<String> _publishRideRequest(WidgetTester t, _Rig rig) async {
  await t.tap(find.text(_l.nextStep).first); // pickup -> destination
  await t.pump();
  await t.tap(find.text(_l.nextStep).first); // destination -> price
  await t.pump();
  await t.tap(find.text(_l.publishRide));
  await t.pumpAndSettle();

  final frame =
      jsonDecode(rig.socket.sent.firstWhere((s) => s.contains('"kind":20177')))
          as List<dynamic>;
  return (frame[1] as Map<String, dynamic>)['id'] as String;
}

/// Delivers the three staged offers the passenger chooses between: two
/// plain fixed prices and one metered pair of rates.
///
/// Every driver here has an empty receipt history, so `rankRideOffers`
/// gives them all a `trustWeight` of zero and the list keeps the order they
/// arrived in -- which is what makes the row order reproducible.
Future<void> _stageOffers(WidgetTester t, _Rig rig, String requestId) async {
  // The offers subscription `_publish` opened is the only kind-1059 REQ
  // this page has sent at this point.
  final subId = _firstWrapSubId(rig.socket);
  final offers = <(KeyPair, RideOfferPayload)>[
    (
      _driver(11),
      RideOfferPayload(
        rideRequestId: requestId,
        priceMnt: _kAgreedPriceMnt,
        etaMinutes: 4,
        vehicleDescription: 'цагаан Toyota Prius 30',
        driverFamilyName: 'Б.',
        driverGivenName: 'Ганбаатар',
        driverPhotoJpegBase64: _kStagedPortraitsBase64[0],
      ),
    ),
    (
      _driver(12),
      RideOfferPayload(
        rideRequestId: requestId,
        priceMnt: _kFinalFareMnt,
        etaMinutes: 3,
        vehicleDescription: 'мөнгөлөг Toyota Alphard',
        kmTariffMnt: _kKmTariffMnt,
        waitTariffMntPerMinute: _kWaitTariffMntPerMinute,
        driverFamilyName: 'Ц.',
        driverGivenName: 'Отгонбаяр',
        driverPhotoJpegBase64: _kStagedPortraitsBase64[1],
      ),
    ),
    // Deliberately bare. A driver running a current client cannot send an
    // offer without both a name and a portrait (`driverOfferBlock`), so
    // this is what one from an older client looks like -- and the list has
    // to stay readable with one of each in it. Nothing but a picture can
    // show whether a named row and an anonymous one sit together without
    // the anonymous one reading as a rendering fault.
    (
      _driver(13),
      RideOfferPayload(
        rideRequestId: requestId,
        priceMnt: 8000,
        etaMinutes: 7,
        vehicleDescription: 'хар Hyundai Sonata',
      ),
    ),
  ];
  for (final (sender, payload) in offers) {
    _emitDm(
      rig.socket,
      subId: subId,
      sender: sender,
      recipientPubHex: rig.identity.pubHex,
      payload: payload,
    );
  }
  await t.pumpAndSettle();
  // `TripReceiptRepository.receiptsAbout` collects for a real 3 seconds per
  // driver; without pumping past it the delayed futures are left dangling
  // and the test fails its "no pending timers" teardown invariant.
  await t.pump(const Duration(seconds: 4));
  await t.pumpAndSettle();
}

/// Taps the metered offer on the list and settles on the driver's page,
/// with the portrait decoded.
///
/// The metered one on purpose: its vehicle description and its price are
/// both the longest on the list, so whatever fits around them fits around
/// the other two.
Future<void> _openDriverPage(WidgetTester t) async {
  await t.tap(find.textContaining(groupedMnt(_kFinalFareMnt)));
  await t.pumpAndSettle();
  await _precacheOnScreenImages(t);
}

/// Pumps `ActiveTripView` inside the frame its real hosts give it.
Future<_Rig> _pumpTrip(
  WidgetTester t, {
  required TripRole role,
  required String tripId,
  required KeyPair counterparty,
  required int agreedPriceMnt,
  int? kmTariffMnt,
  int? waitTariffMntPerMinute,
  bool locationGranted = true,
  Uint8List? driverQr,
}) async {
  final keyStore = InMemoryKeyStore();
  final identity = await IdentityService(keyStore).restore(_kDemoMnemonic);
  final sockets = <String, FakeRelaySocket>{};
  final pool = RelayPool([
    _kRelayUrl,
  ], connect: (url) => sockets[url] = FakeRelaySocket());
  final location = FakeLocationSource();
  addTearDown(location.dispose);
  await pool.connectAll();

  await t.pumpWidget(
    _screen(
      _TripHost(
        child: ActiveTripView(
          role: role,
          tripId: tripId,
          counterpartyPubHex: counterparty.publicHex,
          agreedPriceMnt: agreedPriceMnt,
          kmTariffMnt: kmTariffMnt,
          waitTariffMntPerMinute: waitTariffMntPerMinute,
          // Every real host wires this; without it the final screen
          // renders no control at all, which is not the screen anyone
          // actually reaches.
          onFinished: () {},
        ),
      ),
      Brightness.light,
      [
        keyStoreProvider.overrideWithValue(keyStore),
        relayPoolProvider.overrideWithValue(pool),
        locationSourceProvider.overrideWithValue(location),
        locationPermissionCheckProvider.overrideWithValue(
          () async => locationGranted,
        ),
        driverQrStoreProvider.overrideWithValue(_StubDriverQrStore(driverQr)),
        voiceNotePlayerProvider.overrideWithValue(FakeVoiceNotePlayer()),
      ],
    ),
  );
  await t.pumpAndSettle();

  return _Rig(
    identity: identity,
    socket: sockets[_kRelayUrl]!,
    location: location,
  );
}

/// Feeds [route] to the screen's own GPS subscription, one fix at a time.
Future<void> _driveRoute(WidgetTester t, _Rig rig, List<GpsFix> route) async {
  for (final fix in route) {
    rig.location.emit(fix);
    // Two frames: `RideMap`'s marker layer needs the extra one on some
    // transitions (see `meter/taximeter_page_test.dart`).
    await t.pump();
    await t.pump();
  }
  await t.pumpAndSettle();
}

/// Upper bound on [_letSnackBarsExpire]'s passes, so a `SnackBar` that
/// never leaves fails the shoot rather than hanging it.
const _kSnackBarDrainPasses = 8;

/// Lets every queued `SnackBar` run out its display duration and leave, so
/// the layer underneath is photographed on its own rather than behind a
/// toast -- which, at the bottom of the trip screen, sits squarely over the
/// driver's primary action.
///
/// One pass per toast, not one long pump for all of them: a single jump
/// lands the entrance animation and only *then* starts the four-second
/// display timer, so the queue drains one screenful at a time however far
/// the clock is advanced in one go.
Future<void> _letSnackBarsExpire(WidgetTester t) async {
  for (var pass = 0; pass < _kSnackBarDrainPasses; pass++) {
    if (find.byType(SnackBar).evaluate().isEmpty) return;
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Note on shadows: the test binding sets `debugDisableShadows`, which
  // turns Material *elevation* shadows into stroked outlines. It is
  // deliberately left alone -- flipping it trips the framework's "a
  // painting debug variable was changed by the test" invariant.
  setUpAll(() async {
    _stubPathProvider();
    await _loadRealFonts();
    _l = await AppLocalizations.delegate.load(const Locale('mn'));
  });

  setUp(() {
    // `_select` reads `phoneShareSettingsStoreProvider`, which is backed by
    // real `shared_preferences` -- without this mock its very first await
    // throws and the wizard never advances past the offers step.
    SharedPreferences.setMockInitialValues({});
    // Almost every screen here mounts a `RideMap`, and `RichAttributionWidget`
    // paints flutter_map's own logo asset in its corner. Decoding an image is
    // real asynchronous work the fake test clock cannot drive, so whether that
    // logo has arrived by shutter time depends purely on whether `imageCache`
    // already holds it -- that is, on what ran *before* this case in the same
    // process. Left alone, the very same screen photographs with the logo when
    // the file runs whole and without it when the case is run alone, and the
    // pictures stop being reproducible for a reason that has nothing to do
    // with the app. Emptying the cache per case makes the answer the same
    // either way. (`_precacheDriverQr` runs after this and is unaffected.)
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  // ---------------------------------------------------------------------
  // The passenger's booking wizard (`ride/passenger_ride_page.dart`).
  // ---------------------------------------------------------------------

  testWidgets('passenger: pickup step', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpPassengerRide(t);
    await _shoot(t, 'passenger_pickup_light');
  });

  testWidgets('passenger: name your price', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpPassengerRide(t);
    await t.tap(find.text(_l.nextStep).first); // pickup -> destination
    await t.pump();
    await t.tap(find.text(_l.nextStep).first); // destination -> price
    await t.pumpAndSettle();
    // Photographed before anything is typed, on purpose: the empty field is
    // the only state in which the Material label sits inside the outline
    // rather than notched into it.
    await _shoot(t, 'passenger_price_light');
  });

  testWidgets('passenger: published, no offers yet', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final rig = await _pumpPassengerRide(t);
    await _publishRideRequest(t, rig);
    await _shoot(t, 'passenger_offers_empty_light');
  });

  testWidgets('passenger: three offers to choose between', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final rig = await _pumpPassengerRide(t);
    final requestId = await _publishRideRequest(t, rig);
    await _stageOffers(t, rig, requestId);
    await _precacheOnScreenImages(t);
    await _shoot(t, 'passenger_offers_list_light');
  });

  testWidgets('passenger: the driver behind an offer', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final rig = await _pumpPassengerRide(t);
    final requestId = await _publishRideRequest(t, rig);
    await _stageOffers(t, rig, requestId);

    await _openDriverPage(t);
    await _shoot(t, 'passenger_driver_offer_light');
  });

  testWidgets('passenger: the portrait, full screen', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final rig = await _pumpPassengerRide(t);
    final requestId = await _publishRideRequest(t, rig);
    await _stageOffers(t, rig, requestId);
    await _openDriverPage(t);

    // The one screen in the app that is forced dark in both brightnesses,
    // and the only place the "this is not verified" caveat gets a whole
    // sentence rather than a chip. Both are claims about pixels, so both
    // need a picture.
    await t.tap(
      find.descendant(
        of: find.byType(DriverOfferPage),
        matching: find.byType(DriverPortrait),
      ),
    );
    await t.pumpAndSettle();
    await _precacheOnScreenImages(t);
    await _shoot(t, 'passenger_driver_photo_light');
  });

  testWidgets('passenger: confirming an offer', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final rig = await _pumpPassengerRide(t);
    final requestId = await _publishRideRequest(t, rig);
    await _stageOffers(t, rig, requestId);
    await _openDriverPage(t);

    // The confirmation is now two taps from the list rather than one: the
    // driver's page comes first, and this dialog is still the last thing
    // between a stray tap and an exact address leaving the device.
    await t.tap(find.text(_l.offerDriverSelectAction));
    await t.pumpAndSettle();
    // Again, after the driver page has popped. A cache warmed before a route
    // transition is not a cache that is still warm after it -- this picture
    // came out with the first row's portrait present on one run and missing
    // on the next until the precache moved to here, immediately in front of
    // the shutter. The rule this case establishes: precache last, never
    // "earlier in the same test".
    await _precacheOnScreenImages(t);
    await _shoot(t, 'passenger_confirm_offer_dialog_light');
  });

  testWidgets('passenger: driver chosen, on the way', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final rig = await _pumpPassengerRide(t);
    final requestId = await _publishRideRequest(t, rig);
    await _stageOffers(t, rig, requestId);
    await _openDriverPage(t);

    await t.tap(find.text(_l.offerDriverSelectAction));
    await t.pumpAndSettle();
    await t.tap(find.text(_l.confirmSelectOfferAction));
    await t.pumpAndSettle();
    await _precacheOnScreenImages(t);
    await _shoot(t, 'passenger_waiting_driver_light');
  });

  // ---------------------------------------------------------------------
  // The shared in-trip view (`ride/active_trip_view.dart`).
  // ---------------------------------------------------------------------

  testWidgets('trip: passenger, metered, waiting', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final driver = _driver(21);
    final rig = await _pumpTrip(
      t,
      role: TripRole.passenger,
      tripId: 'trip-tracking-metered',
      counterparty: driver,
      agreedPriceMnt: 0,
      kmTariffMnt: _kKmTariffMnt,
      waitTariffMntPerMinute: _kWaitTariffMntPerMinute,
    );

    // The passenger's phase subscription is the first kind-1059 REQ its
    // side sends (see `_startTracking`'s doc comment on ordering).
    _emitDm(
      rig.socket,
      subId: _firstWrapSubId(rig.socket),
      sender: driver,
      recipientPubHex: rig.identity.pubHex,
      payload: const RideTripStatusPayload(
        tripId: 'trip-tracking-metered',
        phase: TripPhase.tripInProgress,
      ),
    );
    await t.pumpAndSettle();
    await _driveRoute(t, rig, _kMeteredRoute);
    await _shoot(t, 'trip_tracking_metered_light');
  });

  testWidgets('trip: driver, en route to pickup', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final rig = await _pumpTrip(
      t,
      role: TripRole.driver,
      tripId: 'trip-tracking-driver',
      counterparty: _driver(22),
      agreedPriceMnt: _kAgreedPriceMnt,
    );
    await _driveRoute(t, rig, _kApproachRoute);
    await _shoot(t, 'trip_tracking_driver_light');
  });

  testWidgets('trip: two voice notes, one playing', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final passenger = _driver(23);
    final rig = await _pumpTrip(
      t,
      role: TripRole.driver,
      tripId: 'trip-voice',
      counterparty: passenger,
      agreedPriceMnt: _kAgreedPriceMnt,
    );

    // For the driver role the voice-note subscription is the first
    // kind-1059 REQ -- there is no phase subscription competing for it,
    // and `IncomingCallListener`'s own is always sent after.
    final subId = _firstWrapSubId(rig.socket);
    for (final seconds in [7, 12]) {
      _emitDm(
        rig.socket,
        subId: subId,
        sender: passenger,
        recipientPubHex: rig.identity.pubHex,
        payload: VoiceNotePayload(
          tripId: 'trip-voice',
          audioBase64: base64Encode(List<int>.filled(64, 7)),
          durationSeconds: seconds,
        ),
      );
      await t.pumpAndSettle();
    }
    // Each arrival also raises a SnackBar; let both leave so the banner is
    // photographed as the persistent layer it is.
    await _letSnackBarsExpire(t);

    await t.tap(find.byType(ActionChip).first);
    await t.pumpAndSettle();
    await _shoot(t, 'trip_voice_note_banner_light');
  });

  testWidgets('trip: passenger confirms the metered fare', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final driver = _driver(24);
    final rig = await _pumpTrip(
      t,
      role: TripRole.passenger,
      tripId: 'trip-fare-confirm',
      counterparty: driver,
      agreedPriceMnt: 0,
      kmTariffMnt: _kKmTariffMnt,
      waitTariffMntPerMinute: _kWaitTariffMntPerMinute,
    );

    _emitDm(
      rig.socket,
      subId: _firstWrapSubId(rig.socket),
      sender: driver,
      recipientPubHex: rig.identity.pubHex,
      payload: const RideTripStatusPayload(
        tripId: 'trip-fare-confirm',
        phase: TripPhase.arrived,
        finalFareMnt: _kFinalFareMnt,
        finalWaitingFareMnt: _kFinalWaitingFareMnt,
        finalWaitingSeconds: _kFinalWaitingSeconds,
      ),
    );
    await t.pumpAndSettle();
    await _shoot(t, 'trip_fare_confirm_light');
  });

  testWidgets('trip: rating, nothing picked yet', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final driver = _driver(25);
    final rig = await _pumpTrip(
      t,
      role: TripRole.passenger,
      tripId: 'trip-rating',
      counterparty: driver,
      agreedPriceMnt: _kAgreedPriceMnt,
    );

    // A fixed-price trip carries no final fare, so an arrival goes straight
    // to rating with no confirm step in between.
    _emitDm(
      rig.socket,
      subId: _firstWrapSubId(rig.socket),
      sender: driver,
      recipientPubHex: rig.identity.pubHex,
      payload: const RideTripStatusPayload(
        tripId: 'trip-rating',
        phase: TripPhase.arrived,
      ),
    );
    await t.pumpAndSettle();
    await _shoot(t, 'trip_rating_empty_light');
  });

  testWidgets('trip: finished, passenger side', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final driver = _driver(26);
    final rig = await _pumpTrip(
      t,
      role: TripRole.passenger,
      tripId: 'trip-done-passenger',
      counterparty: driver,
      agreedPriceMnt: _kAgreedPriceMnt,
    );

    _emitDm(
      rig.socket,
      subId: _firstWrapSubId(rig.socket),
      sender: driver,
      recipientPubHex: rig.identity.pubHex,
      payload: const RideTripStatusPayload(
        tripId: 'trip-done-passenger',
        phase: TripPhase.arrived,
      ),
    );
    await t.pumpAndSettle();

    // Four stars: a real rating, and one that leaves the fifth star empty
    // so the filled/empty pair is visible in the picture before it.
    await t.tap(find.byIcon(Icons.star_border).at(3));
    await t.pump();
    await t.tap(find.text(_l.submitRatingAction));
    await t.pumpAndSettle();
    await _shoot(t, 'trip_done_passenger_light');
  });

  testWidgets('trip: finished, driver side with QR', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final qr = await _sampleBankQrPng(t);
    final rig = await _pumpTrip(
      t,
      role: TripRole.driver,
      tripId: 'trip-done-driver',
      counterparty: _driver(27),
      agreedPriceMnt: _kFinalFareMnt,
      driverQr: qr,
    );
    await _driveRoute(t, rig, _kApproachRoute);

    await t.tap(find.text(_l.markPassengerBoardedAction));
    await t.pumpAndSettle();
    await t.tap(find.text(_l.endTripAction));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.star_border).at(4));
    await t.pump();
    await t.tap(find.text(_l.submitRatingAction));
    await t.pumpAndSettle();
    await _precacheDriverQr(t, qr);

    await _shoot(t, 'trip_done_driver_qr_light');
  });

  testWidgets('trip: the passenger declined the fare', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final driver = _driver(28);
    final rig = await _pumpTrip(
      t,
      role: TripRole.passenger,
      tripId: 'trip-declined',
      counterparty: driver,
      agreedPriceMnt: 0,
      kmTariffMnt: _kKmTariffMnt,
      waitTariffMntPerMinute: _kWaitTariffMntPerMinute,
    );

    _emitDm(
      rig.socket,
      subId: _firstWrapSubId(rig.socket),
      sender: driver,
      recipientPubHex: rig.identity.pubHex,
      payload: const RideTripStatusPayload(
        tripId: 'trip-declined',
        phase: TripPhase.arrived,
        finalFareMnt: _kFinalFareMnt,
        finalWaitingFareMnt: _kFinalWaitingFareMnt,
        finalWaitingSeconds: _kFinalWaitingSeconds,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text(_l.meteredFareDeclineAction));
    await t.pumpAndSettle();
    await _shoot(t, 'trip_done_declined_light');
  });

  testWidgets('trip: location permission refused', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    await _pumpTrip(
      t,
      role: TripRole.passenger,
      tripId: 'trip-location-denied',
      counterparty: _driver(29),
      agreedPriceMnt: _kAgreedPriceMnt,
      locationGranted: false,
    );
    await _shoot(t, 'trip_location_denied_light');
  });

  // ---------------------------------------------------------------------
  // The full-screen layer over the trip (`call/call_screen.dart`).
  // ---------------------------------------------------------------------

  testWidgets('call: incoming', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    final passenger = _driver(31);
    final rig = await _pumpTrip(
      t,
      role: TripRole.driver,
      tripId: 'trip-incoming-call',
      counterparty: passenger,
      agreedPriceMnt: _kAgreedPriceMnt,
    );
    await _driveRoute(t, rig, _kApproachRoute);

    // `IncomingCallListener`'s call-signal subscription is the last
    // kind-1059 REQ the driver side sends: the voice-note one goes first
    // (from `_startTracking`, synchronously), and live location is kind
    // 20178, not a gift wrap.
    _emitDm(
      rig.socket,
      subId: _lastWrapSubId(rig.socket),
      sender: passenger,
      recipientPubHex: rig.identity.pubHex,
      payload: const CallOfferPayload(
        tripId: 'trip-incoming-call',
        sdp: 'v=0 staged-remote-offer',
      ),
    );
    await t.pumpAndSettle();
    await _shoot(t, 'call_incoming_overlay');
  });
}
