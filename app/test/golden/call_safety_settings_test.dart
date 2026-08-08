// SPDX-License-Identifier: AGPL-3.0-or-later

/// Design screenshots for the driver-side and call-side screens the first
/// batch (`design_screenshots_test.dart`) never photographed. Same
/// reasoning, same harness, same shutter: nothing here asserts anything,
/// every case is tagged `golden` so `dart_test.yaml` skips it in an ordinary
/// run, and `matchesGoldenFile` is a screenshot tool on a machine with no
/// emulator and no web build. Read that file's header for the full
/// argument; this one records only what differs.
///
/// ```sh
/// cd app
/// flutter test --update-goldens --run-skipped \
///     test/golden/call_safety_settings_test.dart --concurrency=1
/// ```
///
/// What is real and what is staged:
///
/// * Every widget is the production one, imported and pumped; nothing under
///   `lib/` is touched. Every string comes from `app_mn.arb` through the
///   real `AppLocalizations` — the only things invented here are *data*: a
///   name, a plate, a price, a landmark, a phone number, GPS timestamps.
/// * Nothing is drawn from a wall clock, a random number generator or a
///   freshly minted key. The identity is BIP-39's all-zero test vector
///   restored (never `createNew`), the ride request is a hand-built
///   `NostrEvent` with a fixed id and `created_at`, and every GPS fix
///   carries a scripted timestamp.
/// * The relay network is absent rather than faked into answering: the pool
///   is built over [FakeRelaySocket] and never connected, and the two
///   streams `DriverInboxPage` reads come from
///   [_StubDriverInboxService]/[_StubHandoffService]. That is what keeps
///   these pictures off the wall clock — `DriverInboxPage` hardcodes
///   `DateTime.now()` into its own expiry filter, so a relay-delivered
///   request would have to be stamped "now" to survive it.
/// * The map tiles are genuinely absent, as in the first batch: `RideMap`
///   really lays out and paints, `flutter_test` blocks its tile fetches.
/// * The finished meter's duration chip reads `0 мин` for the reason the
///   first batch documented — it is wall-clock time between two taps in one
///   test, with no seam to inject a clock through. The *waiting* duration
///   beside it comes from the scripted fix timestamps and is real, which is
///   why the two visibly disagree in that picture.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:takhi/call/call_engine.dart';
import 'package:takhi/call/call_providers.dart';
import 'package:takhi/call/call_screen.dart';
import 'package:takhi/call/phone_share_settings.dart';
import 'package:takhi/call/voice_note_recorder.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/meter/routing_client.dart';
import 'package:takhi/meter/tariff_store.dart';
import 'package:takhi/meter/taximeter_page.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/payment/driver_qr_capture_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/driver_photo_store.dart';
import 'package:takhi/profile/driver_profile_page.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi/profile/profile_providers.dart';
import 'package:takhi/ride/driver_inbox_page.dart';
import 'package:takhi/ride/driver_inbox_service.dart';
import 'package:takhi/ride/handoff_service.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/ride_providers.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/primary_button.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_call_engine.dart';
import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';
import '../support/staged_portrait.dart';

/// The tag `dart_test.yaml` skips. Every case here carries it.
const _kGoldenTag = 'golden';

/// A modern handset's logical size, matching the first screenshot batch so
/// the two sets are judged at the same scale.
const _kLogicalSize = Size(390, 844);

const _kDevicePixelRatio = 2.0;

/// Fonts the pictures need. Without NotoSans every Cyrillic glyph would
/// render as a filled box.
const _kFonts = <String, String>{
  'NotoSans': 'assets/fonts/NotoSans-Regular.ttf',
  'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
};

/// BIP-39's all-zero test vector — restored, never minted, so the derived
/// pubkey (and therefore every id derived from it) is the same on every run.
const _kDemoMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

/// Label on the throwaway first route the pushed screens open from.
const _kLauncherLabel = 'нүүр';

/// Sukhbaatar Square — `defaultCityConfig`'s coordinates, i.e. where
/// `DriverInboxPage` centres its map, so a request here lands on screen.
const _kPickupLat = 47.9186;
const _kPickupLon = 106.9176;

/// A staged passenger's key material, and the staged request's event id.
/// Fixed hex rather than a generated pair: nothing here verifies a
/// signature, and a fresh key would change nothing on screen while making
/// the fixture non-reproducible in principle.
const _kPassengerPubHex =
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';

const _kRideRequestId =
    '1d8b5cbcb7b0a6e1c6a1eee74be96e0a8b9b9b6b5b0f3e0d9c8b7a695847362d';

const _kTripId = 'takhi-trip-6f2a91c4';

/// What the driver charges on the taximeter screens: real Ulaanbaatar
/// street-hail rates, so the fares come out with the digit count a driver
/// actually reads rather than a round test number's.
const _kMeterKmTariff = 1200;
const _kMeterWaitTariff = 300;

/// The whole-trip-duration rate, for the three pictures that photograph a
/// driver who charges all three. Deliberately smaller than the stopped-time
/// rate: it runs for every second of the trip rather than only the stopped
/// ones, so a driver pricing both sanely prices this one lower — and the two
/// figures on the running sheet then differ, which is what makes a picture
/// with the labels swapped obvious rather than plausible.
const _kMeterDurationTariff = 100;

/// A scripted run: two travelling legs near 40-50 km/h (well above
/// `kWaitingSpeedThresholdKmh`, so they bill as distance), then two legs of
/// a metre of GPS drift per minute (~0.07 km/h, which `MeterSession`
/// refuses to bill as travel and charges as waiting). All four figures on
/// the running sheet are non-zero at once: ~4.5 км, 8 мин elapsed,
/// 2 мин waited, and a waiting charge beside the fare.
const _kMeterRoute = <GpsFix>[
  GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 1000),
  GpsFix(lat: 47.9366, lon: 106.9176, timestampSeconds: 1180),
  GpsFix(lat: 47.9366, lon: 106.9506, timestampSeconds: 1360),
  GpsFix(lat: 47.93661, lon: 106.9506, timestampSeconds: 1420),
  GpsFix(lat: 47.93662, lon: 106.9506, timestampSeconds: 1480),
];

/// The profile a driver who prices by the meter has already published.
/// Where the driver's own phone says the car is while the inbox is
/// photographed. Deliberately a couple of streets off [_kPickupLat] /
/// [_kPickupLon], so the driver's dot and the waiting call's pin are two
/// separate marks in frame rather than one drawn over the other -- which is
/// exactly the comparison the picture exists to show.
const _kDriverFix = GpsFix(
  lat: 47.9165,
  lon: 106.9142,
  timestampSeconds: 1000,
  accuracyMeters: 40,
);

const _kMeteredDriverProfile = DriverProfile(
  familyName: 'Д.',
  givenName: 'Батсайхан',
  car: 'Toyota Prius 30',
  color: 'цагаан',
  plate: '1234УБА',
  kmTariffMnt: 1500,
  waitTariffMntPerMinute: 300,
  // All three rates, so the toggle's subtitle is photographed at its tallest.
  // That subtitle is what commits this driver to every rate in their profile
  // at once, it gains a line per rate, and it sits at the bottom of a dialog
  // that is already a `Column(mainAxisSize: min)` holding three fields -- the
  // exact shape that runs out of screen without any test being able to say so.
  durationTariffMntPerMinute: 80,
);

/// Always throws, so any fare estimate deterministically falls back to the
/// offline straight-line guess instead of reaching the public OSRM demo
/// server from a test.
class _OfflineRoutingClient implements RoutingClient {
  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) => throw Exception('offline');
}

/// An in-memory [DriverQrStore] holding nothing -- the finished meter step
/// builds `DriverQrDisplay`, which would otherwise reach `path_provider`.
class _EmptyDriverQrStore implements DriverQrStore {
  @override
  Future<void> save(Uint8List pngBytes) async {}

  @override
  Future<Uint8List?> load() async => null;

  @override
  Future<void> clear() async {}
}

/// Hands `DriverInboxPage` a fixed list of nearby requests instead of a
/// relay subscription. See the library header for why the service, not the
/// socket, is the seam that keeps these pictures off the wall clock.
class _StubDriverInboxService extends DriverInboxService {
  final List<RideRequestListing> listings;

  _StubDriverInboxService(this.listings) : super(RelayPool(const []));

  @override
  Stream<RideRequestListing> nearbyRequests({
    required double driverLat,
    required double driverLon,
    required int Function() nowSeconds,
  }) => Stream.fromIterable(listings);
}

/// Hands `DriverInboxPage` a fixed handoff (or none) instead of a
/// gift-wrapped DM subscription, whose ciphertext would differ per run.
class _StubHandoffService extends HandoffService {
  final List<ReceivedHandoff> handoffs;

  _StubHandoffService(this.handoffs)
    : super(RideDmChannel(RelayPool(const [])));

  @override
  Stream<ReceivedHandoff> receiveHandoffs(String myPubHex, String myPrivHex) =>
      Stream.fromIterable(handoffs);
}

/// Answers `path_provider` with a scratch directory: `flutter_map`'s tile
/// layer asks for the cache directory on first build, and that channel is
/// absent under `flutter_test`.
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

/// Phone-shaped screen at phone density, put back afterwards.
void _useHandsetScreen(WidgetTester t) {
  t.view.physicalSize = _kLogicalSize * _kDevicePixelRatio;
  t.view.devicePixelRatio = _kDevicePixelRatio;
  addTearDown(t.view.reset);
}

/// The app shell every picture is taken through: `main.dart`'s theme,
/// locale and delegates, minus the router.
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
Future<void> _shoot(WidgetTester t, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('images/$name.png'),
);

/// Pumps [page] as the app's root screen.
Future<void> _pumpRoot(
  WidgetTester t,
  Widget page,
  List<Override> overrides,
) async {
  await t.pumpWidget(_screen(page, Brightness.light, overrides));
  await t.pumpAndSettle();
}

/// Pushes [page] on top of a throwaway first route, the way every screen
/// here is actually reached. Only a pushed route carries the `AppBar`'s
/// back arrow, and only a pushed route can raise `ConfirmLeaveScope`'s
/// dialog. [settle] is `false` for `CallScreen`, whose connecting state
/// holds an indefinite spinner `pumpAndSettle` would never outlast.
Future<void> _pumpPushed(
  WidgetTester t,
  Widget page,
  List<Override> overrides, {
  bool settle = true,
}) async {
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
      Brightness.light,
      overrides,
    ),
  );
  await t.tap(find.text(_kLauncherLabel));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await _pumpFrames(t);
  }
}

/// A fixed slice of fake time, for screens whose spinner never settles.
Future<void> _pumpFrames(WidgetTester t, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Decodes every [Image] currently on screen into the image cache, so the
/// next frame paints the pictures instead of holes where they go.
///
/// `Image.memory` hands its bytes to the codec on a real event loop, and a
/// widget test runs on a fake clock that never lets that finish -- so a
/// portrait pumped and photographed in the ordinary way comes out as an
/// empty circle, silently and with every test still green. That is exactly
/// the failure class `docs/design/SCREENSHOT_RULE.md` exists to catch, and
/// it caught this one.
///
/// Driven off the live tree rather than off a byte list the caller passes
/// in: `MemoryImage`'s cache key is the *identity* of its `Uint8List`, so
/// precaching a copy of the same pixels warms the wrong key and changes
/// nothing. Asking the widgets themselves guarantees the key matches.
Future<void> _precacheOnScreenImages(WidgetTester t) async {
  final elements = find.byType(Image).evaluate().toList();
  await t.runAsync(() async {
    for (final element in elements) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await t.pumpAndSettle();
}

/// Drops the caret and focus ring after text entry. Not cosmetic: a focused
/// field paints a timer-driven blinking cursor, and whether the picture
/// catches it up or down would make a regenerated file differ for nothing.
Future<void> _dismissKeyboard(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
}

/// A staged public ride request at the driver's own map centre. Hand-built
/// rather than signed: the stub bypasses relay and expiry alike, and a
/// fixed `id`/`created_at` is what makes the fixture reproducible.
RideRequestListing _stagedListing() {
  final event = NostrEvent(
    id: _kRideRequestId,
    pubkey: _kPassengerPubHex,
    createdAt: 1700000000,
    kind: kKindRideRequest,
    tags: [
      ['g', geohashEncode(_kPickupLat, _kPickupLon, precision: 6)],
      ['dest', geohashEncode(47.9210, 106.8890, precision: 6)],
      ['expiration', '1700000240'],
    ],
    content: 'Хоёр хүн, ачаагүй',
  );
  return RideRequestListing(event, parseRideRequest(event));
}

/// The exact pickup point a passenger sends once they have picked this
/// driver -- the screen a driver reads aloud to find a doorway.
ReceivedHandoff _stagedHandoff() {
  const lat = 47.9221, lon = 106.9155;
  return ReceivedHandoff(
    _kPassengerPubHex,
    RideHandoffPayload(
      rideRequestId: _kRideRequestId,
      tripId: _kTripId,
      lat: lat,
      lon: lon,
      // The real encoder, not a plausible-looking literal: this is the one
      // string on screen a driver retypes into another app, so an invented
      // code would prove nothing about the real one's length or wrapping.
      plusCode: plusCodeEncode(lat, lon),
      landmarkText: 'Сүхбаатарын талбайн зүүн урд, «Гоён» дэлгүүрийн үүдэнд',
    ),
  );
}

/// Everything `DriverInboxPage` needs with no network: a restored identity,
/// an unconnected fake-socket pool, and its two streams supplied directly.
///
/// [portrait] is the driver's own stored photograph. It is not decoration
/// here: `driverOfferBlock` refuses a driver with no name or no portrait,
/// and `_sendOffer` checks that *before* it opens the pricing dialog -- so
/// a screenshot of that dialog cannot be taken at all unless this store has
/// something in it. Left null for the screens that never open it.
Future<List<Override>> _inboxOverrides({
  required List<RideRequestListing> listings,
  required List<ReceivedHandoff> handoffs,
  DriverProfile? profile,
  Uint8List? portrait,
}) async {
  final keyStore = InMemoryKeyStore();
  await IdentityService(keyStore).restore(_kDemoMnemonic);
  final profileStore = InMemoryDriverProfileStore();
  if (profile != null) await profileStore.save(profile);
  final photoStore = InMemoryDriverPhotoStore();
  if (portrait != null) await photoStore.save(portrait);
  return [
    keyStoreProvider.overrideWithValue(keyStore),
    relayPoolProvider.overrideWithValue(
      RelayPool(defaultRelayUrls, connect: (_) => FakeRelaySocket()),
    ),
    driverInboxServiceProvider.overrideWithValue(
      _StubDriverInboxService(listings),
    ),
    handoffServiceProvider.overrideWithValue(_StubHandoffService(handoffs)),
    driverProfileStoreProvider.overrideWithValue(profileStore),
    driverPhotoStoreProvider.overrideWithValue(photoStore),
    driverQrStoreProvider.overrideWithValue(_EmptyDriverQrStore()),
  ];
}

/// Opens `_OfferDialog` from the one nearby-request marker on the map and
/// fills it in with a real-looking offer.
Future<void> _openFilledOfferDialog(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.person_pin_circle));
  await t.pumpAndSettle();

  final fields = find.byType(TextField);
  await t.enterText(fields.at(0), '12000');
  await t.enterText(fields.at(1), '6');
  await t.enterText(fields.at(2), 'цагаан Toyota Prius 30, 1234УБА');
  await _dismissKeyboard(t);
}

/// The provider set every taximeter picture is taken through.
List<Override> _meterOverrides({
  required TariffStore tariffStore,
  required FakeLocationSource location,
}) => [
  tariffStoreProvider.overrideWithValue(tariffStore),
  meterJournalStoreProvider.overrideWithValue(InMemoryMeterJournalStore()),
  routingClientProvider.overrideWithValue(_OfflineRoutingClient()),
  locationSourceProvider.overrideWithValue(location),
  locationPermissionCheckProvider.overrideWithValue(() async => true),
  driverQrStoreProvider.overrideWithValue(_EmptyDriverQrStore()),
];

/// A tariff store holding a saved rate, so the meter opens idle.
///
/// [durationMntPerMinute] defaults to zero — i.e. the driver most of these
/// pictures are of, who does not charge for the trip's length — so that the
/// long-standing meter screenshots keep photographing the state they were
/// framed for. The pictures that exist *for* the third rate pass it in.
Future<TariffStore> _savedTariff({int durationMntPerMinute = 0}) async {
  final store = InMemoryTariffStore();
  await store.save(
    DriverTariff(
      mntPerKm: _kMeterKmTariff,
      mntPerMinute: _kMeterWaitTariff,
      durationMntPerMinute: durationMntPerMinute,
    ),
  );
  return store;
}

/// Starts the meter and feeds it [_kMeterRoute].
Future<void> _runStagedMeterRoute(
  WidgetTester t,
  FakeLocationSource location,
) async {
  await t.tap(find.text('Эхлүүл'));
  await t.pumpAndSettle();
  for (final fix in _kMeterRoute) {
    location.emit(fix);
    // Two frames: `RideMap`'s polyline layer needs the extra one on some
    // transitions (see `meter/taximeter_page_test.dart`); the settle then
    // finishes the mode badge's cross-fade, so no picture catches the
    // meter showing two modes at once.
    await t.pump();
    await t.pumpAndSettle();
  }
}

/// Pauses the running meter and confirms the guard dialog. The confirm
/// carries the same verb as the button that opened it, so the tap is scoped
/// to the dialog rather than matched by label alone.
Future<void> _pauseAndConfirm(WidgetTester t) async {
  await t.tap(find.widgetWithText(TextButton, 'Түр зогсоох'));
  await t.pumpAndSettle();
  await t.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Түр зогсоох'),
    ),
  );
  await t.pumpAndSettle();
}

/// Everything `CallScreen` needs to run one whole attempt with no WebRTC
/// stack, no relay and no `shared_preferences` plugin behind it.
Future<List<Override>> _callOverrides(FakeCallEngine engine) async {
  final keyStore = InMemoryKeyStore();
  await IdentityService(keyStore).restore(_kDemoMnemonic);
  return [
    keyStoreProvider.overrideWithValue(keyStore),
    relayPoolProvider.overrideWithValue(
      RelayPool(defaultRelayUrls, connect: (_) => FakeRelaySocket()),
    ),
    callEngineFactoryProvider.overrideWithValue((iceServers) => engine),
    phoneShareSettingsStoreProvider.overrideWithValue(
      InMemoryPhoneShareSettingsStore(),
    ),
    voiceNoteRecorderProvider.overrideWithValue(FakeVoiceNoteRecorder()),
  ];
}

/// A detector that finds nobody, so «no face found» -- the one refusal a
/// real driver hits most often, and the one whose wording has to be
/// instructions rather than an accusation -- can be photographed without a
/// model, a native library or a device.
class _NoFaceDetector implements FaceDetector {
  const _NoFaceDetector();

  @override
  Future<List<DetectedFace>> detect(Uint8List jpegBytes) async => const [];
}

/// Hands the profile screen a real image with no gallery behind it, so the
/// refusal that follows is the app's own verdict rather than a plugin that
/// was never there.
class _StagedImagePickerPlatform extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(stagedPortraitJpeg(), name: 'portrait.jpg');
}

/// Everything `DriverProfilePage` reads, with both halves of the portrait
/// pipeline pinned: the store to memory, the detector to one that always
/// refuses. The production `faceDetectorProvider` is
/// `UnavailableFaceDetector`, which would put «the checker is broken» on
/// screen and make these pictures a photograph of a placeholder rather than
/// of the design.
Future<List<Override>> _profileOverrides(
  KeyStore keyStore, {
  required DriverPhotoStore photoStore,
  DriverProfile? profile,
}) async {
  final profileStore = InMemoryDriverProfileStore();
  if (profile != null) await profileStore.save(profile);
  return [
    keyStoreProvider.overrideWithValue(keyStore),
    relayPoolProvider.overrideWithValue(
      RelayPool(defaultRelayUrls, connect: (_) => FakeRelaySocket()),
    ),
    driverProfileStoreProvider.overrideWithValue(profileStore),
    driverPhotoStoreProvider.overrideWithValue(photoStore),
    faceDetectorProvider.overrideWithValue(const _NoFaceDetector()),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _stubPathProvider();
    await _loadRealFonts();
  });

  // S14a -- the offer dialog's `Column(mainAxisSize: min)` has to hold
  // three fields plus a checkbox carrying a three-rate Cyrillic subtitle,
  // now two lines tall. No widget test can say it fits.
  //
  // One picture rather than the two this used to take. The second showed
  // the «set a km-tariff first» hint that stands in for the checkbox, and
  // that state can no longer be reached: `_sendOffer` refuses to open this
  // dialog at all unless `driverOfferBlock` passes, which needs a saved
  // profile, and `DriverProfile.kmTariffMnt` is not nullable -- so by the
  // time the dialog exists there is always a tariff behind it. See
  // `design_system_audit_test.dart`'s `_unphotographedStates`.

  testWidgets('offer dialog, tariff saved', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpRoot(
      t,
      const DriverInboxPage(),
      await _inboxOverrides(
        listings: [_stagedListing()],
        handoffs: const [],
        profile: _kMeteredDriverProfile,
        portrait: stagedPortraitJpeg(),
      ),
    );

    await _openFilledOfferDialog(t);
    // Ticked on purpose: an unticked box says nothing about whether the
    // check mark is legible against this theme's field colour.
    await t.tap(find.byType(Checkbox));
    await t.pumpAndSettle();

    await _shoot(t, 'driver_offer_dialog_light');
  });

  // S14 -- the map a driver watches between trips. Photographed with the
  // driver's own position delivered, which is the whole point: this screen
  // used to draw a call pin with nothing on the map standing for the car
  // looking at it, so «is that one close?» had no answer. The base tiles
  // still do not load under `flutter_test`, but the marks do -- and the
  // marks are what this picture is for.
  testWidgets('driver inbox, located, one nearby call', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final location = FakeLocationSource();
    addTearDown(location.dispose);
    await _pumpRoot(t, const DriverInboxPage(), [
      ...await _inboxOverrides(
        listings: [_stagedListing()],
        handoffs: const [],
        profile: _kMeteredDriverProfile,
        portrait: stagedPortraitJpeg(),
      ),
      locationSourceProvider.overrideWithValue(location),
      locationPermissionCheckProvider.overrideWithValue(() async => true),
    ]);

    location.emit(_kDriverFix);
    await t.pumpAndSettle();

    await _shoot(t, 'driver_inbox_markers_light');
  });

  // S15 -- the one screen where a driver reads a Plus Code off the glass
  // with their own eyes.

  testWidgets('driver awarded handoff', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    // The location source has to be stubbed here now, and it did not before:
    // being awarded a job starts the approach broadcast, which opens a real
    // GPS subscription. Under `flutter_test` that reaches the geolocator
    // platform channel and throws `MissingPluginException` -- a harness
    // gap, not something a device does.
    final location = FakeLocationSource();
    addTearDown(location.dispose);
    await _pumpRoot(t, const DriverInboxPage(), [
      ...await _inboxOverrides(
        listings: const [],
        handoffs: [_stagedHandoff()],
      ),
      locationSourceProvider.overrideWithValue(location),
      locationPermissionCheckProvider.overrideWithValue(() async => true),
    ]);

    await _shoot(t, 'driver_awarded_handoff_light');
  });

  // S17 -- the app's longest form: a portrait, ten fields, four headings,
  // three tinted notices and a disabled save. Photographed empty because
  // that is how it opens for a driver who has never published a profile,
  // and the state where the labels, the helper lines and the two notices
  // are the only guidance there is.
  //
  // Four pictures rather than one, because the blocks that were added to
  // this screen are the ones that have to be *read* rather than filled in.
  // The empty form carries the "you cannot send offers yet" warning above
  // the empty circle and the "this is not proof of identity" disclaimer, and
  // is also the only framing of the line that now names what is keeping the
  // save button grey -- that line is at its longest here, with all six
  // required boxes still empty; the refused state adds a third tinted card
  // between the picker buttons and that disclaimer, and is photographed
  // where a driver actually stands when it appears -- scrolled down to the
  // button they just pressed, which is the only framing that holds the
  // refusal and the disclaimer at once; the ready state is the only one
  // where the top notice is green and the circle holds a face; and the
  // price section is its own picture because the bottom of this form is now
  // three per-unit rates followed by two flat fees -- the booking base and the
  // minimum floor -- each with a label and a helper line under it, and no
  // widget test can say whether «Дуудлагын суурь хөлс (₮)» and «Доод хязгаар
  // (₮)» stay legible and distinct stacked below the three rates. None of the
  // four is a colour-swap of another.

  testWidgets('driver profile, empty form', tags: _kGoldenTag, (t) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).restore(_kDemoMnemonic);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const DriverProfilePage(),
      await _profileOverrides(keyStore, photoStore: InMemoryDriverPhotoStore()),
    );

    await _shoot(t, 'driver_profile_empty_light');
  });

  testWidgets('driver profile, photo refused', tags: _kGoldenTag, (t) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).restore(_kDemoMnemonic);
    ImagePickerPlatform.instance = _StagedImagePickerPlatform();

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const DriverProfilePage(),
      await _profileOverrides(
        keyStore,
        photoStore: InMemoryDriverPhotoStore(),
        profile: _kMeteredDriverProfile,
      ),
    );

    // The commonest real refusal, and the one whose wording matters most:
    // «no face found» is nearly always an honest driver standing too far
    // from the camera, so the picture has to show instructions rather than
    // an accusation.
    await t.ensureVisible(find.text('Галерейгаас сонгох'));
    await t.pumpAndSettle();
    await t.tap(find.text('Галерейгаас сонгох'));
    await t.pumpAndSettle();

    await _shoot(t, 'driver_profile_photo_refused_light');
  });

  testWidgets('driver profile, portrait accepted', tags: _kGoldenTag, (
    t,
  ) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).restore(_kDemoMnemonic);
    final photoStore = InMemoryDriverPhotoStore();
    // Pre-stored rather than picked, so the picture does not depend on the
    // staged portrait surviving a live compression run.
    await photoStore.save(stagedPortraitJpeg());

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const DriverProfilePage(),
      await _profileOverrides(
        keyStore,
        photoStore: photoStore,
        profile: _kMeteredDriverProfile,
      ),
    );
    // Without this the 132dp circle photographs empty -- see
    // [_precacheOnScreenImages]. This case is the only one in the file with
    // a photograph in frame, and the whole point of it.
    await _precacheOnScreenImages(t);

    await _shoot(t, 'driver_profile_photo_ready_light');
  });

  testWidgets('driver profile, price section', tags: _kGoldenTag, (t) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).restore(_kDemoMnemonic);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const DriverProfilePage(),
      await _profileOverrides(
        keyStore,
        photoStore: InMemoryDriverPhotoStore(),
        // A saved profile rather than an empty form: the three rates have to
        // be judged holding real numbers, since a driver reading this
        // section is checking prices they already set, and an empty capsule
        // says nothing about whether «1 500» crowds its own label.
        //
        // Built here rather than reusing [_kMeteredDriverProfile], which
        // charges nothing for a trip's duration -- that constant is what the
        // offer dialog and the inbox are photographed against, and giving it
        // a third rate would change their pictures to answer a question
        // about this one.
        profile: const DriverProfile(
          familyName: 'Д.',
          givenName: 'Батсайхан',
          car: 'Toyota Prius 30',
          color: 'цагаан',
          plate: '1234УБА',
          kmTariffMnt: 1500,
          waitTariffMntPerMinute: 300,
          durationTariffMntPerMinute: 120,
          // The two flat fees, set to real figures for the same reason the
          // three rates are: a driver reading this section is checking prices
          // they already chose, so the picture has to show «1 500» and «3 000»
          // in their capsules rather than an empty box that says nothing about
          // crowding.
          bookingBaseMnt: 1500,
          minFareMnt: 3000,
        ),
      ),
    );

    // The last field on the page, so scrolling it into view brings the whole
    // «Үнэ» section with it and leaves the anchored save sheet in frame
    // underneath -- which is the framing that shows the two flat fees below the
    // three per-unit rates and the save button together.
    await t.ensureVisible(
      find.byKey(const Key('driverProfileMinFareField')),
    );
    await t.pumpAndSettle();

    await _shoot(t, 'driver_profile_price_light');
  });

  // S18 -- an `Expanded(Center(...))` holding one line of hint text, which
  // is either a calm empty state or a hole in the middle of the screen.

  testWidgets('qr capture, nothing picked', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpPushed(t, const DriverQrCapturePage(), [
      driverQrStoreProvider.overrideWithValue(_EmptyDriverQrStore()),
    ]);

    await _shoot(t, 'qr_capture_empty_light');
  });

  // S19 -- the tariff step's two unphotographed states: the very first
  // entry (no cancel to fall back to) and the double-error verdict.

  testWidgets('meter tariff, first entry', tags: _kGoldenTag, (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(tariffStore: InMemoryTariffStore(), location: location),
    );

    await _shoot(t, 'meter_tariff_first_light');
  });

  testWidgets('meter tariff, every field refused', tags: _kGoldenTag, (
    t,
  ) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(tariffStore: await _savedTariff(), location: location),
    );

    // Reopening a saved rate is what puts the cancel button on the step.
    // Reached from a charge row since v0.4.0: the idle step lists every
    // charge instead of carrying two pills.
    await t.tap(find.text('Замын хөлс'));
    await t.pumpAndSettle();

    // Three prices typed as words: `_saveTariff` states every verdict at
    // once, so the picture shows the tallest the step can ever get -- the
    // boxes, their explanations and three refusals stacked above the sheet.
    await t.enterText(find.byType(TextField).at(0), 'арван мянга');
    await t.enterText(find.byType(TextField).at(1), 'гурван зуу');
    await t.enterText(find.byType(TextField).at(2), 'зуу');
    await _dismissKeyboard(t);
    await t.tap(find.text('Хадгалах'));
    await t.pumpAndSettle();

    await _shoot(t, 'meter_tariff_invalid_light');
  });

  // S20 -- the idle step as a driver actually finds it: no destination
  // picked, so no estimate chips, so the waiting caveat stands alone.

  testWidgets('meter idle, no destination', tags: _kGoldenTag, (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(tariffStore: await _savedTariff(), location: location),
    );

    await _shoot(t, 'meter_idle_empty_light');
  });

  // S21 -- the running sheet at its fullest: mode badge, headline fare and
  // four statistics, not the two a zero-waiting run can show.

  testWidgets('meter running, waiting mode', tags: _kGoldenTag, (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(tariffStore: await _savedTariff(), location: location),
    );
    await _runStagedMeterRoute(t, location);

    await _shoot(t, 'meter_running_waiting_light');
  });

  testWidgets('meter running, paused', tags: _kGoldenTag, (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(tariffStore: await _savedTariff(), location: location),
    );
    await _runStagedMeterRoute(t, location);
    await _pauseAndConfirm(t);

    await _shoot(t, 'meter_running_paused_light');
  });

  // S22 -- the itemised summary a passenger checks the arithmetic on. Only
  // a run that actually waited shows the two middle rows.

  testWidgets('meter finished, waiting rows', tags: _kGoldenTag, (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(tariffStore: await _savedTariff(), location: location),
    );
    await _runStagedMeterRoute(t, location);

    await t.tap(find.widgetWithText(PrimaryButton, 'Дуусгах'));
    await t.pumpAndSettle();

    await _shoot(t, 'meter_finished_waiting_light');
  });

  // S21b/S22b -- the same three steps for a driver who charges all three
  // rates (added 2026-08-01 with the trip-duration rate). They are their own
  // pictures rather than a change to the ones above, because the driver who
  // charges only by distance and jam is still the common case and still has
  // to be photographed: this rate is opt-in, and every screen it touches has
  // a with-it and a without-it shape.

  testWidgets('meter idle, all three rates set', tags: _kGoldenTag, (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(
        tariffStore: await _savedTariff(
          durationMntPerMinute: _kMeterDurationTariff,
        ),
        location: location,
      ),
    );

    // Three rate pills where there are normally two, and the estimate now
    // carries two caveats rather than one -- the tallest this step gets.
    await _shoot(t, 'meter_idle_all_rates_light');
  });

  testWidgets('meter running, all three rates set', tags: _kGoldenTag, (
    t,
  ) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(
        tariffStore: await _savedTariff(
          durationMntPerMinute: _kMeterDurationTariff,
        ),
        location: location,
      ),
    );
    await _runStagedMeterRoute(t, location);

    // The fullest the running sheet ever is: mode badge, headline fare,
    // distance and elapsed time, then the stopped minutes, the stopped
    // charge and the duration charge on one shrink-to-fit line.
    await _shoot(t, 'meter_running_all_rates_light');
  });

  testWidgets('meter finished, all three breakdown rows', tags: _kGoldenTag, (
    t,
  ) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(
        tariffStore: await _savedTariff(
          durationMntPerMinute: _kMeterDurationTariff,
        ),
        location: location,
      ),
    );
    await _runStagedMeterRoute(t, location);

    await t.tap(find.widgetWithText(PrimaryButton, 'Дуусгах'));
    await t.pumpAndSettle();

    // The column a passenger adds up: distance, stopped time, the time
    // waited, trip duration, rule, total. Four labelled rows above the rule
    // is as many as this screen can ever show.
    await _shoot(t, 'meter_finished_all_rates_light');
  });

  // The guard before the fare stops. Shot on a meter that charges by trip
  // duration, because that is the case the dialog had to grow a second
  // paragraph for: pausing stops the km and stopped-time meters, and does
  // not stop the duration one -- that rate bills every second between the
  // first GPS fix and the last by design. Without the note the dialog made
  // a promise it only half kept, on the screen where a driver decides to
  // stop for fuel.

  testWidgets(
    'meter pause confirmation, duration rate set',
    tags: _kGoldenTag,
    (t) async {
      final location = FakeLocationSource();
      addTearDown(location.dispose);

      _useHandsetScreen(t);
      await _pumpPushed(
        t,
        const TaximeterPage(),
        _meterOverrides(
          tariffStore: await _savedTariff(durationMntPerMinute: 120),
          location: location,
        ),
      );
      await _runStagedMeterRoute(t, location);

      await t.tap(find.widgetWithText(TextButton, 'Түр зогсоох'));
      await t.pumpAndSettle();

      await _shoot(t, 'meter_pause_confirm_dialog_light');
    },
  );

  // S32 -- the only place a `DialogActionBar` paints its caution tone, and
  // the only warning before a whole run's fare disappears.

  testWidgets('meter leave confirmation', tags: _kGoldenTag, (t) async {
    final location = FakeLocationSource();
    addTearDown(location.dispose);

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const TaximeterPage(),
      _meterOverrides(tariffStore: await _savedTariff(), location: location),
    );
    await _runStagedMeterRoute(t, location);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    await _shoot(t, 'meter_leave_confirm_dialog_light');
  });

  // S23 -- the four call bodies, the app's only full-screen use of gold on
  // `TakhiColors.ink`, and none of them reachable without a second device.

  testWidgets('call, connecting', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    // No state emitted: `startAsCaller` leaves the screen on
    // `CallStateDialing`, i.e. the first fifteen seconds of every call.
    await _pumpPushed(
      t,
      const CallScreen(
        tripId: _kTripId,
        counterpartyPubHex: _kPassengerPubHex,
        isCaller: true,
      ),
      await _callOverrides(FakeCallEngine()),
      settle: false,
    );

    await _shoot(t, 'call_connecting');
  });

  testWidgets('call, connected', tags: _kGoldenTag, (t) async {
    final engine = FakeCallEngine();

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const CallScreen(
        tripId: _kTripId,
        counterpartyPubHex: _kPassengerPubHex,
        isCaller: true,
      ),
      await _callOverrides(engine),
      settle: false,
    );

    engine.emitConnectionState(CallConnectionState.connected);
    await t.pump(const Duration(milliseconds: 16));
    // 83 one-second ticks, i.e. 01:23 -- long enough that both halves of
    // the clock carry a non-symmetric pair of digits, which is the whole
    // point of looking at tabular figures at all.
    for (var i = 0; i < 83; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    await t.pump(const Duration(milliseconds: 100));

    await _shoot(t, 'call_connected');
  });

  testWidgets('call, phone fallback', tags: _kGoldenTag, (t) async {
    final engine = FakeCallEngine();

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const CallScreen(
        tripId: _kTripId,
        counterpartyPubHex: _kPassengerPubHex,
        isCaller: true,
        // A known number plus the default-on sharing setting is what
        // `decideFallbackAction` needs to offer the phone rung at all.
        counterpartyPhone: '+976 9911 2233',
      ),
      await _callOverrides(engine),
      settle: false,
    );

    engine.emitConnectionState(CallConnectionState.failed);
    await _pumpFrames(t);

    await _shoot(t, 'call_fallback_phone');
  });

  testWidgets('call, voice note fallback', tags: _kGoldenTag, (t) async {
    final engine = FakeCallEngine();

    _useHandsetScreen(t);
    await _pumpPushed(
      t,
      const CallScreen(
        tripId: _kTripId,
        counterpartyPubHex: _kPassengerPubHex,
        isCaller: true,
        // No phone number known: the last rung of the chain.
      ),
      await _callOverrides(engine),
      settle: false,
    );

    engine.emitConnectionState(CallConnectionState.failed);
    await _pumpFrames(t);

    await _shoot(t, 'call_fallback_voice_note');
  });
}
