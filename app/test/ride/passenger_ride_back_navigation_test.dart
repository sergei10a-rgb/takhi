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
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/passenger_ride_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

const _home = 'нүүр';
const _next = 'Үргэлжлүүл';
const _back = 'Буцах';
const _publish = 'Нийтлэх';
const _stay = 'Үлдэх';
const _leave = 'Гарах';
const _cancel = 'Цуцлах';
const _confirmSelect = 'Тийм, илгээх';
const _startTrip = 'Аялал руу очих';
const _finishTrip = 'Аяллыг дуусгах';
const _receiptPublished = 'Баримт нийтлэгдлээ';
const _offersTitle = 'Ирж буй саналууд';
const _selectOfferTitle = 'Энэ жолоочийг сонгох уу?';
const _leaveRequestTitle = 'Дуудлагаа цуцлах уу?';
const _leaveTripTitle = 'Аялалаас гарах уу?';
const _leaveSelectionTitle = 'Сонгосон жолоочоо цуцлах уу?';

/// Pushes [PassengerRidePage] on top of a stand-in home route, exactly
/// the way `router.dart`'s CTA does. Without a route underneath there is
/// no `AppBar` back arrow at all, so none of the back behaviour this file
/// is about would be reachable.
Future<Map<String, FakeRelaySocket>> _openRidePage(
  WidgetTester t,
  InMemoryKeyStore store,
) async {
  final sockets = <String, FakeRelaySocket>{};
  final pool = RelayPool([
    'wss://a',
  ], connect: (u) => sockets[u] = FakeRelaySocket());

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(store),
        relayPoolProvider.overrideWithValue(pool),
        // Only the scenarios that reach `ActiveTripView` need these, but
        // an override the other cases never touch is cheaper than a second
        // near-identical harness -- and the real providers would reach for
        // a GPS radio that `flutter_test` has no plugin for.
        locationSourceProvider.overrideWithValue(FakeLocationSource()),
        locationPermissionCheckProvider.overrideWithValue(() async => true),
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
                  MaterialPageRoute<void>(
                    builder: (_) => const PassengerRidePage(),
                  ),
                ),
                child: const Text(_home),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await pool.connectAll();
  await t.pumpAndSettle();

  await t.tap(find.text(_home));
  await t.pumpAndSettle();
  return sockets;
}

/// Walks pickup -> destination -> price -> published, leaving the page on
/// the offers step with a live ride request on the relay.
Future<void> _publishRequest(WidgetTester t, {String price = '5000'}) async {
  await t.tap(find.text(_next).first);
  await t.pump();
  await t.tap(find.text(_next).first);
  await t.pump();
  await t.enterText(find.byType(TextField).first, price);
  await t.tap(find.text(_publish));
  await t.pumpAndSettle();
}

String _rideRequestIdFrom(FakeRelaySocket socket) {
  final frame =
      jsonDecode(socket.sent.firstWhere((s) => s.contains('"kind":20177')))
          as List<dynamic>;
  return (frame[1] as Map<String, dynamic>)['id'] as String;
}

/// Feeds one driver offer into the page's live inbox subscription and
/// flushes `TripReceiptRepository.receiptsAbout`'s real 3-second
/// collection window, which the arriving offer kicks off.
Future<void> _deliverOffer(
  WidgetTester t,
  FakeRelaySocket socket, {
  required String driverPrivHex,
  required String passengerPubHex,
  required String rideRequestId,
  required int priceMnt,
}) async {
  final wrap = nip17Wrap(
    senderPrivHex: driverPrivHex,
    recipientPubHex: passengerPubHex,
    rumorKind: kRumorKindRideDm,
    content: RideOfferPayload(
      rideRequestId: rideRequestId,
      priceMnt: priceMnt,
      etaMinutes: 3,
      vehicleDescription: 'цагаан Prius',
    ).encode(),
    now: 1000,
  );
  final inboxSubId =
      (jsonDecode(socket.sent.firstWhere((s) => s.contains('"kinds":[1059]')))
              as List<dynamic>)[1]
          as String;
  socket.emit(jsonEncode(['EVENT', inboxSubId, wrap.toJson()]));
  await t.pumpAndSettle();
  await t.pump(const Duration(seconds: 3));
}

/// Picks the offer whose summary contains [priceText] and confirms the
/// dialog `_select` now raises first -- the exact pickup point (and a phone
/// number, if sharing is on) is about to leave the device irreversibly.
Future<void> _selectOffer(WidgetTester t, String priceText) async {
  await t.tap(find.textContaining(priceText));
  await t.pumpAndSettle();
  await t.tap(find.text(_confirmSelect));
  await t.pumpAndSettle();
}

/// How many gift-wrapped DMs this page has actually put on the wire. The
/// `"kind":1059` spelling only appears in published `EVENT` frames --
/// subscriptions use `"kinds":[1059]` -- so this counts sends, not reads.
int _dmCount(FakeRelaySocket socket) =>
    socket.sent.where((s) => s.contains('"kind":1059')).length;

/// The subscription id of every gift-wrap `REQ` this page has opened, in
/// the order they went on the wire.
List<String> _giftWrapSubIds(FakeRelaySocket socket) => socket.sent
    .where((s) => s.contains('"kinds":[1059]'))
    .map((s) => (jsonDecode(s) as List<dynamic>)[1] as String)
    .toList();

/// Offer -> handoff -> active trip -> driver arrives -> rating submitted,
/// i.e. the point where this side's receipt is on the relay and leaving
/// costs nothing at all.
Future<void> _driveToSettledTrip(
  WidgetTester t,
  FakeRelaySocket socket, {
  required String driverPrivHex,
  required String passengerPubHex,
}) async {
  await _selectOffer(t, '6000');

  // `ActiveTripView._startTracking` wires the passenger's status
  // subscription first among its own (see its ordering comment), so it is
  // the next gift-wrap `REQ` after the ones this page had already opened.
  // The arrival has to be emitted on exactly that id: `RelayPool` dedupes
  // by event id, so fanning the same event out across every subscription
  // would only ever reach whichever one happens to see it first.
  final subIdsBeforeTrip = _giftWrapSubIds(socket).length;
  await t.tap(find.text(_startTrip));
  await t.pumpAndSettle();
  final statusSubId = _giftWrapSubIds(socket)[subIdsBeforeTrip];

  final wrap = nip17Wrap(
    senderPrivHex: driverPrivHex,
    recipientPubHex: passengerPubHex,
    rumorKind: kRumorKindRideDm,
    content: RideTripStatusPayload(
      // Read off the widget rather than re-decoding the handoff DM: this
      // is the very id `HandoffService` minted and threaded in, so a
      // status addressed to it cannot silently miss the filter.
      tripId: t.widget<ActiveTripView>(find.byType(ActiveTripView)).tripId,
      phase: TripPhase.arrived,
    ).encode(),
    now: 1000,
  );
  socket.emit(jsonEncode(['EVENT', statusSubId, wrap.toJson()]));
  await t.pumpAndSettle();

  await t.tap(find.byIcon(Icons.star_border).at(4));
  await t.pumpAndSettle();
  await t.tap(find.text('Илгээх'));
  await t.pumpAndSettle();
}

void main() {
  // `_select` reads `phoneShareSettingsStoreProvider`, which is backed by
  // real `shared_preferences` -- same mock the sibling
  // `passenger_ride_page_test.dart` installs.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('back on the first step leaves the page outright -- nothing '
      'has been entered or published yet, so there is nothing to confirm', (
    t,
  ) async {
    await _openRidePage(t, InMemoryKeyStore());

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_leaveRequestTitle), findsNothing);
    expect(find.text(_leaveTripTitle), findsNothing);
    expect(find.text(_home), findsOneWidget);
  });

  testWidgets('back on the destination step returns to the pickup step '
      'instead of closing the whole wizard', (t) async {
    await _openRidePage(t, InMemoryKeyStore());

    await t.tap(find.text(_next).first); // pickup -> destination
    await t.pumpAndSettle();
    expect(find.text(_back), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    // Still on the ride page, and back on its first step -- which is the
    // one step that no longer offers an in-body "back".
    expect(find.text(_home), findsNothing);
    expect(find.text(_back), findsNothing);
    expect(find.text(_next), findsOneWidget);
  });

  testWidgets('stepping back shows the landmark the passenger already typed, '
      'and never leaks it into the next step', (t) async {
    await _openRidePage(t, InMemoryKeyStore());

    await t.enterText(find.byType(TextField).first, 'Улаан байшин');
    await t.pumpAndSettle();
    await t.tap(find.text(_next).first); // pickup -> destination
    await t.pumpAndSettle();

    // A fresh, empty field: the destination is not the pickup.
    expect(find.text('Улаан байшин'), findsNothing);
    await t.enterText(find.byType(TextField).first, 'Хөх дэлгүүр');
    await t.pumpAndSettle();

    await t.tap(find.text(_back)); // destination -> pickup
    await t.pumpAndSettle();
    expect(find.text('Улаан байшин'), findsOneWidget);

    await t.tap(find.text(_next).first); // pickup -> destination again
    await t.pumpAndSettle();
    expect(find.text('Хөх дэлгүүр'), findsOneWidget);
  });

  testWidgets('the price survives a trip back to the destination step and '
      'forward again', (t) async {
    await _openRidePage(t, InMemoryKeyStore());

    await t.tap(find.text(_next).first);
    await t.pumpAndSettle();
    await t.tap(find.text(_next).first); // -> price
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '7500');
    await t.pumpAndSettle();

    await t.tap(find.text(_back)); // price -> destination
    await t.pumpAndSettle();
    expect(find.text('7500'), findsNothing);

    await t.tap(find.text(_next).first); // destination -> price
    await t.pumpAndSettle();
    expect(find.text('7500'), findsOneWidget);
  });

  testWidgets('back on the offers step asks first, and "stay" keeps the '
      'published request and its offer list alive', (t) async {
    final store = InMemoryKeyStore();
    await IdentityService(store).createNew();
    await _openRidePage(t, store);
    await _publishRequest(t);
    expect(find.text(_offersTitle), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text(_leaveRequestTitle), findsOneWidget);

    await t.tap(find.text(_stay));
    await t.pumpAndSettle();

    expect(find.text(_leaveRequestTitle), findsNothing);
    expect(find.text(_offersTitle), findsOneWidget);
    expect(find.text(_home), findsNothing);
  });

  testWidgets('confirming the offers-step dialog leaves the page for good', (
    t,
  ) async {
    final store = InMemoryKeyStore();
    await IdentityService(store).createNew();
    await _openRidePage(t, store);
    await _publishRequest(t);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text(_leave));
    await t.pumpAndSettle();

    expect(find.text(_offersTitle), findsNothing);
    expect(find.text(_home), findsOneWidget);
  });

  testWidgets("the offers step's own back button withdraws the request and "
      'returns to the price step with the price still filled in', (t) async {
    final store = InMemoryKeyStore();
    await IdentityService(store).createNew();
    await _openRidePage(t, store);
    await _publishRequest(t, price: '4200');

    await t.tap(find.text(_back));
    await t.pumpAndSettle();

    // Back inside the wizard -- no dialog, page still open, and the
    // number that produced no acceptable offers is there to be edited.
    expect(find.text(_leaveRequestTitle), findsNothing);
    expect(find.text(_home), findsNothing);
    expect(find.text(_publish), findsOneWidget);
    expect(find.text('4200'), findsOneWidget);
  });

  testWidgets('leaving from the done step tells the chosen driver the ride '
      'is cancelled (spec §7.5) rather than letting them drive over', (
    t,
  ) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 121));
    final sockets = await _openRidePage(t, store);
    final socket = sockets['wss://a']!;

    await _publishRequest(t);
    final rideRequestId = _rideRequestIdFrom(socket);
    await _deliverOffer(
      t,
      socket,
      driverPrivHex: driver.privateHex,
      passengerPubHex: identity.pubHex,
      rideRequestId: rideRequestId,
      priceMnt: 6000,
    );

    await _selectOffer(t, '6000');
    expect(find.textContaining('Prius'), findsOneWidget); // done step

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text(_leaveSelectionTitle), findsOneWidget);

    await t.tap(find.text(_leave));
    await t.pumpAndSettle();

    expect(find.text(_home), findsOneWidget);
    final lastDm =
        jsonDecode(socket.sent.lastWhere((s) => s.contains('"kind":1059')))
            as List<dynamic>;
    final unwrapped = nip17Unwrap(
      NostrEvent.fromJson(lastDm[1] as Map<String, dynamic>),
      driver.privateHex,
    );
    final payload = RideDmPayload.decode(unwrapped.rumor.content);
    expect(payload, isA<RideCancelPayload>());
    expect((payload as RideCancelPayload).rideRequestId, rideRequestId);
  });

  testWidgets('the done step asks about the booking, not about a trip that '
      'has not started -- a driver is chosen, nobody is riding yet', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 125));
    final sockets = await _openRidePage(t, store);
    final socket = sockets['wss://a']!;

    await _publishRequest(t);
    await _deliverOffer(
      t,
      socket,
      driverPrivHex: driver.privateHex,
      passengerPubHex: identity.pubHex,
      rideRequestId: _rideRequestIdFrom(socket),
      priceMnt: 6000,
    );
    await _selectOffer(t, '6000');
    expect(find.textContaining('Prius'), findsOneWidget); // done step

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    // "Leave the trip?" here described something that does not exist:
    // `ActiveTripView` has not been mounted, no location is being shared,
    // and there is nothing to "get back into".
    expect(find.text(_leaveSelectionTitle), findsOneWidget);
    expect(find.text(_leaveTripTitle), findsNothing);
    // And the body names the consequence that makes this worth confirming
    // at all -- the driver is already on their way and has to be told.
    expect(find.textContaining('жолоочид мэдэгдэнэ'), findsOneWidget);

    await t.tap(find.text(_stay));
    await t.pumpAndSettle();
    expect(find.textContaining('Prius'), findsOneWidget);
  });

  testWidgets('back during a running trip does ask about the trip -- by then '
      'there actually is one', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 126));
    final sockets = await _openRidePage(t, store);
    final socket = sockets['wss://a']!;

    await _publishRequest(t);
    await _deliverOffer(
      t,
      socket,
      driverPrivHex: driver.privateHex,
      passengerPubHex: identity.pubHex,
      rideRequestId: _rideRequestIdFrom(socket),
      priceMnt: 6000,
    );
    await _selectOffer(t, '6000');

    await t.tap(find.text(_startTrip));
    await t.pumpAndSettle();
    expect(find.byType(ActiveTripView), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_leaveTripTitle), findsOneWidget);
    expect(find.text(_leaveSelectionTitle), findsNothing);

    // Confirmed rather than dismissed so the live trip is torn down with
    // the page instead of ticking on past the end of the test.
    await t.tap(find.text(_leave));
    await t.pumpAndSettle();
    expect(find.text(_home), findsOneWidget);
  });

  testWidgets('tapping an offer asks before anything leaves the device, and '
      '"Цуцлах" sends the driver nothing at all', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 122));
    final sockets = await _openRidePage(t, store);
    final socket = sockets['wss://a']!;

    await _publishRequest(t);
    await _deliverOffer(
      t,
      socket,
      driverPrivHex: driver.privateHex,
      passengerPubHex: identity.pubHex,
      rideRequestId: _rideRequestIdFrom(socket),
      priceMnt: 6000,
    );

    await t.tap(find.textContaining('6000'));
    await t.pumpAndSettle();

    // The tile tap alone is not the disclosure -- the dialog names the car
    // being chosen, and no handoff has gone out yet.
    expect(find.text(_selectOfferTitle), findsOneWidget);
    expect(find.textContaining('Prius'), findsWidgets);
    expect(_dmCount(socket), 0);

    await t.tap(find.text(_cancel));
    await t.pumpAndSettle();

    // Backed out cleanly: still choosing, still nothing on the wire.
    expect(find.text(_selectOfferTitle), findsNothing);
    expect(find.text(_offersTitle), findsOneWidget);
    expect(_dmCount(socket), 0);

    // And confirming is what actually sends the pickup point.
    await _selectOffer(t, '6000');

    expect(_dmCount(socket), 1);
    final handoffDm =
        jsonDecode(socket.sent.lastWhere((s) => s.contains('"kind":1059')))
            as List<dynamic>;
    final payload = RideDmPayload.decode(
      nip17Unwrap(
        NostrEvent.fromJson(handoffDm[1] as Map<String, dynamic>),
        driver.privateHex,
      ).rumor.content,
    );
    expect(payload, isA<RideHandoffPayload>());
  });

  testWidgets('a settled trip is no longer guarded -- back leaves without '
      'asking, and the driver is never told a finished ride was '
      'cancelled', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 123));
    final sockets = await _openRidePage(t, store);
    final socket = sockets['wss://a']!;

    await _publishRequest(t);
    await _deliverOffer(
      t,
      socket,
      driverPrivHex: driver.privateHex,
      passengerPubHex: identity.pubHex,
      rideRequestId: _rideRequestIdFrom(socket),
      priceMnt: 6000,
    );
    await _driveToSettledTrip(
      t,
      socket,
      driverPrivHex: driver.privateHex,
      passengerPubHex: identity.pubHex,
    );
    expect(find.text(_receiptPublished), findsOneWidget);

    final dmsBeforeLeaving = _dmCount(socket);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_leaveTripTitle), findsNothing);
    expect(find.text(_home), findsOneWidget);
    // The one DM this side ever sent is the handoff -- a `RideCancelPayload`
    // for a trip whose receipt is already published would flatly contradict
    // spec §7.5.
    expect(_dmCount(socket), dmsBeforeLeaving);
  });

  testWidgets('"Аяллыг дуусгах" on the finished screen returns the passenger '
      'to the start of the flow instead of stranding them there', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 124));
    final sockets = await _openRidePage(t, store);
    final socket = sockets['wss://a']!;

    await _publishRequest(t);
    await _deliverOffer(
      t,
      socket,
      driverPrivHex: driver.privateHex,
      passengerPubHex: identity.pubHex,
      rideRequestId: _rideRequestIdFrom(socket),
      priceMnt: 6000,
    );
    await _driveToSettledTrip(
      t,
      socket,
      driverPrivHex: driver.privateHex,
      passengerPubHex: identity.pubHex,
    );

    await t.tap(find.text(_finishTrip));
    await t.pumpAndSettle();

    // Back on the pickup step -- the one step with a "next" and no "back",
    // and still on the ride page rather than dumped out to home.
    expect(find.byType(ActiveTripView), findsNothing);
    expect(find.text(_receiptPublished), findsNothing);
    expect(find.text(_home), findsNothing);
    expect(find.text(_next), findsOneWidget);
    expect(find.text(_back), findsNothing);
  });
}
