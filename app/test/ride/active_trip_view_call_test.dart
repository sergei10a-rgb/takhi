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

  testWidgets('passenger role: a helper announcement received before the call '
      'button is tapped reaches CallScreen as a turn: ICE server (Plan 5 '
      'CRITICAL-1 fix -- previously buildIceServers() was always called '
      'with no helpers at all)', (tester) async {
    final passengerStore = InMemoryKeyStore();
    await IdentityService(passengerStore).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 98));

    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    final fakeLocation = FakeLocationSource();

    List<Map<String, dynamic>>? capturedIceServers;

    await pool.connectAll();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(passengerStore),
          relayPoolProvider.overrideWithValue(pool),
          locationSourceProvider.overrideWithValue(fakeLocation),
          locationPermissionCheckProvider.overrideWithValue(() async => true),
          callEngineFactoryProvider.overrideWithValue((iceServers) {
            capturedIceServers = iceServers;
            return FakeCallEngine();
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Scaffold(
            body: ActiveTripView(
              role: TripRole.passenger,
              tripId: 'trip-call-helper',
              counterpartyPubHex: driver.publicHex,
              agreedPriceMnt: 5000,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // `ActiveTripView.initState` already warmed up
    // `helperDirectoryProvider` -- find its kind-30178 REQ and answer it
    // with a real announcement before ever tapping the call button, so
    // the accumulator has something to hand `CallScreen` by call time.
    final helperSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[30178]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;
    // `HelperDirectoryService.watchHelpers`/`HelperDirectory.current()`
    // both default their own `now` to the real system clock, so this
    // announcement's `now`/`expirySeconds` must be realistic or it is
    // silently dropped as "already expired" before ever reaching the
    // accumulator.
    final helperEvent = buildHelperAnnouncement(
      pubkey: 'ab' * 32,
      now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      helperId: 'h1',
      host: 'turn.example.mn',
      port: 3478,
      credential: 'secret',
    );
    final helperKeys = generateKeyPair(List<int>.filled(32, 9));
    final signedHelper = signEvent(
      helperEvent.copyWith(id: computeEventId(helperEvent)),
      helperKeys.privateHex,
    );
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', helperSubId, signedHelper.toJson()]),
    );
    await tester.pump(const Duration(milliseconds: 10));

    await tester.tap(find.byIcon(Icons.call));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(capturedIceServers, isNotNull);
    expect(capturedIceServers!.length, 2);
    expect(capturedIceServers![1]['urls'], ['turn:turn.example.mn:3478']);
    expect(capturedIceServers![1]['credential'], 'secret');
  });

  testWidgets('driver role: an incoming call offer surfaces the accept/decline '
      'overlay without any local button tap', (tester) async {
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

    // `ActiveTripView.initState`'s own voice-note subscription (Plan 5
    // review CRITICAL-3 fix) also opens a kind-1059 subscription, and --
    // being wired synchronously in `_startTracking`, unconditionally for
    // both roles -- always does so *before* this sibling
    // `IncomingCallListener` widget's own kind-1059 call-signal
    // subscription (see `_startTracking`'s doc comment on subscription
    // ordering). So for the driver role specifically (which has no
    // `_statusSubscription` competing for "first"), the call-signal
    // subscription is reliably the *last* kind-1059 REQ sent by the time
    // `pumpAndSettle` settles, not the first.
    final callSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.lastWhere(
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
    final hangupPayload = RideDmPayload.decode(unwrappedHangup.rumor.content);
    expect(hangupPayload, isA<CallHangupPayload>());
    expect(find.byType(CallScreen), findsNothing);
  });
}
