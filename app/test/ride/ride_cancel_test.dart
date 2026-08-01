// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Cancelling a ride the passenger already published (spec §7.5).
//
// The two halves are tested together on purpose. A "cancel" button that
// clears local state and sends nothing is theatre: the driver who offered
// -- or worse, the one already driving over -- learns nothing, and the app
// has told the passenger a comforting lie. So every case here asserts both
// what left the device and what the *driver's* screen did with it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/profile/driver_photo_store.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi/profile/profile_providers.dart';
import 'package:takhi/ride/driver_inbox_page.dart';
import 'package:takhi/ride/passenger_ride_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

const _home = 'нүүр';
const _next = 'Үргэлжлүүл';
const _back = 'Буцах';
const _publish = 'Нийтлэх';
const _confirmSelect = 'Тийм, илгээх';
const _openedDriverSelect = 'Энэ жолоочийг сонгох';
const _offersTitle = 'Ирж буй саналууд';

const _cancelRequestAction = 'Дуудлагаа цуцлах';
const _cancelDriverAction = 'Сонгосон жолоочоо цуцлах';
const _yesCancel = 'Тийм, цуцлах';
const _noKeep = 'Үгүй, үлдээх';
const _cancelledToast = 'Дуудлага цуцлагдлаа';

/// The one sentence only the *cancel* dialog carries. Its title -- «Дуудлагаа
/// цуцлах уу?» -- is word-for-word the back-guard dialog's, so asserting on
/// the title alone could not tell the two apart, and a test that cannot tell
/// them apart would pass with the new button wired to the old guard.
const _cancelRequestCaveat = 'реле дээр 4 минут хүртэл харагдсаар';
const _cancelDriverConsequence = 'тэр таныг хүлээхээ болино';

const _driverCancelledTitle = 'Зорчигч дуудлагаа цуцаллаа';
const _driverCancelledDismiss = 'Ойлголоо';
const _driverAwardedHeading = 'Зорчигчийн яг байршил';
const _driverListeningTitle = 'Дуудлага сонсож байна';

/// Sukhbaatar Square -- `DriverInboxPage`'s own default map centre, so a
/// request published here lands inside the driver's geohash-6 neighbourhood
/// without panning first.
const _lat = 47.9186, _lon = 106.9176;

// ---------------------------------------------------------------------------
// Passenger side
// ---------------------------------------------------------------------------

/// Pushes [PassengerRidePage] on top of a stand-in home route, the way
/// `router.dart`'s CTA does -- so "did this leave the page?" is answerable.
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

/// Walks pickup -> destination -> price -> published, leaving the page on the
/// offers step with a live ride request on the relay.
Future<void> _publishRequest(WidgetTester t) async {
  await t.tap(find.text(_next).first);
  await t.pump();
  await t.tap(find.text(_next).first);
  await t.pump();
  await t.tap(find.text(_publish));
  await t.pumpAndSettle();
}

String _rideRequestIdFrom(FakeRelaySocket socket) {
  final frame =
      jsonDecode(socket.sent.firstWhere((s) => s.contains('"kind":20177')))
          as List<dynamic>;
  return (frame[1] as Map<String, dynamic>)['id'] as String;
}

/// Feeds one driver offer into the page's live inbox subscription and flushes
/// `TripReceiptRepository.receiptsAbout`'s real 3-second collection window,
/// which the arriving offer kicks off.
Future<void> _deliverOffer(
  WidgetTester t,
  FakeRelaySocket socket, {
  required String driverPrivHex,
  required String passengerPubHex,
  required String rideRequestId,
  required int priceMnt,
  String vehicle = 'цагаан Prius',
}) async {
  final wrap = nip17Wrap(
    senderPrivHex: driverPrivHex,
    recipientPubHex: passengerPubHex,
    rumorKind: kRumorKindRideDm,
    content: RideOfferPayload(
      rideRequestId: rideRequestId,
      priceMnt: priceMnt,
      etaMinutes: 3,
      vehicleDescription: vehicle,
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

/// The offer ROW carrying [text], never the quick-pick shortcut on the
/// action sheet -- that button states the price of the offer it would take,
/// so a bare `textContaining` matches twice whenever that offer is fastest.
Finder _offerRowWith(String text) => find.descendant(
  of: find.byType(ListView),
  matching: find.textContaining(text),
);

/// Picks the offer whose card carries [priceText]: opens the driver's page,
/// chooses them there, and confirms the exact-pickup disclosure dialog.
Future<void> _selectOffer(WidgetTester t, String priceText) async {
  await t.tap(_offerRowWith(priceText));
  await t.pumpAndSettle();
  await t.tap(find.text(_openedDriverSelect));
  await t.pumpAndSettle();
  await t.tap(find.text(_confirmSelect));
  await t.pumpAndSettle();
}

/// Every cancellation this device actually put on the wire that [privHex] can
/// open. Decrypting per recipient is the point: "a cancellation was sent" is
/// not the claim under test, "*this driver* was told" is.
List<RideCancelPayload> _cancelsReadableBy(
  FakeRelaySocket socket,
  String privHex,
) {
  final out = <RideCancelPayload>[];
  for (final frame in socket.sent.where((s) => s.contains('"kind":1059'))) {
    final wrap = NostrEvent.fromJson(
      (jsonDecode(frame) as List<dynamic>)[1] as Map<String, dynamic>,
    );
    try {
      final payload = RideDmPayload.decode(
        nip17Unwrap(wrap, privHex).rumor.content,
      );
      if (payload is RideCancelPayload) out.add(payload);
    } on Exception {
      // Addressed to a different driver, or not a cancellation at all.
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Driver side
// ---------------------------------------------------------------------------

/// A driver complete enough to be allowed to make an offer at all
/// (`driverOfferBlock` refuses a nameless or portrait-less one).
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
  final photoStore = InMemoryDriverPhotoStore();
  await photoStore.save(Uint8List.fromList(List<int>.filled(900, 0x42)));
  return [
    driverProfileStoreProvider.overrideWithValue(profileStore),
    driverPhotoStoreProvider.overrideWithValue(photoStore),
  ];
}

/// The subscription id of every gift-wrap `REQ` this page has opened, in the
/// order they went on the wire.
List<String> _giftWrapSubIds(FakeRelaySocket socket) => socket.sent
    .where((s) => s.contains('"kinds":[1059]'))
    .map((s) => (jsonDecode(s) as List<dynamic>)[1] as String)
    .toList();

/// Drives `DriverInboxPage` to the awarded-handoff screen: one nearby
/// request, a real offer sent through the pricing dialog, then the
/// passenger's handoff. Returns the socket and the passenger's keys.
Future<({FakeRelaySocket socket, KeyPair passenger, String rideRequestId})>
_driveDriverToAwarded(
  WidgetTester t, {
  required InMemoryKeyStore driverStore,
  required String driverPubHex,
  required int seed,
}) async {
  final passenger = generateKeyPair(List<int>.filled(32, seed));
  final sockets = <String, FakeRelaySocket>{};
  final pool = RelayPool([
    'wss://a',
  ], connect: (u) => sockets[u] = FakeRelaySocket());

  // `DriverInboxPage.initState` subscribes as soon as identity resolves,
  // which can happen during `pumpWidget` -- the pool has to be connected
  // first or `subscribe` iterates zero sockets and sends no `REQ` at all.
  await pool.connectAll();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(driverStore),
        relayPoolProvider.overrideWithValue(pool),
        locationSourceProvider.overrideWithValue(FakeLocationSource()),
        locationPermissionCheckProvider.overrideWithValue(() async => false),
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
  await t.pumpAndSettle();

  final socket = sockets['wss://a']!;
  final listingsSubId =
      (jsonDecode(socket.sent.firstWhere((s) => s.contains('"kinds":[20177]')))
              as List<dynamic>)[1]
          as String;

  // `_wireStreams` hardcodes the real wall clock for its expiry check, so
  // this event's `now` must be real "now" or it reads as already expired.
  final requestEvent = signEvent(
    buildRideRequest(
      pubkey: passenger.publicHex,
      now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      pickupLat: _lat,
      pickupLon: _lon,
      destLat: _lat,
      destLon: _lon,
    ),
    passenger.privateHex,
    auxRand: List<int>.filled(32, seed),
  );
  socket.emit(jsonEncode(['EVENT', listingsSubId, requestEvent.toJson()]));
  await t.pumpAndSettle();

  await t.tap(find.byIcon(Icons.person_pin_circle));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField).at(0), '8000');
  await t.enterText(find.byType(TextField).at(1), '5');
  await t.enterText(find.byType(TextField).at(2), 'хөх Tucson');
  await t.tap(find.text('Санал илгээх'));
  await t.pumpAndSettle();

  final rideRequestId = requestEvent.id!;
  final handoffWrap = nip17Wrap(
    senderPrivHex: passenger.privateHex,
    recipientPubHex: driverPubHex,
    rumorKind: kRumorKindRideDm,
    content: RideHandoffPayload(
      rideRequestId: rideRequestId,
      tripId: 'trip-$seed',
      lat: _lat,
      lon: _lon,
      plusCode: '8Q7XJVMC+2V',
      landmarkText: 'Улаан хаалганы урд',
    ).encode(),
    now: 1000,
  );
  socket.emit(
    jsonEncode(['EVENT', _giftWrapSubIds(socket).first, handoffWrap.toJson()]),
  );
  await t.pumpAndSettle();
  expect(find.text(_driverAwardedHeading), findsOneWidget);

  return (socket: socket, passenger: passenger, rideRequestId: rideRequestId);
}

/// Delivers one cancellation to the driver's own cancellation subscription.
///
/// Emitted on that subscription's *own* id rather than the handoff one: a
/// relay routes each frame by `subId`, and `RelayPool` only dispatches a
/// frame to the subscription whose id it carries.
Future<void> _deliverCancel(
  WidgetTester t,
  FakeRelaySocket socket, {
  required String senderPrivHex,
  required String driverPubHex,
  required String rideRequestId,
}) async {
  final wrap = nip17Wrap(
    senderPrivHex: senderPrivHex,
    recipientPubHex: driverPubHex,
    rumorKind: kRumorKindRideDm,
    content: RideCancelPayload(rideRequestId: rideRequestId).encode(),
    now: 1000,
  );
  final subIds = _giftWrapSubIds(socket);
  expect(
    subIds.length,
    greaterThanOrEqualTo(2),
    reason:
        'DriverInboxPage opened no cancellation subscription, so spec §7.5 '
        'cancellations can never reach this driver',
  );
  socket.emit(jsonEncode(['EVENT', subIds[1], wrap.toJson()]));
  await t.pumpAndSettle();
}

void main() {
  // `_select` reads `phoneShareSettingsStoreProvider`, backed by real
  // `shared_preferences`, and `_sendOffer` reads the driver profile store.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the offers step carries an explicit way out, and backing out '
      'of the confirmation keeps the request and every offer alive', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 131));
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

    // The button is on the step itself, not hidden behind a back gesture.
    expect(find.text(_cancelRequestAction), findsOneWidget);
    await t.tap(find.text(_cancelRequestAction));
    await t.pumpAndSettle();

    // And it says the one true thing about a Nostr cancellation: the
    // published request is not retracted, it merely expires.
    expect(find.textContaining(_cancelRequestCaveat), findsOneWidget);

    await t.tap(find.text(_noKeep));
    await t.pumpAndSettle();

    expect(find.text(_offersTitle), findsOneWidget);
    expect(find.textContaining(groupedMnt(6000)), findsWidgets);
    expect(
      _cancelsReadableBy(socket, driver.privateHex),
      isEmpty,
      reason: '"keep it" told the driver the ride was off',
    );
  });

  testWidgets('confirming the offers-step cancellation tells every driver who '
      'offered -- not just the last one -- and returns the wizard to its '
      'first step', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final first = generateKeyPair(List<int>.filled(32, 132));
    final second = generateKeyPair(List<int>.filled(32, 133));
    final sockets = await _openRidePage(t, store);
    final socket = sockets['wss://a']!;

    await _publishRequest(t);
    final rideRequestId = _rideRequestIdFrom(socket);
    await _deliverOffer(
      t,
      socket,
      driverPrivHex: first.privateHex,
      passengerPubHex: identity.pubHex,
      rideRequestId: rideRequestId,
      priceMnt: 6000,
    );
    await _deliverOffer(
      t,
      socket,
      driverPrivHex: second.privateHex,
      passengerPubHex: identity.pubHex,
      rideRequestId: rideRequestId,
      priceMnt: 7000,
      vehicle: 'хар Sonata',
    );

    await t.tap(find.text(_cancelRequestAction));
    await t.pumpAndSettle();
    await t.tap(find.text(_yesCancel));
    await t.pumpAndSettle();

    for (final driver in [first, second]) {
      final cancels = _cancelsReadableBy(socket, driver.privateHex);
      expect(
        cancels.map((c) => c.rideRequestId),
        [rideRequestId],
        reason: 'a driver who offered was left waiting on a dead request',
      );
    }

    // Said out loud rather than left as a screen that silently changed.
    expect(find.text(_cancelledToast), findsOneWidget);

    // Back at the start of the flow, still inside the page: the request is
    // gone, the offers are gone, and nothing was published for it.
    expect(find.text(_offersTitle), findsNothing);
    expect(find.text(_home), findsNothing);
    expect(find.text(_next), findsOneWidget);
    expect(find.text(_back), findsNothing);
  });

  testWidgets('cancelling with no offer in hand sends nothing and still '
      'clears the request', (t) async {
    final store = InMemoryKeyStore();
    await IdentityService(store).createNew();
    final sockets = await _openRidePage(t, store);
    final socket = sockets['wss://a']!;

    await _publishRequest(t);
    await t.tap(find.text(_cancelRequestAction));
    await t.pumpAndSettle();
    await t.tap(find.text(_yesCancel));
    await t.pumpAndSettle();

    expect(
      socket.sent.where((s) => s.contains('"kind":1059')),
      isEmpty,
      reason: 'a cancellation was gift-wrapped to nobody in particular',
    );
    expect(find.text(_next), findsOneWidget);
  });

  testWidgets('the done step can cancel the driver already chosen: exactly '
      'that driver is told, and leaving afterwards does not tell them a '
      'second time', (t) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 134));
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
    await _selectOffer(t, groupedMnt(6000));
    expect(find.textContaining('Prius'), findsOneWidget); // done step

    expect(find.text(_cancelDriverAction), findsOneWidget);
    await t.tap(find.text(_cancelDriverAction));
    await t.pumpAndSettle();
    expect(find.textContaining(_cancelDriverConsequence), findsOneWidget);

    await t.tap(find.text(_yesCancel));
    await t.pumpAndSettle();

    expect(
      _cancelsReadableBy(socket, driver.privateHex).map((c) => c.rideRequestId),
      [rideRequestId],
    );
    expect(find.text(_next), findsOneWidget); // back at the start

    // The booking is off, so the back guard has nothing left to protect --
    // and must not fire a second cancellation at a driver already told.
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text(_home), findsOneWidget);
    expect(
      _cancelsReadableBy(socket, driver.privateHex).length,
      1,
      reason: 'the chosen driver was told twice about one cancellation',
    );
  });

  testWidgets('a driver already on their way is told the rider cancelled, and '
      'is put back to listening for calls', (t) async {
    final driverStore = InMemoryKeyStore();
    final driver = await IdentityService(driverStore).createNew();
    final awarded = await _driveDriverToAwarded(
      t,
      driverStore: driverStore,
      driverPubHex: driver.pubHex,
      seed: 141,
    );

    await _deliverCancel(
      t,
      awarded.socket,
      senderPrivHex: awarded.passenger.privateHex,
      driverPubHex: driver.pubHex,
      rideRequestId: awarded.rideRequestId,
    );

    // Not merely cleared -- said. A screen that swaps itself out with no
    // word is indistinguishable from a crash to a driver mid-turn.
    expect(find.text(_driverCancelledTitle), findsOneWidget);
    expect(find.text(_driverAwardedHeading), findsNothing);

    await t.tap(find.text(_driverCancelledDismiss));
    await t.pumpAndSettle();
    expect(find.text(_driverCancelledTitle), findsNothing);
    expect(find.text(_driverListeningTitle), findsOneWidget);
  });

  testWidgets('a cancellation from a stranger, or about a different job, '
      'leaves the awarded pickup exactly where it was', (t) async {
    final driverStore = InMemoryKeyStore();
    final driver = await IdentityService(driverStore).createNew();
    final awarded = await _driveDriverToAwarded(
      t,
      driverStore: driverStore,
      driverPubHex: driver.pubHex,
      seed: 142,
    );
    final stranger = generateKeyPair(List<int>.filled(32, 199));

    // Right ride request id, wrong sender: anyone who watched the public
    // kind-20177 go by knows the id, so the id alone cannot be the key.
    await _deliverCancel(
      t,
      awarded.socket,
      senderPrivHex: stranger.privateHex,
      driverPubHex: driver.pubHex,
      rideRequestId: awarded.rideRequestId,
    );
    expect(find.text(_driverAwardedHeading), findsOneWidget);
    expect(find.text(_driverCancelledTitle), findsNothing);

    // Right sender, wrong ride request: the same passenger's *other* call.
    await _deliverCancel(
      t,
      awarded.socket,
      senderPrivHex: awarded.passenger.privateHex,
      driverPubHex: driver.pubHex,
      rideRequestId: 'some-other-request',
    );
    expect(find.text(_driverAwardedHeading), findsOneWidget);
    expect(find.text(_driverCancelledTitle), findsNothing);
  });
}
