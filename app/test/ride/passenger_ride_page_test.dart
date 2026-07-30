// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/call/phone_share_settings.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/passenger_ride_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// Picks the offer whose summary contains [priceText]. Tapping the tile is
/// no longer enough on its own: an exact pickup point (and possibly a phone
/// number) is about to leave the device, so `_select` confirms first.
Future<void> _selectOffer(WidgetTester tester, String priceText) async {
  await tester.tap(find.textContaining(priceText));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Тийм, илгээх'));
  await tester.pumpAndSettle();
}

void main() {
  // `_select` (Task 5) reads `phoneShareSettingsStoreProvider`, which is
  // backed by real `shared_preferences` -- without this mock, `_select`'s
  // very first await throws in the test environment and the widget never
  // advances past the offers step. Same pattern as
  // `tariff_store_test.dart`/`meter_journal_test.dart`.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pickup -> destination -> price -> publish -> ranked offer -> '
      'selecting sends a handoff', (tester) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 111));

    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(store),
          relayPoolProvider.overrideWithValue(pool),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const PassengerRidePage(),
        ),
      ),
    );
    await pool.connectAll();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Үргэлжлүүл').first); // pickup -> destination
    await tester.pump();
    await tester.tap(find.text('Үргэлжлүүл').first); // destination -> price
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.tap(find.text('Нийтлэх')); // price -> publish
    await tester.pumpAndSettle();

    final rideRequestFrame =
        jsonDecode(
              sockets['wss://a']!.sent.firstWhere(
                (s) => s.contains('"kind":20177'),
              ),
            )
            as List<dynamic>;
    final rideRequestId =
        (rideRequestFrame[1] as Map<String, dynamic>)['id'] as String;

    final offerWrap = nip17Wrap(
      senderPrivHex: driver.privateHex,
      recipientPubHex: identity.pubHex,
      rumorKind: kRumorKindRideDm,
      content: RideOfferPayload(
        rideRequestId: rideRequestId,
        priceMnt: 6000,
        etaMinutes: 3,
        vehicleDescription: 'цагаан Prius',
      ).encode(),
      now: 1000,
    );
    final inboxSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[1059]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', inboxSubId, offerWrap.toJson()]),
    );
    await tester.pumpAndSettle();
    // Flush TripReceiptRepository.receiptsAbout's real 3-second collection
    // window (kicked off by the offer arriving) -- pumpAndSettle alone
    // won't advance fake-async time this far because nothing re-schedules
    // a frame while it's pending, so the delayed Future is left dangling
    // (failing the "no pending timers" test-teardown invariant) unless
    // explicitly pumped past its deadline here.
    await tester.pump(const Duration(seconds: 3));

    expect(find.textContaining(groupedMnt(6000)), findsOneWidget);

    await _selectOffer(tester, groupedMnt(6000));

    expect(find.textContaining('Prius'), findsOneWidget);
  });

  testWidgets('tapping "go to trip" on the done step reaches ActiveTripView', (
    tester,
  ) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 112));

    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    final fakeLocation = FakeLocationSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(store),
          relayPoolProvider.overrideWithValue(pool),
          locationSourceProvider.overrideWithValue(fakeLocation),
          locationPermissionCheckProvider.overrideWithValue(() async => true),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: const PassengerRidePage(),
        ),
      ),
    );
    await pool.connectAll();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Үргэлжлүүл').first); // pickup -> destination
    await tester.pump();
    await tester.tap(find.text('Үргэлжлүүл').first); // destination -> price
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.tap(find.text('Нийтлэх')); // price -> publish
    await tester.pumpAndSettle();

    final rideRequestFrame =
        jsonDecode(
              sockets['wss://a']!.sent.firstWhere(
                (s) => s.contains('"kind":20177'),
              ),
            )
            as List<dynamic>;
    final rideRequestId =
        (rideRequestFrame[1] as Map<String, dynamic>)['id'] as String;

    final offerWrap = nip17Wrap(
      senderPrivHex: driver.privateHex,
      recipientPubHex: identity.pubHex,
      rumorKind: kRumorKindRideDm,
      content: RideOfferPayload(
        rideRequestId: rideRequestId,
        priceMnt: 6000,
        etaMinutes: 3,
        vehicleDescription: 'цагаан Prius',
      ).encode(),
      now: 1000,
    );
    final inboxSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[1059]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', inboxSubId, offerWrap.toJson()]),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.textContaining(groupedMnt(6000)), findsOneWidget);

    await _selectOffer(tester, groupedMnt(6000));

    expect(find.textContaining('Prius'), findsOneWidget);

    await tester.tap(find.text('Аялал руу очих'));
    await tester.pumpAndSettle();

    // Decrypt the handoff DM `_select` actually sent over the wire (a
    // kind-1059 gift wrap -- the only one this passenger side ever
    // publishes) to learn the trip id `HandoffService` minted for it --
    // that same id must be the one threaded into `ActiveTripView` below,
    // not some hardcoded or empty placeholder. Not simply `.sent.last`:
    // reaching `ActiveTripView` opens its own subscriptions afterwards,
    // which would be the actual last frame sent.
    final handoffFrame =
        jsonDecode(
              sockets['wss://a']!.sent.lastWhere(
                (s) => s.contains('"kind":1059'),
              ),
            )
            as List<dynamic>;
    expect(handoffFrame[0], 'EVENT');
    final handoffWrapEvent = NostrEvent.fromJson(
      handoffFrame[1] as Map<String, dynamic>,
    );
    final unwrappedHandoff = nip17Unwrap(handoffWrapEvent, driver.privateHex);
    final decodedHandoff =
        RideDmPayload.decode(unwrappedHandoff.rumor.content)
            as RideHandoffPayload;

    final activeTripView = tester.widget<ActiveTripView>(
      find.byType(ActiveTripView),
    );
    expect(activeTripView.role, TripRole.passenger);
    expect(activeTripView.tripId, decodedHandoff.tripId);
    expect(activeTripView.tripId, isNotEmpty);
    expect(activeTripView.counterpartyPubHex, driver.publicHex);
    expect(activeTripView.agreedPriceMnt, 6000);
  });

  testWidgets(
    'the offer list spells out both halves of a metered price, says so when '
    'waiting is free, and leaves a fixed-price offer a single figure (§7.4)',
    (tester) async {
      final store = InMemoryKeyStore();
      final identity = await IdentityService(store).createNew();
      final meteredDriver = generateKeyPair(List<int>.filled(32, 121));
      final waitFreeDriver = generateKeyPair(List<int>.filled(32, 122));
      final fixedDriver = generateKeyPair(List<int>.filled(32, 123));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(store),
            relayPoolProvider.overrideWithValue(pool),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const PassengerRidePage(),
          ),
        ),
      );
      await pool.connectAll();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Үргэлжлүүл').first);
      await tester.pump();
      await tester.tap(find.text('Үргэлжлүүл').first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.tap(find.text('Нийтлэх'));
      await tester.pumpAndSettle();

      final rideRequestFrame =
          jsonDecode(
                sockets['wss://a']!.sent.firstWhere(
                  (s) => s.contains('"kind":20177'),
                ),
              )
              as List<dynamic>;
      final rideRequestId =
          (rideRequestFrame[1] as Map<String, dynamic>)['id'] as String;
      final inboxSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;

      void emitOffer(KeyPair from, RideOfferPayload offer) {
        sockets['wss://a']!.emit(
          jsonEncode([
            'EVENT',
            inboxSubId,
            nip17Wrap(
              senderPrivHex: from.privateHex,
              recipientPubHex: identity.pubHex,
              rumorKind: kRumorKindRideDm,
              content: offer.encode(),
              now: 1000,
            ).toJson(),
          ]),
        );
      }

      emitOffer(
        meteredDriver,
        RideOfferPayload(
          rideRequestId: rideRequestId,
          priceMnt: 6000,
          etaMinutes: 3,
          vehicleDescription: 'цагаан Prius',
          kmTariffMnt: 1200,
          waitTariffMntPerMinute: 300,
        ),
      );
      emitOffer(
        waitFreeDriver,
        RideOfferPayload(
          rideRequestId: rideRequestId,
          priceMnt: 6500,
          etaMinutes: 4,
          vehicleDescription: 'улаан Sonata',
          kmTariffMnt: 1000,
        ),
      );
      emitOffer(
        fixedDriver,
        RideOfferPayload(
          rideRequestId: rideRequestId,
          priceMnt: 7000,
          etaMinutes: 5,
          vehicleDescription: 'хөх Tucson',
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // This is the moment the passenger decides -- neither rate may be
      // rounded away, hidden behind a tap, or implied.
      expect(
        find.text('${groupedMnt(1200)}\u00A0₮/км + 300\u00A0₮/мин хүлээлгэ'),
        findsOneWidget,
      );
      expect(
        find.text('${groupedMnt(1000)}\u00A0₮/км, хүлээлгэ үнэгүй'),
        findsOneWidget,
      );
      // The fixed-price offer stays a single figure: quoting a per-km rate
      // beside it would describe a charge that never applies.
      expect(find.textContaining('₮/км'), findsNWidgets(2));

      // A driver who never set a waiting rate is still perfectly selectable.
      await _selectOffer(tester, groupedMnt(6500));
      expect(find.textContaining('Sonata'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a metered offer (spec §7.2) threads its kmTariffMnt into '
    'ActiveTripView; a plain fixed-price offer threads null',
    (tester) async {
      final store = InMemoryKeyStore();
      final identity = await IdentityService(store).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 113));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(store),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const PassengerRidePage(),
          ),
        ),
      );
      await pool.connectAll();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Үргэлжлүүл').first);
      await tester.pump();
      await tester.tap(find.text('Үргэлжлүүл').first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.tap(find.text('Нийтлэх'));
      await tester.pumpAndSettle();

      final rideRequestFrame =
          jsonDecode(
                sockets['wss://a']!.sent.firstWhere(
                  (s) => s.contains('"kind":20177'),
                ),
              )
              as List<dynamic>;
      final rideRequestId =
          (rideRequestFrame[1] as Map<String, dynamic>)['id'] as String;

      final offerWrap = nip17Wrap(
        senderPrivHex: driver.privateHex,
        recipientPubHex: identity.pubHex,
        rumorKind: kRumorKindRideDm,
        content: RideOfferPayload(
          rideRequestId: rideRequestId,
          priceMnt: 7000,
          etaMinutes: 5,
          vehicleDescription: 'хар Sonata',
          kmTariffMnt: 1500,
        ).encode(),
        now: 1000,
      );
      final inboxSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', inboxSubId, offerWrap.toJson()]),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(find.textContaining(groupedMnt(7000)), findsOneWidget);
      await _selectOffer(tester, groupedMnt(7000));
      await tester.tap(find.text('Аялал руу очих'));
      await tester.pumpAndSettle();

      final activeTripView = tester.widget<ActiveTripView>(
        find.byType(ActiveTripView),
      );
      expect(activeTripView.kmTariffMnt, 1500);
    },
  );

  testWidgets(
    'selecting an offer with a saved own phone number includes it in the '
    'handoff DM sent to the driver (spec §7.3-②)',
    (tester) async {
      // Unlike the `setUp` above (empty mock prefs), this test seeds a
      // saved own phone number before the widget is built, so `_select`'s
      // `phoneShareSettingsStoreProvider.loadOwnPhone()` call actually
      // returns a number -- exercising the phone-included branch of
      // `_select` (Task 5's actual feature) through the real screen,
      // rather than only directly against
      // `HandoffService.sendHandoff(phone: ...)` one layer down.
      SharedPreferences.setMockInitialValues({});
      final phoneStore = SharedPreferencesPhoneShareSettingsStore(
        SharedPreferences.getInstance,
      );
      await phoneStore.saveOwnPhone('99112233');

      final store = InMemoryKeyStore();
      final identity = await IdentityService(store).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 113));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(store),
            relayPoolProvider.overrideWithValue(pool),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const PassengerRidePage(),
          ),
        ),
      );
      await pool.connectAll();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Үргэлжлүүл').first); // pickup -> destination
      await tester.pump();
      await tester.tap(find.text('Үргэлжлүүл').first); // destination -> price
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.tap(find.text('Нийтлэх')); // price -> publish
      await tester.pumpAndSettle();

      final rideRequestFrame =
          jsonDecode(
                sockets['wss://a']!.sent.firstWhere(
                  (s) => s.contains('"kind":20177'),
                ),
              )
              as List<dynamic>;
      final rideRequestId =
          (rideRequestFrame[1] as Map<String, dynamic>)['id'] as String;

      final offerWrap = nip17Wrap(
        senderPrivHex: driver.privateHex,
        recipientPubHex: identity.pubHex,
        rumorKind: kRumorKindRideDm,
        content: RideOfferPayload(
          rideRequestId: rideRequestId,
          priceMnt: 6000,
          etaMinutes: 3,
          vehicleDescription: 'цагаан Prius',
        ).encode(),
        now: 1000,
      );
      final inboxSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', inboxSubId, offerWrap.toJson()]),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(find.textContaining(groupedMnt(6000)), findsOneWidget);

      await _selectOffer(tester, groupedMnt(6000));

      final handoffFrame =
          jsonDecode(
                sockets['wss://a']!.sent.lastWhere(
                  (s) => s.contains('"kind":1059'),
                ),
              )
              as List<dynamic>;
      final handoffWrapEvent = NostrEvent.fromJson(
        handoffFrame[1] as Map<String, dynamic>,
      );
      final unwrappedHandoff = nip17Unwrap(handoffWrapEvent, driver.privateHex);
      final decodedHandoff =
          RideDmPayload.decode(unwrappedHandoff.rumor.content)
              as RideHandoffPayload;

      expect(decodedHandoff.phone, '99112233');
    },
  );
}
