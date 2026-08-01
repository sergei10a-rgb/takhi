// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/metered_tariff_label.dart';
import 'package:takhi/ride/ride_dm_channel.dart' show kRumorKindRideDm;
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// The trip-duration rate (the third rate, added 2026-08-01) on a *matched*
/// ride -- the Nostr-arranged flow, as opposed to the offline street-hail
/// taximeter that `test/meter/duration_tariff_test.dart` covers.
///
/// The gap these tests exist to keep closed: for one commit the rate was
/// settable in the driver's profile and published in their kind-0, but it
/// reached neither the offer, nor the meter the trip actually ran on, nor
/// the receipt the passenger signed. A driver could set a rate, watch it in
/// their profile, and earn nothing for it on every ride the app arranged for
/// them. Every step of that chain is asserted below, end to end, because a
/// break anywhere in it is silent: the trip still completes, the fare is
/// simply smaller than the one both sides agreed.
void main() {
  group('the rate survives the wire', () {
    test('an offer carrying all three rates decodes back to all three', () {
      final encoded = RideOfferPayload(
        rideRequestId: 'req-1',
        priceMnt: 0,
        etaMinutes: 4,
        vehicleDescription: 'Prius',
        kmTariffMnt: 1500,
        waitTariffMntPerMinute: 300,
        durationTariffMntPerMinute: 120,
      ).encode();

      final decoded = RideDmPayload.decode(encoded) as RideOfferPayload;

      expect(decoded.kmTariffMnt, 1500);
      expect(decoded.waitTariffMntPerMinute, 300);
      expect(decoded.durationTariffMntPerMinute, 120);
    });

    test('an offer from a client built before the rate existed decodes with '
        'a null duration rate rather than throwing', () {
      // Byte-for-byte what the previous release put on the wire: the two
      // older tariff fields and no third one. It has to keep decoding --
      // a driver on an old build is not a malformed offer, and refusing it
      // would take them off the network on the day someone else updated.
      final legacy = jsonEncode({
        'type': 'offer',
        'rideRequestId': 'req-2',
        'priceMnt': 0,
        'etaMinutes': 6,
        'vehicleDescription': 'Prius',
        'kmTariffMnt': 1500,
        'waitTariffMntPerMinute': 300,
      });

      final decoded = RideDmPayload.decode(legacy) as RideOfferPayload;

      expect(decoded.kmTariffMnt, 1500);
      expect(decoded.waitTariffMntPerMinute, 300);
      expect(decoded.durationTariffMntPerMinute, isNull);
    });

    test('a zero duration rate travels as a zero, not as an absence', () {
      // The distinction earns its keep on the receiving side: `null` means
      // "this client cannot tell you", `0` means "the driver promises the
      // trip's duration is free". Both render no row, but only one of them
      // is a promise, and folding zero into null would throw that away.
      final decoded =
          RideDmPayload.decode(
                RideOfferPayload(
                  rideRequestId: 'req-3',
                  priceMnt: 0,
                  etaMinutes: 2,
                  vehicleDescription: 'Prius',
                  kmTariffMnt: 1500,
                  durationTariffMntPerMinute: 0,
                ).encode(),
              )
              as RideOfferPayload;

      expect(decoded.durationTariffMntPerMinute, 0);
    });

    test('the arrived status carries the duration fare and its seconds, and '
        'an older status decodes them as absent', () {
      final decoded =
          RideDmPayload.decode(
                const RideTripStatusPayload(
                  tripId: 'trip-1',
                  phase: TripPhase.arrived,
                  finalFareMnt: 9000,
                  finalWaitingFareMnt: 1500,
                  finalWaitingSeconds: 300,
                  finalDurationFareMnt: 1200,
                  finalDurationSeconds: 600,
                ).encode(),
              )
              as RideTripStatusPayload;

      expect(decoded.finalFareMnt, 9000);
      expect(decoded.finalWaitingFareMnt, 1500);
      expect(decoded.finalDurationFareMnt, 1200);
      expect(decoded.finalDurationSeconds, 600);

      final legacy =
          RideDmPayload.decode(
                jsonEncode({
                  'type': 'trip_status',
                  'tripId': 'trip-1',
                  'phase': 'arrived',
                  'finalFareMnt': 8200,
                  'finalWaitingFareMnt': 1500,
                  'finalWaitingSeconds': 300,
                }),
              )
              as RideTripStatusPayload;

      expect(legacy.finalFareMnt, 8200);
      expect(legacy.finalDurationFareMnt, isNull);
      expect(legacy.finalDurationSeconds, isNull);
    });
  });

  group('the price a passenger reads before they pick', () {
    late AppLocalizations l;

    setUpAll(() async {
      l = await AppLocalizations.delegate.load(const Locale('mn'));
    });

    test('the duration rate is its own clause, naming itself', () {
      final label = meteredDurationTariffLabel(l, 120);

      // The figure and the word that says which rate it is have to travel
      // together. This lives apart from the km/stopped-time label precisely
      // so it cannot be the tail of a longer string that a fixed-width chip
      // ellipses away -- which is what happened when all three rates shared
      // one label: «... + 80 ₮/мин хуг…».
      expect(label, isNotNull);
      expect(label, contains(groupedMnt(120)));
      expect(label, contains('хугацаа'));
    });

    test('it fits a chip: no rate label is long enough to be clipped on a '
        'narrow phone', () {
      // A crude proxy for the real constraint, and deliberately so: the
      // picture (trip/offer goldens) is what actually judges the width. This
      // only holds the line against a future edit that grows either clause
      // back toward the single-string version that did not fit.
      for (final label in [
        meteredTariffLabel(l, kmTariffMnt: 1500, waitTariffMntPerMinute: 300),
        meteredDurationTariffLabel(l, 120)!,
      ]) {
        expect(
          label.length,
          lessThanOrEqualTo(32),
          reason: 'offer-card chips do not wrap; "$label" is too long',
        );
      }
    });

    test('a free trip duration says nothing at all, unlike a free stop', () {
      // Asymmetric on purpose. Every metered offer has an answer about
      // stopped time, so silence there would be ambiguous and the label
      // states «зогсолт үнэгүй» outright. Almost no driver sets a duration
      // rate, so stating its absence would put a line about a charge that
      // does not exist on every offer in the country.
      expect(meteredDurationTariffLabel(l, 0), isNull);
      expect(meteredDurationTariffLabel(l, null), isNull);
      expect(
        meteredTariffLabel(l, kmTariffMnt: 1500, waitTariffMntPerMinute: 0),
        contains('зогсолт үнэгүй'),
      );
    });

    test(
      'the km/stopped-time label is untouched by the third rate -- an '
      'offer without one reads exactly as it did before the rate existed',
      () {
        expect(
          meteredTariffLabel(l, kmTariffMnt: 1500, waitTariffMntPerMinute: 300),
          allOf(contains(groupedMnt(1500)), contains(groupedMnt(300))),
        );
        expect(
          meteredTariffLabel(l, kmTariffMnt: 1500, waitTariffMntPerMinute: 300),
          isNot(contains('хугацаа')),
        );
      },
    );
  });

  testWidgets('driver role: a trip run on a duration rate reports the duration '
      'fare to the passenger, separately from the stopped-time one', (
    tester,
  ) async {
    final driverStore = InMemoryKeyStore();
    await IdentityService(driverStore).createNew();
    final passenger = generateKeyPair(List<int>.filled(32, 71));

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
          home: Scaffold(
            body: ActiveTripView(
              role: TripRole.driver,
              tripId: 'trip-duration-1',
              counterpartyPubHex: passenger.publicHex,
              agreedPriceMnt: 0,
              kmTariffMnt: 1500,
              durationTariffMntPerMinute: 600,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Ten minutes between the first fix and the last, and the car never
    // moved far enough to matter -- the whole point of this rate is that
    // those ten minutes are billed anyway.
    fakeLocation.emit(
      const GpsFix(lat: 47.90, lon: 106.90, timestampSeconds: 1000),
    );
    await tester.pump();
    fakeLocation.emit(
      const GpsFix(lat: 47.90, lon: 106.90, timestampSeconds: 1600),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Зорчигч сууллаа'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Аялал дууслаа'));
    await tester.pumpAndSettle();

    final endWrap = NostrEvent.fromJson(
      (jsonDecode(
                sockets['wss://a']!.sent.lastWhere(
                  (s) => s.contains('"kind":1059'),
                ),
              )
              as List<dynamic>)[1]
          as Map<String, dynamic>,
    );
    final endPayload =
        RideDmPayload.decode(
              nip17Unwrap(endWrap, passenger.privateHex).rumor.content,
            )
            as RideTripStatusPayload;

    expect(endPayload.phase, TripPhase.arrived);
    expect(endPayload.finalDurationSeconds, 600);
    // 600 s at 600 ₮/мин. Asserted as an exact figure rather than "greater
    // than zero": the failure this guards against is the rate arriving as
    // zero after a refactor, which "positive" would catch but a wrong
    // *rate* would not.
    expect(endPayload.finalDurationFareMnt, 6000);
    // The car stood still for all of it, and this driver set no
    // stopped-time rate -- so the two time charges are genuinely different
    // numbers here, and the duration one cannot be the waiting one under
    // another name.
    expect(endPayload.finalWaitingFareMnt, 0);
    expect(endPayload.finalFareMnt, greaterThanOrEqualTo(6000));
  });

  testWidgets('passenger role: the confirm screen shows the duration charge as '
      'its own row, and the distance row is the total minus BOTH time '
      'charges', (tester) async {
    final passengerStore = InMemoryKeyStore();
    final passengerIdentity = await IdentityService(passengerStore).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 72));

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
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Scaffold(
            body: ActiveTripView(
              role: TripRole.passenger,
              tripId: 'trip-duration-2',
              counterpartyPubHex: driver.publicHex,
              agreedPriceMnt: 0,
              kmTariffMnt: 1500,
              waitTariffMntPerMinute: 300,
              durationTariffMntPerMinute: 120,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[1059]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;
    sockets['wss://a']!.emit(
      jsonEncode([
        'EVENT',
        statusSubId,
        nip17Wrap(
          senderPrivHex: driver.privateHex,
          recipientPubHex: passengerIdentity.pubHex,
          rumorKind: kRumorKindRideDm,
          content: const RideTripStatusPayload(
            tripId: 'trip-duration-2',
            phase: TripPhase.arrived,
            // 6700 driving + 1500 stopped + 1200 duration. The two time
            // charges overlap -- the 300 stopped seconds are inside the 600
            // trip seconds -- and both are billed, which is the author's
            // ruling of 2026-08-01 and is exactly what the passenger is
            // being shown so they can accept or decline it.
            finalFareMnt: 9400,
            finalWaitingFareMnt: 1500,
            finalWaitingSeconds: 300,
            finalDurationFareMnt: 1200,
            finalDurationSeconds: 600,
          ).encode(),
          now: 1000,
        ).toJson(),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('${groupedMnt(9400)} ₮'), findsOneWidget);
    expect(find.text('Нийт'), findsOneWidget);

    // The row that used to be wrong. Before the duration rate reached this
    // screen the distance figure was `total - waiting`, which would have
    // reported this trip's 1200 ₮ of duration charge as 7900 ₮ of driving:
    // a claim that the car covered more road than it did, on the one screen
    // whose entire job is that the rows add up to the total above them.
    expect(find.text('Замын хөлс'), findsOneWidget);
    expect(find.text('${groupedMnt(6700)} ₮'), findsOneWidget);
    expect(find.text('${groupedMnt(7900)} ₮'), findsNothing);

    // Two time rows, each with the minutes that justify it, neither merged
    // into the other.
    expect(find.text('Зогсолтын хөлс (5 мин)'), findsOneWidget);
    expect(find.text('${groupedMnt(1500)} ₮'), findsOneWidget);
    expect(find.text('Хугацааны хөлс (10 мин)'), findsOneWidget);
    expect(find.text('${groupedMnt(1200)} ₮'), findsOneWidget);
  });

  testWidgets('passenger role: a trip with a duration charge but no stopped '
      'charge still gets its distance row', (tester) async {
    final passengerStore = InMemoryKeyStore();
    final passengerIdentity = await IdentityService(passengerStore).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 73));

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
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Scaffold(
            body: ActiveTripView(
              role: TripRole.passenger,
              tripId: 'trip-duration-3',
              counterpartyPubHex: driver.publicHex,
              agreedPriceMnt: 0,
              kmTariffMnt: 1500,
              durationTariffMntPerMinute: 120,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[1059]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;
    sockets['wss://a']!.emit(
      jsonEncode([
        'EVENT',
        statusSubId,
        nip17Wrap(
          senderPrivHex: driver.privateHex,
          recipientPubHex: passengerIdentity.pubHex,
          rumorKind: kRumorKindRideDm,
          content: const RideTripStatusPayload(
            tripId: 'trip-duration-3',
            phase: TripPhase.arrived,
            finalFareMnt: 7900,
            finalWaitingFareMnt: 0,
            finalWaitingSeconds: 0,
            finalDurationFareMnt: 1200,
            finalDurationSeconds: 600,
          ).encode(),
          now: 1000,
        ).toJson(),
      ]),
    );
    await tester.pumpAndSettle();

    // The distance row appears because a time charge exists to explain,
    // even though the *waiting* one does not -- the gate is "any time
    // charge", not "the waiting charge". Gating on waiting alone would have
    // shown this passenger a 7900 ₮ total with no breakdown at all and a
    // 1200 ₮ charge they never saw named.
    expect(find.text('Замын хөлс'), findsOneWidget);
    expect(find.text('${groupedMnt(6700)} ₮'), findsOneWidget);
    expect(find.text('Хугацааны хөлс (10 мин)'), findsOneWidget);
    // ...and no stopped-time row, because there is no such charge on this
    // trip. A 0 ₮ row is a row about nothing.
    expect(find.textContaining('Зогсолтын хөлс'), findsNothing);
  });
}
