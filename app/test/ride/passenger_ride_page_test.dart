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
import 'package:takhi/ride/ride_providers.dart';
import 'package:takhi/ride/trip_receipt_repository.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// Picks the offer whose summary contains [priceText]. Three steps, not one:
/// the tile opens the driver's own page (face, name, car, tariffs, key, and
/// the plain statement that the photo is unverified), that page's action asks
/// `_select` for the driver, and `_select` still confirms before an exact
/// pickup point -- and possibly a phone number -- leaves the device.
Future<void> _selectOffer(WidgetTester tester, String priceText) async {
  // Scrolled to first: the list is a `ListView` under a heading, a sort
  // control and an action sheet, so on a short surface the third offer is
  // genuinely below the fold. Tapping through the sheet that covers it would
  // be testing a screen no rider has.
  await tester.ensureVisible(find.textContaining(priceText));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(priceText));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Энэ жолоочийг сонгох'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Тийм, илгээх'));
  await tester.pumpAndSettle();
}

/// Serves whatever receipts a test has staged for a driver, instead of
/// collecting them off a relay for three real seconds.
///
/// `implements` rather than a subclass: the real repository takes a
/// `RelayPool` and this test has nothing for it to talk to. Only
/// `receiptsAbout` is on the interface, and it is the whole of what
/// `PassengerRidePage` calls.
class _StagedReceipts implements TripReceiptRepository {
  _StagedReceipts(this.byDriver);

  final Map<String, List<TripReceipt>> byDriver;

  @override
  Future<List<TripReceipt>> receiptsAbout(
    String subjectPubkey, {
    Duration timeout = const Duration(seconds: 3),
  }) async => byDriver[subjectPubkey] ?? const [];

  /// The passenger's booking flow never publishes a receipt -- that happens
  /// at the end of `ActiveTripView`, past every screen this file drives --
  /// so a call here means the test is exercising something it did not mean
  /// to, and should say so rather than quietly do nothing.
  @override
  Future<NostrEvent> publish({
    required String privHex,
    required int now,
    required String tripId,
    required String counterpartyPubkey,
    required String role,
    required int ratingStars,
    required int distanceMeters,
    required int durationSeconds,
    required int priceMnt,
    int waitingSeconds = 0,
    int waitingFareMnt = 0,
    String comment = '',
  }) => throw UnimplementedError('the offers step publishes no receipts');
}

/// One trip both sides signed off on: the rider's receipt about the driver
/// and the driver's counter-receipt about the rider. `computeReputation`
/// counts a trip only when both exist for the same `tripId` -- a driver who
/// rates themselves, or a rider who rates a driver who never rated back,
/// contributes nothing (spec §9).
List<TripReceipt> _pairedTrip({
  required String tripId,
  required String riderPubkey,
  required String driverPubkey,
  required int stars,
}) => [
  TripReceipt(
    tripId: tripId,
    counterpartyPubkey: driverPubkey,
    role: 'passenger',
    ratingStars: stars,
    distanceMeters: 4200,
    durationSeconds: 600,
    priceMnt: 6000,
    comment: '',
    authorPubkey: riderPubkey,
    createdAt: 1000,
  ),
  TripReceipt(
    tripId: tripId,
    counterpartyPubkey: riderPubkey,
    role: 'driver',
    ratingStars: 5,
    distanceMeters: 4200,
    durationSeconds: 600,
    priceMnt: 6000,
    comment: '',
    authorPubkey: driverPubkey,
    createdAt: 1000,
  ),
];

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
        find.text('${groupedMnt(1200)}\u00A0₮/км + 300\u00A0₮/мин зогсолт'),
        findsOneWidget,
      );
      expect(
        find.text('${groupedMnt(1000)}\u00A0₮/км, зогсолт үнэгүй'),
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

  testWidgets(
    'the offer list states each driver\'s reputation as trips both sides '
    'confirmed, and marks the one that actually leads (spec §9)',
    (tester) async {
      // A real handset, not the 800x600 test default: this is the app's
      // busiest card -- avatar, key, rating, fare, ETA, car, two tariffs --
      // and the width it has to survive is a phone's.
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final store = InMemoryKeyStore();
      final identity = await IdentityService(store).createNew();
      final trusted = generateKeyPair(List<int>.filled(32, 131));
      final newcomer = generateKeyPair(List<int>.filled(32, 132));
      final riderOne = generateKeyPair(List<int>.filled(32, 141));
      final riderTwo = generateKeyPair(List<int>.filled(32, 142));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(store),
            relayPoolProvider.overrideWithValue(pool),
            tripReceiptRepositoryProvider.overrideWithValue(
              _StagedReceipts({
                trusted.publicHex: [
                  ..._pairedTrip(
                    tripId: 't1',
                    riderPubkey: riderOne.publicHex,
                    driverPubkey: trusted.publicHex,
                    stars: 5,
                  ),
                  ..._pairedTrip(
                    tripId: 't2',
                    riderPubkey: riderOne.publicHex,
                    driverPubkey: trusted.publicHex,
                    stars: 4,
                  ),
                  ..._pairedTrip(
                    tripId: 't3',
                    riderPubkey: riderTwo.publicHex,
                    driverPubkey: trusted.publicHex,
                    stars: 5,
                  ),
                ],
              }),
            ),
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
      await tester.tap(find.text('Нийтлэх'));
      await tester.pumpAndSettle();

      // Nothing has answered yet: the step must say so rather than leave a
      // heading over an empty half-screen.
      expect(find.text('Саналуудыг хүлээж байна'), findsOneWidget);

      final rideRequestId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kind":20177'),
                    ),
                  )
                  as List<dynamic>)[1]['id']
              as String;
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

      // The newcomer answers first and cheapest: without reputation on the
      // card there would be nothing on screen to weigh against that.
      emitOffer(
        newcomer,
        RideOfferPayload(
          rideRequestId: rideRequestId,
          priceMnt: 5500,
          etaMinutes: 6,
          vehicleDescription: 'хар Hyundai Sonata',
        ),
      );
      emitOffer(
        trusted,
        RideOfferPayload(
          rideRequestId: rideRequestId,
          priceMnt: 7000,
          etaMinutes: 3,
          vehicleDescription: 'цагаан Toyota Prius',
          kmTariffMnt: 1500,
          waitTariffMntPerMinute: 300,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // The counts, not the score: `trustWeight` is a damped, web-of-trust
      // weighted figure nobody standing on a kerb can read. Three trips
      // from *two* riders, because the trip count on its own is the half a
      // single enthusiastic pubkey can inflate.
      expect(find.text('3 аялал · 2 хүн баталсан'), findsOneWidget);
      expect(find.text('4.7'), findsOneWidget);
      // A driver with no history is named as new rather than reported as
      // lacking something, and shows no star at all -- an average of zero
      // over no ratings is not a zero rating.
      expect(find.text('Шинэ жолооч'), findsOneWidget);

      // The order now means something, and the screen says what it means.
      expect(
        find.text('Хоёр талдаа баталгаажсан аялалд тулгуурлан эрэмбэлэв'),
        findsOneWidget,
      );
      expect(find.text('Хамгийн итгэмжтэй'), findsOneWidget);

      // The badge belongs to the ranked-first card, which is the more
      // expensive offer -- i.e. the list is sorted on reputation and not on
      // price or arrival order.
      expect(
        tester.getTopLeft(find.text('Хамгийн итгэмжтэй')).dy,
        lessThan(tester.getTopLeft(find.textContaining(groupedMnt(5500))).dy),
      );

      // ---- and the rider can overrule that ----------------------------
      // A default nobody can change is not a default, it is the app
      // deciding what matters on somebody else's behalf. Тhe cheap
      // newcomer is exactly the offer a reputation sort buries.
      await tester.tap(find.text('Хямд'));
      await tester.pumpAndSettle();

      expect(find.text('Хамгийн хямд саналаас нь эрэмбэлэв'), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining(groupedMnt(5500))).dy,
        lessThan(tester.getTopLeft(find.textContaining(groupedMnt(7000))).dy),
      );
      // The badge went with the driver rather than with the first row: it
      // is a claim about who is most trusted, not about who is on top.
      expect(find.text('Хамгийн итгэмжтэй'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Хамгийн итгэмжтэй')).dy,
        greaterThan(
          tester.getTopLeft(find.textContaining(groupedMnt(5500))).dy,
        ),
      );

      // Back, and the heading says so again -- the subtitle is wired to the
      // live sort, not written once at build time.
      await tester.tap(find.text('Нэр хүнд'));
      await tester.pumpAndSettle();

      expect(
        find.text('Хоёр талдаа баталгаажсан аялалд тулгуурлан эрэмбэлэв'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.textContaining(groupedMnt(7000))).dy,
        lessThan(tester.getTopLeft(find.textContaining(groupedMnt(5500))).dy),
      );
    },
  );
}
