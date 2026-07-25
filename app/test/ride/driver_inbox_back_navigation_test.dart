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
import 'package:takhi/map/ride_map.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/driver_inbox_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// Sukhbaatar Square -- `DriverInboxPage`'s own default map center, so a
/// request published here always lands inside the driver's geohash-6 cell
/// (mirrors `driver_inbox_page_test.dart`'s constant).
const _lat = 47.9186, _lon = 106.9176;

const _homeLabel = 'нүүр';
const _leaveTitle = 'Аялалаас гарах уу?';

/// Handles onto the page a test has just pushed, so it can keep feeding it
/// relay frames afterwards.
class _Inbox {
  final Map<String, FakeRelaySocket> sockets;
  final Identity driver;
  final KeyPair passenger;

  const _Inbox(this.sockets, this.driver, this.passenger);

  FakeRelaySocket get socket => sockets['wss://a']!;

  /// The subscription id of the first `REQ` whose filter contains
  /// [filterFragment] -- `"kinds":[1059]` is this page's own handoff inbox,
  /// `"kinds":[20177]` its nearby-requests feed.
  String subIdFor(String filterFragment) =>
      (jsonDecode(socket.sent.firstWhere((s) => s.contains(filterFragment)))
              as List<dynamic>)[1]
          as String;
}

/// Pushes [DriverInboxPage] on top of a plain first route -- the state the
/// real app is in after `HomePage`'s `context.push('/ride/driver')`, and
/// the only one in which an `AppBar` back arrow exists at all.
Future<_Inbox> _pumpInboxOnStack(WidgetTester t, {required int seed}) async {
  final keyStore = InMemoryKeyStore();
  final driver = await IdentityService(keyStore).createNew();
  final passenger = generateKeyPair(List<int>.filled(32, seed));

  final sockets = <String, FakeRelaySocket>{};
  final pool = RelayPool([
    'wss://a',
  ], connect: (u) => sockets[u] = FakeRelaySocket());
  // `DriverInboxPage.initState` subscribes the moment identity resolves,
  // so the pool has to already hold its sockets by then -- same reasoning
  // as `driver_inbox_page_test.dart`'s own `connectAll` placement.
  await pool.connectAll();

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(keyStore),
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
                    builder: (_) => const DriverInboxPage(),
                  ),
                ),
                child: const Text(_homeLabel),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text(_homeLabel));
  await t.pumpAndSettle();
  return _Inbox(sockets, driver, passenger);
}

/// Delivers the gift-wrapped handoff a passenger sends when they pick this
/// driver -- what flips the page from its map to the "awarded" view.
Future<void> _deliverHandoff(
  WidgetTester t,
  _Inbox inbox, {
  required String tripId,
}) async {
  final wrap = nip17Wrap(
    senderPrivHex: inbox.passenger.privateHex,
    recipientPubHex: inbox.driver.pubHex,
    rumorKind: kRumorKindRideDm,
    content: RideHandoffPayload(
      rideRequestId: 'req-$tripId',
      tripId: tripId,
      lat: _lat,
      lon: _lon,
      plusCode: '8Q7XJVMC+2V',
      landmarkText: 'Улаан хаалганы урд',
    ).encode(),
    now: 1000,
  );
  inbox.socket.emit(
    jsonEncode(['EVENT', inbox.subIdFor('"kinds":[1059]'), wrap.toJson()]),
  );
  await t.pumpAndSettle();
}

/// Handoff -> start trip -> both driver phase buttons -> rating submitted,
/// i.e. the point where the receipt is already on the relay and leaving
/// costs nothing.
Future<void> _driveToDoneStep(WidgetTester t, _Inbox inbox) async {
  await _deliverHandoff(t, inbox, tripId: 'trip-done');
  await t.tap(find.text('Аялал эхлүүлэх'));
  await t.pumpAndSettle();
  await t.tap(find.text('Зорчигч сууллаа'));
  await t.pumpAndSettle();
  await t.tap(find.text('Аялал дууслаа'));
  await t.pumpAndSettle();
  await t.tap(find.byIcon(Icons.star_border).at(4));
  await t.pumpAndSettle();
  await t.tap(find.text('Илгээх'));
  await t.pumpAndSettle();
}

void main() {
  // `_sendOffer` reads `driverProfileServiceProvider` before the offer
  // dialog opens, which falls through to the real SharedPreferences store.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('with no trip in flight the inbox pops straight back home -- '
      'a back arrow exists and no dialog gets in the way', (t) async {
    await _pumpInboxOnStack(t, seed: 60);

    expect(find.byType(RideMap), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_leaveTitle), findsNothing);
    expect(find.text(_homeLabel), findsOneWidget);
  });

  testWidgets('the awarded-handoff screen is not guarded either -- nothing '
      'has been started yet, so back just leaves', (t) async {
    final inbox = await _pumpInboxOnStack(t, seed: 61);
    await _deliverHandoff(t, inbox, tripId: 'trip-awarded');

    expect(find.text('Зорчигчийн яг байршил'), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_leaveTitle), findsNothing);
    expect(find.text(_homeLabel), findsOneWidget);
  });

  testWidgets('once the trip is running, back is intercepted by the '
      'leave-trip confirmation and "Үлдэх" keeps the driver in it', (t) async {
    final inbox = await _pumpInboxOnStack(t, seed: 62);
    await _deliverHandoff(t, inbox, tripId: 'trip-running');
    await t.tap(find.text('Аялал эхлүүлэх'));
    await t.pumpAndSettle();
    expect(find.byType(ActiveTripView), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_leaveTitle), findsOneWidget);

    await t.tap(find.text('Үлдэх'));
    await t.pumpAndSettle();

    expect(find.text(_leaveTitle), findsNothing);
    expect(find.byType(ActiveTripView), findsOneWidget);
  });

  testWidgets('confirming "Гарах" from a running trip really does leave the '
      'page', (t) async {
    final inbox = await _pumpInboxOnStack(t, seed: 63);
    await _deliverHandoff(t, inbox, tripId: 'trip-leave');
    await t.tap(find.text('Аялал эхлүүлэх'));
    await t.pumpAndSettle();

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('Гарах'));
    await t.pumpAndSettle();

    expect(find.byType(ActiveTripView), findsNothing);
    expect(find.text(_homeLabel), findsOneWidget);
  });

  testWidgets('leaving a running trip really does notify the passenger, as '
      'the dialog promises -- otherwise they sit on "driver is on the way" '
      'forever, burning GPS on a driver who is gone', (t) async {
    final inbox = await _pumpInboxOnStack(t, seed: 68);
    await _deliverHandoff(t, inbox, tripId: 'trip-abandon');
    await t.tap(find.text('Аялал эхлүүлэх'));
    await t.pumpAndSettle();

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('Гарах'));
    await t.pumpAndSettle();

    expect(find.text(_homeLabel), findsOneWidget);

    final dm =
        jsonDecode(
              inbox.socket.sent.lastWhere((s) => s.contains('"kind":1059')),
            )
            as List<dynamic>;
    final payload = RideDmPayload.decode(
      nip17Unwrap(
        NostrEvent.fromJson(dm[1] as Map<String, dynamic>),
        inbox.passenger.privateHex,
      ).rumor.content,
    );
    // A phase transition, not a `RideCancelPayload`: that is the only
    // message `ActiveTripView` listens for, so it is the only one that
    // actually stops the passenger waiting (see `_abandonTrip`).
    expect(payload, isA<RideTripStatusPayload>());
    expect((payload as RideTripStatusPayload).tripId, 'trip-abandon');
    expect(payload.phase, TripPhase.arrived);
  });

  testWidgets('the QR settings action stays reachable during an active trip, '
      'not just on the two screens before it', (t) async {
    final inbox = await _pumpInboxOnStack(t, seed: 64);
    await _deliverHandoff(t, inbox, tripId: 'trip-qr');
    expect(find.byIcon(Icons.qr_code), findsOneWidget);

    await t.tap(find.text('Аялал эхлүүлэх'));
    await t.pumpAndSettle();

    expect(find.byType(ActiveTripView), findsOneWidget);
    expect(find.byIcon(Icons.qr_code), findsOneWidget);
  });

  testWidgets('a finished trip is no longer guarded -- back leaves without '
      'asking, because the receipt is already published', (t) async {
    final inbox = await _pumpInboxOnStack(t, seed: 65);
    await _driveToDoneStep(t, inbox);
    expect(find.text('Баримт нийтлэгдлээ'), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_leaveTitle), findsNothing);
    expect(find.text(_homeLabel), findsOneWidget);
  });

  testWidgets('"Аяллыг дуусгах" on the finished screen returns the driver to '
      'the nearby-requests map instead of stranding them there', (t) async {
    final inbox = await _pumpInboxOnStack(t, seed: 66);
    await _driveToDoneStep(t, inbox);

    await t.tap(find.text('Аяллыг дуусгах'));
    await t.pumpAndSettle();

    expect(find.byType(ActiveTripView), findsNothing);
    expect(find.text('Зорчигчийн яг байршил'), findsNothing);
    expect(find.byType(RideMap), findsOneWidget);
  });

  testWidgets('the offer dialog has a visible way out: "Цуцлах" closes it '
      'without publishing an offer', (t) async {
    final inbox = await _pumpInboxOnStack(t, seed: 67);

    final requestEvent = signEvent(
      buildRideRequest(
        pubkey: inbox.passenger.publicHex,
        now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pickupLat: _lat,
        pickupLon: _lon,
        destLat: _lat,
        destLon: _lon,
      ),
      inbox.passenger.privateHex,
      auxRand: List<int>.filled(32, 9),
    );
    inbox.socket.emit(
      jsonEncode([
        'EVENT',
        inbox.subIdFor('"kinds":[20177]'),
        requestEvent.toJson(),
      ]),
    );
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.person_pin_circle));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await t.tap(find.text('Цуцлах'));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(inbox.socket.sent.any((s) => s.contains('"kind":1059')), isFalse);
  });
}
