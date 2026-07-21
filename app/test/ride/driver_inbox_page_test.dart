// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/nearby_requests_layer.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/driver_inbox_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
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
}
