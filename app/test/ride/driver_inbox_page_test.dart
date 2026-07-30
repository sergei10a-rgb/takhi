// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/nearby_requests_layer.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
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
      await profileStore.save(
        const DriverProfile(
          name: 'Бат',
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
    'the waiting rate through to ActiveTripView (spec §7.4)',
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
      await profileStore.save(
        const DriverProfile(
          name: 'Бат',
          car: 'Prius',
          color: 'цагаан',
          plate: '1234УНА',
          kmTariffMnt: 1500,
          waitTariffMntPerMinute: 300,
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
        find.text('${groupedMnt(1500)}\u00A0₮/км + 300\u00A0₮/мин хүлээлгэ'),
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
      await profileStore.save(
        const DriverProfile(
          name: 'Сараа',
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
        find.text('${groupedMnt(1200)}\u00A0₮/км, хүлээлгэ үнэгүй'),
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

  testWidgets(
    'a driver with no saved km-tariff sees no metered toggle, and the '
    'offer omits kmTariffMnt entirely',
    (tester) async {
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

      expect(find.text('Таксиметрээр (миний км-тариф)'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);

      await tester.enterText(find.byType(TextField).at(0), '4000');
      await tester.enterText(find.byType(TextField).at(1), '4');
      await tester.enterText(find.byType(TextField).at(2), 'Prius');
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
      expect(decodedOffer.kmTariffMnt, isNull);
    },
  );
}
