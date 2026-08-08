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
import 'dart:convert';
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
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi/profile/face/tflite_face_detector.dart';
import 'package:takhi/profile/profile_providers.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

/// A store whose write always fails -- a phone whose disk refuses the write,
/// which is one of the ways a save can throw. `load` returns nothing so the
/// page opens on a blank form.
class _ThrowingStore implements DriverProfileStore {
  @override
  Future<void> save(DriverProfile profile) async =>
      throw Exception('disk write refused');
  @override
  Future<DriverProfile?> load() async => null;
}

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

  // Field-test bug (2026-08): a driver re-entered their whole registration and
  // "it wouldn't save". A save that fails must SAY so -- until now the store
  // write sat in a try with no catch, so a throw was swallowed and the driver
  // was left tapping a button that did nothing and gave no reason.
  testWidgets('a save that fails tells the driver and keeps them on the page', (
    tester,
  ) async {
    final (keyStore, pool) = await identityAndPool();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...productionOverrides(keyStore, pool),
          driverProfileStoreProvider.overrideWithValue(_ThrowingStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
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

    // Every field the save gate requires, so the button is live and the save
    // path is actually reached.
    for (final (key, value) in const [
      ('driverProfileFamilyNameField', 'Батбаяр'),
      ('driverProfileNameField', 'Мөнх'),
      ('driverProfileCarField', 'Приус'),
      ('driverProfileColorField', 'Цагаан'),
      ('driverProfilePlateField', '1234 УБА'),
      ('driverProfileKmTariffField', '2500'),
    ]) {
      await tester.enterText(find.byKey(Key(key)), value);
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Хадгалах'));
    await tester.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('mn'));
    // The failure is visible...
    expect(find.text(l.driverProfileSaveError), findsOneWidget);
    // ...and the driver is still on the form, not popped back as if it saved.
    expect(find.byType(DriverProfilePage), findsOneWidget);
  });

  // Field-test bug (2026-08), the other half of the fix: a driver who restored
  // their 12-word seed on a fresh phone found their registration blank,
  // because the profile store is keyed to the install, not the seed. But the
  // car and rates were published under their own pubkey, so on an empty store
  // the page fetches them back off the relay and prefills the form. The name
  // stays blank -- it was never published, and returns only when retyped.
  testWidgets('a fresh install with nothing cached fetches the driver own '
      'published car and rates back off the relay and prefills the form', (
    tester,
  ) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final identity = (await IdentityService(keyStore).load())!;
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();

    // An empty store -- the exact state of a phone that never saw this
    // registration. It is an in-memory one rather than the real
    // SharedPreferences store the rest of this file exercises, for a
    // mechanical reason: `SharedPreferences.getInstance` resolves through a
    // platform channel, off the test's fake clock, so the fetch timer it
    // leads to would become a real wall-clock timer that `tester.pump` cannot
    // advance. An in-memory store resolves in the fake zone, keeping the
    // whole restore chain -- and its four-second window -- under `pump`'s
    // control. What is under test here is the relay refetch, not the store.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...productionOverrides(keyStore, pool),
          driverProfileStoreProvider.overrideWithValue(
            InMemoryDriverProfileStore(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const DriverProfilePage(),
        ),
      ),
    );
    // Let initState resolve the empty load, await the identity, and open the
    // relay subscription -- all microtasks, no frames, so this settles while
    // the fetch window's timer keeps ticking.
    await tester.pumpAndSettle();

    // Answer that subscription with this driver's own published profile.
    final subId = _reqSubId(sockets['wss://a']!);
    final published = signEvent(
      buildDriverProfile(
        pubkey: identity.pubHex,
        now: 1000,
        car: 'Prius 41',
        color: 'мөнгөлөг',
        plate: '5678УБА',
        kmTariffMnt: 2800,
      ),
      identity.privHex,
    );
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, published.toJson()]));

    // Deliver the stream event to the collector, then advance past the fetch
    // window so its timer fires, the fill runs, and the form rebuilds.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    String fieldText(String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    expect(fieldText('driverProfileCarField'), 'Prius 41');
    expect(fieldText('driverProfileColorField'), 'мөнгөлөг');
    expect(fieldText('driverProfilePlateField'), '5678УБА');
    expect(fieldText('driverProfileKmTariffField'), '2800');
    // The name was never on a relay to fetch, so both name boxes stay blank
    // for the driver to retype -- the privacy asymmetry, intact on restore.
    expect(fieldText('driverProfileFamilyNameField'), '');
    expect(fieldText('driverProfileNameField'), '');
  });

  // The booking base (the flat fee that covers the drive to a booked
  // passenger) and the minimum fare (the floor the whole trip is lifted to)
  // must reach BOTH the local store AND the published kind-0. The published
  // half is the point of putting them on this form at all: a matched-trip
  // offer reads its rates from the published profile
  // (`driver_inbox_page.dart`), so a fee a driver can only set in the offline
  // taximeter's tariff form never reaches a booked ride. Setting them here is
  // the only way they price a Nostr-arranged trip.
  testWidgets('the booking base and minimum fare a driver sets are published '
      'and survive a reload', (tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(
      ['wss://a'],
      connect: (u) => sockets[u] = FakeRelaySocket(),
    );
    await pool.connectAll();

    await pumpProfile(tester, keyStore, pool);
    for (final (key, value) in const [
      ('driverProfileFamilyNameField', 'Батбаяр'),
      ('driverProfileNameField', 'Мөнх'),
      ('driverProfileCarField', 'Приус'),
      ('driverProfileColorField', 'Цагаан'),
      ('driverProfilePlateField', '1234 УБА'),
      ('driverProfileKmTariffField', '2500'),
      ('driverProfileBookingBaseField', '1500'),
      ('driverProfileMinFareField', '3000'),
    ]) {
      await tester.enterText(find.byKey(Key(key)), value);
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Хадгалах'));
    await tester.pumpAndSettle();

    // The published kind-0 carries both fees, because that is where a matched
    // offer reads its rates from.
    final published = _publishedProfileEvent(sockets['wss://a']!);
    final takhi =
        (jsonDecode(published['content'] as String)
                as Map<String, dynamic>)['takhi']
            as Map<String, dynamic>;
    expect(takhi['booking_base'], 1500);
    expect(takhi['min_fare'], 3000);

    // And they come back when the page is reopened -- proving _save read the
    // two boxes and the store round-tripped them.
    await pumpProfile(tester, keyStore, pool);
    String fieldText(String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    expect(fieldText('driverProfileBookingBaseField'), '1500');
    expect(fieldText('driverProfileMinFareField'), '3000');
  });
}

/// The event body of the last `["EVENT", <event>]` publish frame a socket was
/// handed. Publish frames are two elements (`RelayPool.publish`); a REQ frame
/// -- which the empty-store prefill also sends -- is three, so length picks
/// the publish out.
Map<String, dynamic> _publishedProfileEvent(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    if (decoded[0] == 'EVENT' && decoded.length == 2) {
      return decoded[1] as Map<String, dynamic>;
    }
  }
  throw StateError('no EVENT publish frame sent');
}

String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}
