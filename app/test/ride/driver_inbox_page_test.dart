// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/map/device_location_layer.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/nearby_requests_layer.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/driver_photo_store.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi/profile/profile_providers.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/driver_inbox_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// A driver who has already set a portrait.
///
/// `OfferService.sendOffer` refuses an offer that carries no name and no
/// photo (`driverOfferBlock`), and `DriverInboxPage` will not even open the
/// pricing dialog without them -- so every test here that reaches an offer
/// needs a driver who is actually allowed to make one.
Future<DriverPhotoStore> _seededPhotoStore() async {
  final store = InMemoryDriverPhotoStore();
  await store.save(Uint8List.fromList(List<int>.filled(900, 0x42)));
  return store;
}

/// Stands in for the on-device model, which no widget test can load.
class _AcceptingFaceDetector implements FaceDetector {
  const _AcceptingFaceDetector();
  @override
  Future<List<DetectedFace>> detect(Uint8List jpegBytes) async => const [
    DetectedFace(score: 0.95, left: 0.25, top: 0.2, width: 0.5, height: 0.5),
  ];
}

const _acceptingDetector = _AcceptingFaceDetector();

/// Everything a driver needs before `DriverInboxPage` will let them price a
/// job: a name, a portrait, and a face checker that can run.
Future<List<Override>> _completeDriverOverrides() async {
  final profileStore = InMemoryDriverProfileStore();
  await profileStore.save(
    const DriverProfile(
      familyName: 'Б.',
      givenName: 'Бат',
      car: 'Prius',
      color: 'цагаан',
      plate: '1234УНА',
      kmTariffMnt: 1500,
    ),
  );
  return [
    driverProfileStoreProvider.overrideWithValue(profileStore),
    driverPhotoStoreProvider.overrideWithValue(await _seededPhotoStore()),
    faceDetectorProvider.overrideWithValue(_acceptingDetector),
  ];
}

void main() {
  // `_sendOffer` (spec §7.2) now reads `driverProfileServiceProvider`
  // before every offer dialog opens, which -- unless overridden -- falls
  // through to the real `SharedPreferencesDriverProfileStore`. Without
  // this mock, `SharedPreferences.getInstance()` has no plugin registered
  // under `flutter_test` and the dialog would never open. Same pattern as
  // `passenger_ride_page_test.dart`'s own `setUp`.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Sukhbaatar Square -- matches `DriverInboxPage`'s own default map
  // center, so a request published here always lands inside the driver's
  // own geohash-6 cell (`DriverInboxService.nearbyRequests`'s `#g` filter)
  // without needing to pan the map first.
  const lat = 47.9186, lon = 106.9176;

  testWidgets('nearby request -> tap marker -> submit offer dialog -> handoff '
      'received drives the full DriverInboxPage state machine', (tester) async {
    final driverStore = InMemoryKeyStore();
    final driver = await IdentityService(driverStore).createNew();
    final passenger = generateKeyPair(List<int>.filled(32, 61));

    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());

    // Unlike `PassengerRidePage` (which only touches the relay pool
    // later, from a button tap), `DriverInboxPage.initState` starts
    // subscribing as soon as identity resolves -- which can happen
    // during the `pumpWidget` await itself. The pool must already be
    // connected before that happens, or `RelayPool.subscribe` iterates
    // zero sockets and silently sends no `REQ` frame at all.
    await pool.connectAll();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(driverStore),
          relayPoolProvider.overrideWithValue(pool),
          ...await _completeDriverOverrides(),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const DriverInboxPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // `_wireStreams` opens two subscriptions: nearby ride requests (kind
    // 20177) and this driver's own inbox for gift-wrapped handoffs (kind
    // 1059, tagged `#p` for the driver's pubkey).
    final listingsSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[20177]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;
    final handoffSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[1059]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;

    // A passenger's public ride request arrives right at the driver's
    // own map center. Unlike `DriverInboxService`'s own unit tests
    // (which inject a fake `nowSeconds`), `DriverInboxPage._wireStreams`
    // hardcodes the real wall clock for its expiry check -- so this
    // event's `now` must be real "now", or it reads as already expired
    // and `_listings` never gets it.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final unsignedRequest = buildRideRequest(
      pubkey: passenger.publicHex,
      now: now,
      pickupLat: lat,
      pickupLon: lon,
      destLat: lat,
      destLon: lon,
    );
    final requestEvent = signEvent(
      unsignedRequest,
      passenger.privateHex,
      auxRand: List<int>.filled(32, 0),
    );
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]),
    );
    await tester.pumpAndSettle();

    // The nearby-request marker is now on the map -- tap it to open
    // `_OfferDialog` (`DriverInboxPage._sendOffer`).
    expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_pin_circle));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3)); // price, eta, vehicle
    await tester.enterText(fields.at(0), '8000');
    await tester.enterText(fields.at(1), '5');
    await tester.enterText(fields.at(2), 'хөх Tucson');
    await tester.tap(find.text('Санал илгээх'));
    await tester.pumpAndSettle();

    // The dialog closed and the offer was actually published as a
    // gift-wrapped DM addressed to the passenger.
    expect(find.byType(AlertDialog), findsNothing);
    final offerFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    expect(offerFrame[0], 'EVENT');
    final offerWrap = NostrEvent.fromJson(
      offerFrame[1] as Map<String, dynamic>,
    );
    final unwrappedOffer = nip17Unwrap(offerWrap, passenger.privateHex);
    final decodedOffer =
        RideDmPayload.decode(unwrappedOffer.rumor.content) as RideOfferPayload;
    expect(decodedOffer.priceMnt, 8000);
    expect(decodedOffer.etaMinutes, 5);
    expect(decodedOffer.vehicleDescription, 'хөх Tucson');
    expect(decodedOffer.rideRequestId, requestEvent.id);

    // The passenger picks this driver: their exact pickup point arrives
    // back as a handoff (`DriverInboxPage._handoffSubscription`).
    final handoffWrap = nip17Wrap(
      senderPrivHex: passenger.privateHex,
      recipientPubHex: driver.pubHex,
      rumorKind: kRumorKindRideDm,
      content: const RideHandoffPayload(
        rideRequestId: 'req1',
        tripId: 'trip1',
        lat: lat,
        lon: lon,
        plusCode: '8Q7XJVMC+2V',
        landmarkText: 'Улаан хаалганы урд',
      ).encode(),
      now: 1000,
    );
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', handoffSubId, handoffWrap.toJson()]),
    );
    await tester.pumpAndSettle();

    // Switched from the map to the "awarded" view.
    expect(find.byType(NearbyRequestsLayer), findsNothing);
    expect(find.text('Зорчигчийн яг байршил'), findsOneWidget);
    expect(find.text('Улаан хаалганы урд'), findsOneWidget);
    expect(find.text('8Q7XJVMC+2V'), findsOneWidget);
  });

  testWidgets(
    'tapping "start trip" on the awarded-handoff view reaches ActiveTripView, '
    'carrying the minted trip id and the retained offer price',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      final driver = await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 62));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(driverStore),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            ...await _completeDriverOverrides(),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const DriverInboxPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listingsSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[20177]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;
      final handoffSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;

      // A real ride request first, so an actual offer (with a real,
      // non-zero, driver-chosen price) can be sent through `_OfferDialog`
      // before the handoff arrives -- otherwise `_lastOfferedPriceMnt`
      // would never be set and `agreedPriceMnt` would trivially fall back
      // to its `?? 0` default, which is exactly the regression this test
      // needs to catch.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final unsignedRequest = buildRideRequest(
        pubkey: passenger.publicHex,
        now: now,
        pickupLat: lat,
        pickupLon: lon,
        destLat: lat,
        destLon: lon,
      );
      final requestEvent = signEvent(
        unsignedRequest,
        passenger.privateHex,
        auxRand: List<int>.filled(32, 1),
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);
      await tester.tap(find.byIcon(Icons.person_pin_circle));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '9500');
      await tester.enterText(find.byType(TextField).at(1), '7');
      await tester.enterText(find.byType(TextField).at(2), 'ногоон Sonata');
      await tester.tap(find.text('Санал илгээх'));
      await tester.pumpAndSettle();

      final handoffWrap = nip17Wrap(
        senderPrivHex: passenger.privateHex,
        recipientPubHex: driver.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const RideHandoffPayload(
          rideRequestId: 'req2',
          tripId: 'trip2',
          lat: lat,
          lon: lon,
          plusCode: '8Q7XJVMC+2V',
          landmarkText: 'Улаан хаалганы урд',
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', handoffSubId, handoffWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Зорчигчийн яг байршил'), findsOneWidget);

      await tester.tap(find.text('Аялал эхлүүлэх'));
      await tester.pumpAndSettle();

      expect(find.byType(ActiveTripView), findsOneWidget);
      expect(find.text('Зорчигчийн яг байршил'), findsNothing);

      final activeTripView = tester.widget<ActiveTripView>(
        find.byType(ActiveTripView),
      );
      expect(activeTripView.role, TripRole.driver);
      expect(activeTripView.tripId, 'trip2');
      expect(activeTripView.counterpartyPubHex, passenger.publicHex);
      expect(activeTripView.agreedPriceMnt, 9500);
    },
  );

  testWidgets(
    'a handoff carrying a startCode gates the trip: "start" opens the code '
    'dialog, a wrong code is refused, and only the matching code reaches '
    'ActiveTripView (spec §7.1)',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      final driver = await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 63));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(driverStore),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            ...await _completeDriverOverrides(),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const DriverInboxPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listingsSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[20177]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;
      final handoffSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final unsignedRequest = buildRideRequest(
        pubkey: passenger.publicHex,
        now: now,
        pickupLat: lat,
        pickupLon: lon,
        destLat: lat,
        destLon: lon,
      );
      final requestEvent = signEvent(
        unsignedRequest,
        passenger.privateHex,
        auxRand: List<int>.filled(32, 1),
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_pin_circle));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '9500');
      await tester.enterText(find.byType(TextField).at(1), '7');
      await tester.enterText(find.byType(TextField).at(2), 'ногоон Sonata');
      await tester.tap(find.text('Санал илгээх'));
      await tester.pumpAndSettle();

      final handoffWrap = nip17Wrap(
        senderPrivHex: passenger.privateHex,
        recipientPubHex: driver.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const RideHandoffPayload(
          rideRequestId: 'req3',
          tripId: 'trip3',
          lat: lat,
          lon: lon,
          plusCode: '8Q7XJVMC+2V',
          landmarkText: 'Улаан хаалганы урд',
          startCode: '0421',
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', handoffSubId, handoffWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      // Tapping start does not begin the trip -- it asks for the code the
      // passenger is holding.
      await tester.tap(find.text('Аялал эхлүүлэх'));
      await tester.pumpAndSettle();
      expect(find.text('Зорчигчийн эхлэх код'), findsOneWidget);
      expect(find.byType(ActiveTripView), findsNothing);

      // A wrong code is refused and says so, without starting the meter.
      await tester.enterText(find.byType(TextField), '0000');
      await tester.tap(find.text('Баталгаажуулах'));
      await tester.pumpAndSettle();
      expect(
        find.text('Код таарахгүй байна. Зорчигчоос дахин асууна уу.'),
        findsOneWidget,
      );
      expect(find.byType(ActiveTripView), findsNothing);

      // The matching code clears the gate and the metered trip begins.
      await tester.enterText(find.byType(TextField), '0421');
      await tester.tap(find.text('Баталгаажуулах'));
      await tester.pumpAndSettle();
      expect(find.text('Зорчигчийн эхлэх код'), findsNothing);
      expect(find.byType(ActiveTripView), findsOneWidget);
      expect(
        tester.widget<ActiveTripView>(find.byType(ActiveTripView)).tripId,
        'trip3',
      );
    },
  );

  testWidgets(
    'a driver with a saved km-tariff sees a metered toggle in the offer '
    'dialog; enabling it attaches kmTariffMnt to the offer and threads it '
    'through to ActiveTripView (spec §7.2)',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      final driver = await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 71));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();
      final profileStore = InMemoryDriverProfileStore();
      final photoStore = await _seededPhotoStore();
      await profileStore.save(
        const DriverProfile(
          familyName: 'Б.',
          givenName: 'Бат',
          car: 'Prius',
          color: 'цагаан',
          plate: '1234УНА',
          kmTariffMnt: 1500,
        ),
      );

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(driverStore),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            driverProfileStoreProvider.overrideWithValue(profileStore),
            driverPhotoStoreProvider.overrideWithValue(photoStore),
            faceDetectorProvider.overrideWithValue(_acceptingDetector),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const DriverInboxPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listingsSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[20177]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;
      final handoffSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final requestEvent = signEvent(
        buildRideRequest(
          pubkey: passenger.publicHex,
          now: now,
          pickupLat: lat,
          pickupLon: lon,
          destLat: lat,
          destLon: lon,
        ),
        passenger.privateHex,
        auxRand: List<int>.filled(32, 2),
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_pin_circle));
      await tester.pumpAndSettle();

      expect(find.text('Таксиметрээр (миний км-тариф)'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), '9000');
      await tester.enterText(find.byType(TextField).at(1), '6');
      await tester.enterText(find.byType(TextField).at(2), 'улаан Tucson');
      await tester.tap(find.text('Санал илгээх'));
      await tester.pumpAndSettle();

      final offerFrame =
          jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
      final offerWrap = NostrEvent.fromJson(
        offerFrame[1] as Map<String, dynamic>,
      );
      final unwrappedOffer = nip17Unwrap(offerWrap, passenger.privateHex);
      final decodedOffer =
          RideDmPayload.decode(unwrappedOffer.rumor.content)
              as RideOfferPayload;
      expect(decodedOffer.kmTariffMnt, 1500);

      final handoffWrap = nip17Wrap(
        senderPrivHex: passenger.privateHex,
        recipientPubHex: driver.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const RideHandoffPayload(
          rideRequestId: 'req3',
          tripId: 'trip3',
          lat: lat,
          lon: lon,
          plusCode: '8Q7XJVMC+2V',
          landmarkText: 'Улаан хаалганы урд',
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', handoffSubId, handoffWrap.toJson()]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Аялал эхлүүлэх'));
      await tester.pumpAndSettle();

      final activeTripView = tester.widget<ActiveTripView>(
        find.byType(ActiveTripView),
      );
      expect(activeTripView.kmTariffMnt, 1500);
    },
  );

  testWidgets(
    'the metered toggle spells out both saved rates, and the offer carries '
    'the waiting rate, the booking base and the floor through to ActiveTripView '
    '(spec §7.4)',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      final driver = await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 73));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();
      final profileStore = InMemoryDriverProfileStore();
      final photoStore = await _seededPhotoStore();
      await profileStore.save(
        const DriverProfile(
          familyName: 'Б.',
          givenName: 'Бат',
          car: 'Prius',
          color: 'цагаан',
          plate: '1234УНА',
          kmTariffMnt: 1500,
          waitTariffMntPerMinute: 300,
          // The two per-trip fees the profile now publishes: a booked ride
          // must carry them the same way it carries the rates.
          bookingBaseMnt: 1500,
          minFareMnt: 3000,
        ),
      );

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(driverStore),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            driverProfileStoreProvider.overrideWithValue(profileStore),
            driverPhotoStoreProvider.overrideWithValue(photoStore),
            faceDetectorProvider.overrideWithValue(_acceptingDetector),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const DriverInboxPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listingsSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[20177]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;
      final handoffSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;

      final requestEvent = signEvent(
        buildRideRequest(
          pubkey: passenger.publicHex,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          pickupLat: lat,
          pickupLon: lon,
          destLat: lat,
          destLon: lon,
        ),
        passenger.privateHex,
        auxRand: List<int>.filled(32, 4),
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_pin_circle));
      await tester.pumpAndSettle();

      // Both halves of the metered price are on screen before the driver
      // commits to it -- a rate they cannot see is a rate they cannot check.
      expect(
        find.text('${groupedMnt(1500)}\u00A0₮/км + 300\u00A0₮/мин зогсолт'),
        findsOneWidget,
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), '9000');
      await tester.enterText(find.byType(TextField).at(1), '6');
      await tester.enterText(find.byType(TextField).at(2), 'улаан Tucson');
      await tester.tap(find.text('Санал илгээх'));
      await tester.pumpAndSettle();

      final offerWrap = NostrEvent.fromJson(
        (jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>)[1]
            as Map<String, dynamic>,
      );
      final decodedOffer =
          RideDmPayload.decode(
                nip17Unwrap(offerWrap, passenger.privateHex).rumor.content,
              )
              as RideOfferPayload;
      expect(decodedOffer.kmTariffMnt, 1500);
      expect(decodedOffer.waitTariffMntPerMinute, 300);
      expect(decodedOffer.bookingBaseMnt, 1500);
      expect(decodedOffer.minFareMnt, 3000);

      final handoffWrap = nip17Wrap(
        senderPrivHex: passenger.privateHex,
        recipientPubHex: driver.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const RideHandoffPayload(
          rideRequestId: 'req4',
          tripId: 'trip4',
          lat: lat,
          lon: lon,
          plusCode: '8Q7XJVMC+2V',
          landmarkText: 'Улаан хаалганы урд',
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', handoffSubId, handoffWrap.toJson()]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Аялал эхлүүлэх'));
      await tester.pumpAndSettle();

      final activeTripView = tester.widget<ActiveTripView>(
        find.byType(ActiveTripView),
      );
      expect(activeTripView.kmTariffMnt, 1500);
      expect(activeTripView.waitTariffMntPerMinute, 300);
      expect(activeTripView.bookingBaseMnt, 1500);
      expect(activeTripView.minFareMnt, 3000);
    },
  );

  testWidgets(
    'a km-tariff with no waiting rate is a valid metered offer -- the toggle '
    'says waiting is free and nothing blocks sending it',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 74));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final profileStore = InMemoryDriverProfileStore();
      final photoStore = await _seededPhotoStore();
      await profileStore.save(
        const DriverProfile(
          familyName: 'Ц.',
          givenName: 'Сараа',
          car: 'Sonata',
          color: 'улаан',
          plate: '4321ЭЖӨ',
          kmTariffMnt: 1200,
        ),
      );

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(driverStore),
            relayPoolProvider.overrideWithValue(pool),
            driverProfileStoreProvider.overrideWithValue(profileStore),
            driverPhotoStoreProvider.overrideWithValue(photoStore),
            faceDetectorProvider.overrideWithValue(_acceptingDetector),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const DriverInboxPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listingsSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[20177]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;
      final requestEvent = signEvent(
        buildRideRequest(
          pubkey: passenger.publicHex,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          pickupLat: lat,
          pickupLon: lon,
          destLat: lat,
          destLon: lon,
        ),
        passenger.privateHex,
        auxRand: List<int>.filled(32, 5),
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_pin_circle));
      await tester.pumpAndSettle();

      expect(
        find.text('${groupedMnt(1200)}\u00A0₮/км, зогсолт үнэгүй'),
        findsOneWidget,
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), '7000');
      await tester.enterText(find.byType(TextField).at(1), '5');
      await tester.enterText(find.byType(TextField).at(2), 'улаан Sonata');
      await tester.tap(find.text('Санал илгээх'));
      await tester.pumpAndSettle();

      final offerWrap = NostrEvent.fromJson(
        (jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>)[1]
            as Map<String, dynamic>,
      );
      final decodedOffer =
          RideDmPayload.decode(
                nip17Unwrap(offerWrap, passenger.privateHex).rumor.content,
              )
              as RideOfferPayload;
      expect(decodedOffer.kmTariffMnt, 1200);
      expect(decodedOffer.waitTariffMntPerMinute, 0);
    },
  );

  testWidgets('a driver who has not filled in their profile never reaches the '
      'pricing dialog at all', (tester) async {
    final driverStore = InMemoryKeyStore();
    await IdentityService(driverStore).createNew();
    final passenger = generateKeyPair(List<int>.filled(32, 72));

    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());

    await pool.connectAll();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(driverStore),
          relayPoolProvider.overrideWithValue(pool),
          driverProfileStoreProvider.overrideWithValue(
            InMemoryDriverProfileStore(),
          ),
          driverPhotoStoreProvider.overrideWithValue(
            InMemoryDriverPhotoStore(),
          ),
          faceDetectorProvider.overrideWithValue(_acceptingDetector),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const DriverInboxPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listingsSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[20177]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final requestEvent = signEvent(
      buildRideRequest(
        pubkey: passenger.publicHex,
        now: now,
        pickupLat: lat,
        pickupLon: lon,
        destLat: lat,
        destLon: lon,
      ),
      passenger.privateHex,
      auxRand: List<int>.filled(32, 3),
    );
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_pin_circle));
    await tester.pumpAndSettle();

    // This case used to be "a driver with no saved km-tariff sees no
    // metered toggle". That scenario is no longer reachable: the driver's
    // name now lives in `DriverProfile` alongside the tariff, so a driver
    // with no profile has no name either -- and one without a name and a
    // portrait is refused before the dialog opens. Every driver who can
    // price a job therefore has a km-tariff, because the profile form
    // will not save without one.
    //
    // So the case is rewritten to assert what is now true, rather than
    // deleted: walking someone through a pricing dialog whose offer
    // `OfferService.sendOffer` would refuse at the end wastes their time
    // in front of a waiting passenger.
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      sockets['wss://a']!.sent.any((s) => s.contains('"kind":1059')),
      isFalse,
      reason: 'an incomplete driver published an offer',
    );
  });

  // Refusing the offer is correct; refusing it *in silence* is not. A tap
  // that produces nothing at all is indistinguishable from a broken app,
  // and the driver is standing in front of a passenger who is about to
  // pick somebody else. These two cases pin the two halves of
  // `driverOfferBlock` to the two sentences that name them, and both to
  // the one screen that fixes either.

  /// Pumps `DriverInboxPage` under a real router, emits one nearby request
  /// at the driver's own map centre, and taps its marker. Returns the list
  /// the driver-profile route appends to when it is actually reached.
  Future<List<String>> tapRequestAsBlockedDriver(
    WidgetTester tester, {
    required DriverProfile? profile,
    required int auxSeed,
  }) async {
    final driverStore = InMemoryKeyStore();
    await IdentityService(driverStore).createNew();
    final passenger = generateKeyPair(List<int>.filled(32, auxSeed));

    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    final profileStore = InMemoryDriverProfileStore();
    if (profile != null) await profileStore.save(profile);

    final pushed = <String>[];
    await pool.connectAll();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(driverStore),
          relayPoolProvider.overrideWithValue(pool),
          driverProfileStoreProvider.overrideWithValue(profileStore),
          // No portrait in either case: the name is what decides which of
          // the two sentences `driverOfferBlock` reports, because it names
          // the missing name first.
          driverPhotoStoreProvider.overrideWithValue(
            InMemoryDriverPhotoStore(),
          ),
          faceDetectorProvider.overrideWithValue(_acceptingDetector),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          routerConfig: GoRouter(
            initialLocation: '/ride/driver',
            routes: [
              GoRoute(
                path: '/ride/driver',
                builder: (context, state) => const DriverInboxPage(),
              ),
              GoRoute(
                path: '/settings/driver-profile',
                builder: (context, state) {
                  pushed.add('/settings/driver-profile');
                  return const Scaffold(body: Text('driver-profile-stub'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listingsSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[20177]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;
    final requestEvent = signEvent(
      buildRideRequest(
        pubkey: passenger.publicHex,
        now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pickupLat: lat,
        pickupLon: lon,
        destLat: lat,
        destLon: lon,
      ),
      passenger.privateHex,
      auxRand: List<int>.filled(32, auxSeed),
    );
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_pin_circle));
    await tester.pumpAndSettle();
    return pushed;
  }

  testWidgets('a driver with no saved name is told so, and the message '
      'carries a way to the profile screen', (tester) async {
    final pushed = await tapRequestAsBlockedDriver(
      tester,
      profile: null,
      auxSeed: 81,
    );

    expect(
      find.text('Санал илгээхийн тулд эхлээд овог, нэрээ бөглөнө үү.'),
      findsOneWidget,
      reason: 'the tap was refused without saying why',
    );
    // Still refused -- the point is that the driver is told, not that the
    // rule was relaxed.
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('Профайл'));
    await tester.pumpAndSettle();
    expect(pushed, ['/settings/driver-profile']);
  });

  testWidgets('a driver whose name is saved but who has no portrait is told '
      'about the photo rather than the name', (tester) async {
    final pushed = await tapRequestAsBlockedDriver(
      tester,
      profile: const DriverProfile(
        familyName: 'Б.',
        givenName: 'Бат',
        car: 'Prius',
        color: 'цагаан',
        plate: '1234УНА',
        kmTariffMnt: 1500,
      ),
      auxSeed: 82,
    );

    expect(
      find.text('Санал илгээхийн тулд эхлээд зургаа оруулна уу.'),
      findsOneWidget,
    );
    expect(
      find.text('Санал илгээхийн тулд эхлээд овог, нэрээ бөглөнө үү.'),
      findsNothing,
      reason: 'a driver with a saved name was told to fill in their name',
    );

    await tester.tap(find.text('Профайл'));
    await tester.pumpAndSettle();
    expect(pushed, ['/settings/driver-profile']);
  });

  testWidgets('marks the driver\'s own car on the map of nearby calls -- '
      'a screen full of pins with nothing standing for YOU cannot answer '
      '"which of these is close"', (tester) async {
    final driverStore = InMemoryKeyStore();
    await IdentityService(driverStore).createNew();
    final pool = RelayPool(['wss://a'], connect: (_) => FakeRelaySocket());
    final location = FakeLocationSource();
    addTearDown(location.dispose);
    await pool.connectAll();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(driverStore),
          relayPoolProvider.overrideWithValue(pool),
          locationSourceProvider.overrideWithValue(location),
          locationPermissionCheckProvider.overrideWithValue(() async => true),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const DriverInboxPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DeviceLocationLayer), findsNothing);

    location.emit(
      const GpsFix(
        lat: lat,
        lon: lon,
        timestampSeconds: 1000,
        accuracyMeters: 25,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DeviceLocationLayer), findsOneWidget);
    final circles = tester
        .widgetList<CircleLayer>(find.byType(CircleLayer))
        .expand((layer) => layer.circles);
    expect(circles.single.radius, 25);
  });

  testWidgets('a refused location permission leaves the inbox exactly as it '
      'was -- listening for calls does not depend on GPS', (tester) async {
    final driverStore = InMemoryKeyStore();
    await IdentityService(driverStore).createNew();
    final pool = RelayPool(['wss://a'], connect: (_) => FakeRelaySocket());
    await pool.connectAll();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(driverStore),
          relayPoolProvider.overrideWithValue(pool),
          locationSourceProvider.overrideWithValue(FakeLocationSource()),
          locationPermissionCheckProvider.overrideWithValue(() async => false),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const DriverInboxPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DeviceLocationLayer), findsNothing);
    expect(find.text('Дуудлага сонсож байна'), findsOneWidget);
  });
}
