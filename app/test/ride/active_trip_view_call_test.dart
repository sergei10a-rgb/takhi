// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_providers.dart';
import 'package:takhi/call/call_screen.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_call_engine.dart';
import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

void main() {
  testWidgets(
    'passenger role: tapping the call button publishes a gift-wrapped '
    'call offer and pushes CallScreen',
    (tester) async {
      final passengerStore = InMemoryKeyStore();
      await IdentityService(passengerStore).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 95));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(passengerStore),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            callEngineFactoryProvider.overrideWithValue(
              (iceServers) => FakeCallEngine(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: Scaffold(
              body: ActiveTripView(
                role: TripRole.passenger,
                tripId: 'trip-call-1',
                counterpartyPubHex: driver.publicHex,
                agreedPriceMnt: 5000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // `CallScreen`'s dialing state shows an indefinite spinner, so
      // `pumpAndSettle` (which waits for all animation to stop) would time
      // out -- a handful of explicit pumps is enough to let the pushed
      // route settle and `CallService.startAsCaller` run to completion.
      await tester.tap(find.byIcon(Icons.call));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final offerFrame = sockets['wss://a']!.sent.lastWhere(
        (s) => s.contains('"kind":1059'),
      );
      final wrapEvent = NostrEvent.fromJson(
        (jsonDecode(offerFrame) as List<dynamic>)[1] as Map<String, dynamic>,
      );
      final unwrapped = nip17Unwrap(wrapEvent, driver.privateHex);
      final payload = RideDmPayload.decode(unwrapped.rumor.content);
      expect(payload, isA<CallOfferPayload>());
      expect((payload as CallOfferPayload).tripId, 'trip-call-1');

      expect(find.byType(CallScreen), findsOneWidget);
    },
  );

  testWidgets(
    'driver role: an incoming call offer surfaces the accept/decline '
    'overlay without any local button tap',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      final driverIdentity = await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 96));

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
            callEngineFactoryProvider.overrideWithValue(
              (iceServers) => FakeCallEngine(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: Scaffold(
              body: ActiveTripView(
                role: TripRole.driver,
                tripId: 'trip-call-2',
                counterpartyPubHex: passenger.publicHex,
                agreedPriceMnt: 5000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final callSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;

      final offerWrap = nip17Wrap(
        senderPrivHex: passenger.privateHex,
        recipientPubHex: driverIdentity.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const CallOfferPayload(
          tripId: 'trip-call-2',
          sdp: 'remote-offer-sdp',
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', callSubId, offerWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ирж буй дуудлага'), findsOneWidget);

      await tester.tap(find.text('Татгалзах'));
      await tester.pumpAndSettle();

      final hangupFrame = sockets['wss://a']!.sent.lastWhere(
        (s) => s.contains('"kind":1059'),
      );
      final hangupWrap = NostrEvent.fromJson(
        (jsonDecode(hangupFrame) as List<dynamic>)[1] as Map<String, dynamic>,
      );
      final unwrappedHangup = nip17Unwrap(hangupWrap, passenger.privateHex);
      final hangupPayload = RideDmPayload.decode(
        unwrappedHangup.rumor.content,
      );
      expect(hangupPayload, isA<CallHangupPayload>());
      expect(find.byType(CallScreen), findsNothing);
    },
  );
}
