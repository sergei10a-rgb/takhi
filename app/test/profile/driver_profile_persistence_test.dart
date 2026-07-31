// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The test that was missing, and whose absence let a dead feature ship.
//
// Every other test around this screen replaces BOTH of the things that
// were actually broken on the phone: `driverProfileStoreProvider` becomes
// an `InMemoryDriverProfileStore`, and `faceDetectorProvider` becomes a
// detector that accepts. 848 green tests could not see either failure,
// because between them they had substituted the entire production path.
//
// So this file overrides only the PLATFORM EDGES -- the documents
// directory and the SharedPreferences backing map, neither of which exists
// in a test VM -- and leaves every provider that carries policy exactly as
// `main()` wires it. What runs here is the real store classes and the real
// face detector.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/driver_photo_store.dart';
import 'package:takhi/profile/driver_profile_page.dart';
import 'package:takhi/profile/face/tflite_face_detector.dart';
import 'package:takhi/profile/profile_providers.dart';

import '../support/fake_relay_socket.dart';

void main() {
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('takhi_profile_test');
    // The backing map a real `SharedPreferences.getInstance()` reads on a
    // device. Set empty, so the store under test starts as a fresh install
    // does -- and, crucially, so `SharedPreferencesDriverProfileStore` is
    // the thing being exercised rather than a stand-in for it.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  /// Production wiring, minus the two platform calls a test VM has no
  /// answer for. Note what is NOT here: `driverProfileStoreProvider` and
  /// `faceDetectorProvider` keep their real values.
  List<Override> productionOverrides(KeyStore keyStore, RelayPool pool) => [
    keyStoreProvider.overrideWithValue(keyStore),
    relayPoolProvider.overrideWithValue(pool),
    // Same class production uses, pointed at a temp directory instead of
    // `getApplicationDocumentsDirectory()`.
    driverPhotoStoreProvider.overrideWithValue(
      FileDriverPhotoStore(() async => documents.path),
    ),
  ];

  Future<(KeyStore, RelayPool)> identityAndPool() async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool(['wss://a'], connect: (_) => FakeRelaySocket());
    await pool.connectAll();
    return (keyStore, pool);
  }

  Future<void> pumpProfile(
    WidgetTester tester,
    KeyStore keyStore,
    RelayPool pool,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: productionOverrides(keyStore, pool),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          // Pushed onto a route, because `_save()` ends in `Navigator.pop`.
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DriverProfilePage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('the real SharedPreferences store, through the real page', () {
    testWidgets('a saved profile survives leaving the screen and coming '
        'back', (tester) async {
      final (keyStore, pool) = await identityAndPool();

      await pumpProfile(tester, keyStore, pool);
      await tester.enterText(
        find.byKey(const Key('driverProfileFamilyNameField')),
        'Батбаяр',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Мөнх-Эрдэнэ',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileCarField')),
        'Приус 30',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileColorField')),
        'Цагаан',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfilePlateField')),
        '1234 УБА',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileKmTariffField')),
        '2500',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      // Re-mount from scratch: a brand new widget tree reading whatever the
      // real store kept. This is "closed the app and opened it again".
      await pumpProfile(tester, keyStore, pool);

      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('driverProfileFamilyNameField')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'Батбаяр',
        reason: 'the family name must come back from shared_preferences',
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('driverProfileNameField')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'Мөнх-Эрдэнэ',
        reason: 'the given name must come back from shared_preferences',
      );
    });
  });

  group('the face detector this app actually ships', () {
    // The engine itself cannot run here -- TFLite is a native library and
    // `flutter test` is a desktop Dart VM with no Android .so to load. That
    // the model accepts a real face is proved on hardware instead, by
    // `integration_test/face_detector_device_test.dart`.
    //
    // What CAN be checked here is the thing that actually went wrong, and
    // it is not subtle: the app shipped a mandatory photo gate wired to an
    // engine that refuses everything. That is a wiring fact, and wiring is
    // testable.
    test('is a real engine, not the placeholder that refuses every photo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final detector = container.read(faceDetectorProvider);

      expect(
        detector,
        isNot(isA<UnavailableFaceDetector>()),
        reason:
            'driverOfferBlock makes a portrait mandatory and '
            'OfferService.sendOffer enforces it, so a detector that refuses '
            'every photo means no driver anywhere can send a single offer. '
            'That is what shipped in v0.2.0, and it passed 848 tests '
            'because every one of them overrode this provider.',
      );
      expect(detector, isA<TfliteFaceDetector>());
    });

    test(
      'the model it needs is actually declared as a bundled asset',
      () async {
        // A detector wired to an asset that is not in pubspec.yaml fails at
        // runtime on a real phone and nowhere else -- the same shape of bug
        // again, one layer down.
        final pubspec = await File('pubspec.yaml').readAsString();
        expect(
          pubspec.contains('assets/models/'),
          isTrue,
          reason:
              'the BlazeFace model must be bundled or the detector cannot '
              'load on a device',
        );
        expect(File(kBlazeFaceAssetPath).existsSync(), isTrue);
      },
    );
  });
}
