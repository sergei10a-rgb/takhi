// SPDX-License-Identifier: AGPL-3.0-or-later

/// Design screenshots of the identity, safety and settings screens — not a
/// verification test.
///
/// A sibling of `design_screenshots_test.dart`, sharing its harness verbatim
/// (real bundled fonts, 390x844 at devicePixelRatio 2, the `golden` tag, PNGs
/// under `images/`) and its reason for existing: the plugins this app depends
/// on have no web implementation, so `flutter run -d chrome` cannot boot it
/// and there is no emulator on this machine. Flutter's own widget renderer is
/// the only renderer available, and `matchesGoldenFile` is being used as a
/// shutter rather than as an assertion.
///
/// That other file photographs the two screens a rider spends time on — home
/// and the meter. This one photographs the screens they pass through *once*,
/// under stress, and which therefore nobody ever looks at twice:
///
/// * **onboarding** — the only screen where `TakhiColors.sand` (a pale
///   parchment) is hardcoded as a *foreground* colour while the surface under
///   it is theme-resolved. On the dark theme that is the pairing it was
///   designed for; on the light theme, whose surface is the equally pale
///   `TakhiColors.paper`, it is pale-on-pale. No widget test can see that —
///   `find.text` passes either way. The light and dark pictures side by side
///   are the whole point.
/// * **the error states** — `createIdentityError` and `restoreError` are
///   instructions the user has to *read* to get unstuck, and they only ever
///   appear when something has already gone wrong. Their size, spacing and
///   wrapping are unverified by construction.
/// * **the two confirmation dialogs** — the app's only
///   `DialogActionTone.destructive` (overwriting a private key) and its
///   inverted-emphasis counterpart on the seed screen, where *staying* is the
///   loud answer. Tone is colour and weight; only a picture carries it.
/// * **the recovery phrase** — twelve words that, if one of them is clipped
///   or unreadable, cost the user their identity permanently.
/// * **the SOS sheet**, in both of its shapes: three rows when a contact is
///   saved, and the empty state — the least-looked-at, worst-moment surface
///   in the app.
///
/// ## Regenerating the pictures
///
/// ```sh
/// cd app
/// flutter test --update-goldens --run-skipped \
///     test/golden/onboarding_and_identity_test.dart --concurrency=1
/// ```
///
/// ## What is real here and what is staged
///
/// * Every widget is the production one, imported and pumped. Nothing under
///   `lib/` is touched, and no user-facing string is written here — all of it
///   comes from `AppLocalizations` (i.e. `l10n/app_mn.arb`), looked up at
///   runtime rather than pasted in, so a copy change moves these pictures
///   instead of silently disagreeing with them.
/// * The **seeds are published BIP-39 test vectors**, never freshly minted.
///   `IdentityService.createNewWithMnemonic` draws real entropy, so a shot
///   taken through it would show a different phrase and a different npub on
///   every run and no regeneration would ever produce a meaningful diff.
///   [_kBackupMnemonic] is the standard `0x8080…80` vector and
///   [_kStoredMnemonic] the all-zero one; both are in every BIP-39 test suite
///   on earth and hold nothing.
/// * The **map behind home is genuinely blank**. `RideMap` is the real widget
///   and really lays out and paints; `flutter_test` blocks its tile fetches,
///   so it paints flutter_map's empty canvas. Honest about position and size,
///   blank about content.
/// * [EditableText.debugDeterministicCursor] is set for the file. The restore
///   screen autofocuses its field, and a blinking caret is both a source of
///   run-to-run diff and something `pumpAndSettle` cannot settle. With the
///   flag the caret is simply always painted — which is also the more useful
///   picture.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi/call/call_providers.dart';
import 'package:takhi/call/phone_share_settings.dart';
import 'package:takhi/call/phone_share_settings_page.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/home/home_page.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/legal/legal_notice_page.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/onboarding/onboarding_page.dart';
import 'package:takhi/onboarding/restore_page.dart';
import 'package:takhi/onboarding/seed_backup_page.dart';
import 'package:takhi/safety/emergency_contact_store.dart';
import 'package:takhi/safety/safety_providers.dart';
import 'package:takhi/settings/settings_page.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/primary_button.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// The tag `dart_test.yaml` skips. Every case here carries it.
const _kGoldenTag = 'golden';

/// A modern handset's logical size, matching `design_screenshots_test.dart`
/// so the two sets of pictures can be compared without mental rescaling.
const _kLogicalSize = Size(390, 844);

/// Written into the pictures, so hairlines and letterforms are judged at the
/// density a phone actually shows.
const _kDevicePixelRatio = 2.0;

/// Fonts the pictures need, family -> asset key in the test bundle. Without
/// these every Cyrillic glyph renders as a filled box.
const _kFonts = <String, String>{
  'NotoSans': 'assets/fonts/NotoSans-Regular.ttf',
  'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
};

/// The brand mark on onboarding, as `_Brandmark` asks the bundle for it.
const _kBrandmarkAsset = 'assets/icon.png';

/// The small horse in `HomeTopBar`'s brand pill, light-theme variant — the
/// only variant these pictures need, since every home shot here is light.
const _kTopBarMarkAsset = 'assets/brand/takhi_horse_ink.png';

/// BIP-39's published `0x8080…80` test vector — the phrase the seed-backup
/// pictures show.
///
/// A real vector rather than an invented one, and specifically this vector
/// rather than the all-zero one, because the all-zero phrase is eleven copies
/// of `abandon`: it would prove that *a* word fits the tile and nothing about
/// twelve different ones. This carries the wordlist's longest entries
/// (`acoustic`, `absurd`, `doctor`) next to its shortest, which is what the
/// 2x6 grid actually has to survive.
const _kBackupMnemonic =
    'letter advice cage absurd amount doctor '
    'acoustic avoid letter advice cage above';

/// [_kBackupMnemonic] with its last word swapped for another valid wordlist
/// entry — the single most common way a recovery phrase is mistyped, and a
/// BIP-39 checksum failure, so `IdentityService.restore` throws the
/// [ArgumentError] the restore screen turns into its inline error.
const _kMistypedMnemonic =
    'letter advice cage absurd amount doctor '
    'acoustic avoid letter advice cage abandon';

/// BIP-39's all-zero vector, used for the identity already in the keystore
/// behind the home and overwrite-dialog shots. Fixed so the npub chip on the
/// home sheet reads the same on every regeneration.
const _kStoredMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

/// The staged emergency contact behind the three-row SOS sheet. A Mongolian
/// mobile number in shape, and deliberately not anybody's: the sheet never
/// prints it, it only decides which of the two sheets is shown.
const _kEmergencyContactPhone = '99112233';

/// A [KeyStore] whose [write] always fails the way the real secure-storage
/// backend does when the OS keystore is locked, access is denied, or the
/// platform is unsupported. Copied in shape from `onboarding_widget_test
/// .dart`'s own double: it is the only way to reach the onboarding screen's
/// error state without a real device in a bad mood.
class _FailingKeyStore implements KeyStore {
  @override
  Future<void> write(String p) async =>
      throw const SecureStoreException('write failed', 'secure store offline');

  @override
  Future<String?> read() async => null;

  @override
  Future<void> clear() async {}
}

/// Answers `path_provider` with a scratch directory for the whole file.
///
/// `flutter_map`'s tile layer asks for the application cache directory the
/// first time a [RideMap] is built, and that plugin's channel is absent under
/// `flutter_test` — without this the home shots die on a
/// `MissingPluginException` before they can be photographed. Nothing is ever
/// read back out: the tiles it would cache never download.
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

/// The app shell every picture is taken through: the theme, locale and
/// delegates `main.dart` configures, minus the router.
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

/// The same shell around a [GoRouter], for [SeedBackupPage].
///
/// That screen is a `PopScope` whose whole job is to intercept a system back,
/// and a back press has to reach a real router to be intercepted — the same
/// harness shape `onboarding_seed_backup_back_navigation_test.dart` uses, for
/// the same reason. `/home` exists only so the confirmed-leave leg has
/// somewhere to land; no picture is taken of it.
Widget _seedScreen(Brightness brightness) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  theme: takhiTheme(brightness),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('mn'),
  routerConfig: GoRouter(
    initialLocation: '/seed',
    routes: [
      GoRoute(
        path: '/seed',
        builder: (context, state) =>
            const SeedBackupPage(mnemonic: _kBackupMnemonic),
      ),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold()),
    ],
  ),
);

/// Writes the whole screen — including anything in the overlay, which is
/// where dialogs and modal sheets live — to `test/golden/images/<name>.png`.
Future<void> _shoot(WidgetTester t, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('images/$name.png'),
);

/// The app's own Mongolian copy, read out of the running tree.
///
/// Every label these cases tap is looked up through this rather than pasted
/// in as a literal: the strings on screen belong to `l10n/app_mn.arb`, and a
/// screenshot harness that hardcodes its own copy of them is a harness that
/// can quietly disagree with the app it is photographing.
AppLocalizations _strings(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first))!;

/// Delivers the platform's `popRoute` message — what Android's hardware back
/// button and iOS' back gesture actually send.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
}

/// Decodes [asset] into the image cache so the next frame paints it.
///
/// `Image.asset` decodes asynchronously and a widget test's fake clock never
/// lets that finish, so without this the 132px circle at the top of onboarding
/// is an empty ring and the horse in home's brand pill is missing.
///
/// Doing it explicitly also removes a real source of run-to-run drift. The
/// [ImageCache] is shared by every case in a file, and a decode kicked off by
/// one case can finish, on the real clock, while the *next* one is running —
/// so without this the first home shot came out without the horse and the
/// three after it came out with it, purely by scheduling accident. Warming
/// the cache deliberately, in every case that needs it, makes all of them
/// agree.
Future<void> _precacheAsset(WidgetTester t, String asset) async {
  final context = t.element(find.byType(Scaffold).first);
  await t.runAsync(() => precacheImage(AssetImage(asset), context));
  await t.pumpAndSettle();
}

/// Onboarding, on [brightness], with [store] behind the identity service.
Future<void> _pumpOnboarding(
  WidgetTester t,
  Brightness brightness,
  KeyStore store,
) async {
  await t.pumpWidget(
    _screen(const OnboardingPage(), brightness, [
      keyStoreProvider.overrideWithValue(store),
    ]),
  );
  await t.pumpAndSettle();
  await _precacheAsset(t, _kBrandmarkAsset);
}

/// Home, with a stored identity, relays connected, and location answered by
/// [permissionGranted].
///
/// Deliberately *not* the located state: `design_screenshots_test.dart`'s
/// `home_light` already photographs home after a successful locate, so these
/// pictures are the two states that come before it — the first paint after
/// onboarding, and a refusal.
Future<void> _pumpHome(
  WidgetTester t, {
  required bool permissionGranted,
  String? emergencyContactPhone,
}) async {
  final keyStore = InMemoryKeyStore();
  await IdentityService(keyStore).restore(_kStoredMnemonic);

  final location = FakeLocationSource();
  addTearDown(location.dispose);

  final contacts = InMemoryEmergencyContactStore();
  final phone = emergencyContactPhone;
  if (phone != null) await contacts.savePhone(phone);

  await t.pumpWidget(
    _screen(const HomePage(), Brightness.light, [
      keyStoreProvider.overrideWithValue(keyStore),
      relayPoolProvider.overrideWithValue(
        RelayPool(defaultRelayUrls, connect: (_) => FakeRelaySocket()),
      ),
      emergencyContactStoreProvider.overrideWithValue(contacts),
      locationSourceProvider.overrideWithValue(location),
      locationPermissionCheckProvider.overrideWithValue(
        () async => permissionGranted,
      ),
    ]),
  );
  await t.pumpAndSettle();
  await _precacheAsset(t, _kTopBarMarkAsset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Note on shadows: the test binding sets `debugDisableShadows`, which turns
  // Material *elevation* shadows into stroked outlines. Left alone on purpose
  // -- flipping it trips the framework's "a painting debug variable was
  // changed by the test" invariant. It does not touch the `BoxDecoration`
  // shadows this design carries its depth in.
  setUpAll(() async {
    _stubPathProvider();
    await _loadRealFonts();
    EditableText.debugDeterministicCursor = true;
  });

  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('onboarding, light', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpOnboarding(t, Brightness.light, InMemoryKeyStore());
    await _shoot(t, 'onboarding_light');
  });

  testWidgets('onboarding, dark', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpOnboarding(t, Brightness.dark, InMemoryKeyStore());
    await _shoot(t, 'onboarding_dark');
  });

  testWidgets('onboarding, secure storage refused', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    await _pumpOnboarding(t, Brightness.light, _FailingKeyStore());

    await t.tap(find.text(_strings(t).createIdentity));
    await t.pumpAndSettle();

    await _shoot(t, 'onboarding_create_error_light');
  });

  testWidgets('onboarding, overwrite confirmation', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    final store = InMemoryKeyStore();
    await IdentityService(store).restore(_kStoredMnemonic);
    await _pumpOnboarding(t, Brightness.light, store);

    await t.tap(find.text(_strings(t).createIdentity));
    await t.pumpAndSettle();

    await _shoot(t, 'onboarding_overwrite_dialog_light');
  });

  testWidgets('seed backup, light', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await t.pumpWidget(_seedScreen(Brightness.light));
    await t.pumpAndSettle();
    await _shoot(t, 'seed_backup_light');
  });

  testWidgets('seed backup, dark', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await t.pumpWidget(_seedScreen(Brightness.dark));
    await t.pumpAndSettle();
    await _shoot(t, 'seed_backup_dark');
  });

  testWidgets('seed backup, leave confirmation', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await t.pumpWidget(_seedScreen(Brightness.light));
    await t.pumpAndSettle();

    await _systemBack(t);
    await t.pumpAndSettle();

    await _shoot(t, 'seed_leave_dialog_light');
  });

  testWidgets('restore, empty', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await t.pumpWidget(
      _screen(const RestorePage(), Brightness.light, [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      ]),
    );
    await t.pumpAndSettle();
    await _shoot(t, 'restore_empty_light');
  });

  testWidgets('restore, phrase rejected', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await t.pumpWidget(
      _screen(const RestorePage(), Brightness.light, [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      ]),
    );
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), _kMistypedMnemonic);
    await t.pump();
    // The button, not `find.text`: the AppBar title and the button carry the
    // same `restoreIdentity` label, so a text finder here is ambiguous.
    await t.tap(find.byType(PrimaryButton));
    await t.pumpAndSettle();

    await _shoot(t, 'restore_error_light');
  });

  testWidgets('home, before locating', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpHome(t, permissionGranted: true);
    await _shoot(t, 'home_unlocated_light');
  });

  testWidgets('home, location refused', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpHome(t, permissionGranted: false);

    await t.tap(find.byIcon(Icons.my_location));
    await t.pumpAndSettle();

    await _shoot(t, 'home_denied_light');
  });

  testWidgets('SOS sheet, contact saved', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpHome(
      t,
      permissionGranted: true,
      emergencyContactPhone: _kEmergencyContactPhone,
    );

    await t.tap(find.byIcon(Icons.emergency));
    await t.pumpAndSettle();

    await _shoot(t, 'sos_sheet_light');
  });

  testWidgets('SOS sheet, no contact saved', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await _pumpHome(t, permissionGranted: true);

    await t.tap(find.byIcon(Icons.emergency));
    await t.pumpAndSettle();

    await _shoot(t, 'sos_sheet_no_contact_light');
  });

  testWidgets('settings menu', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await t.pumpWidget(_screen(const SettingsPage(), Brightness.light, []));
    await t.pumpAndSettle();
    await _shoot(t, 'settings_menu_light');
  });

  testWidgets('phone share settings, nothing entered', tags: _kGoldenTag, (
    t,
  ) async {
    _useHandsetScreen(t);
    await t.pumpWidget(
      _screen(const PhoneShareSettingsPage(), Brightness.light, [
        phoneShareSettingsStoreProvider.overrideWithValue(
          InMemoryPhoneShareSettingsStore(),
        ),
      ]),
    );
    await t.pumpAndSettle();
    await _shoot(t, 'phone_share_settings_light');
  });

  testWidgets('legal notice', tags: _kGoldenTag, (t) async {
    _useHandsetScreen(t);
    await t.pumpWidget(_screen(const LegalNoticePage(), Brightness.light, []));
    await t.pumpAndSettle();
    await _shoot(t, 'legal_notice_light');
  });
}
