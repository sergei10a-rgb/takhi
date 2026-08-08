// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/geo/gps_track.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/ride_dm_channel.dart' show kRumorKindRideDm;
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// The §7.2 GPS-taximeter pricing-mode flow (metered pricing, selected by
/// `kmTariffMnt` being non-null on `ActiveTripView`): both sides show a
/// live running fare, the driver computes and reports the final fare from
/// their own GPS track on "Аялал дууслаа", and the passenger must
/// explicitly confirm that fare before a trip receipt is published --
/// declining leaves the receipt unpaired (spec §9), exactly as if the
/// passenger had simply never tapped submit.
void main() {
  testWidgets('driver role, metered: shows a live running fare and reports the '
      'GPS-computed final fare on ending the trip', (tester) async {
    final driverStore = InMemoryKeyStore();
    await IdentityService(driverStore).createNew();
    final passenger = generateKeyPair(List<int>.filled(32, 61));

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
              tripId: 'trip-metered-1',
              counterpartyPubHex: passenger.publicHex,
              agreedPriceMnt: 0,
              kmTariffMnt: 1500,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    fakeLocation.emit(
      const GpsFix(lat: 47.90, lon: 106.90, timestampSeconds: 1000),
    );
    await tester.pump();
    fakeLocation.emit(
      const GpsFix(lat: 47.92, lon: 106.93, timestampSeconds: 1300),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // A live fare figure is now on screen -- not asserting the exact
    // number (GPS distance math is covered headlessly in
    // metered_trip_pricing_test.dart), just that the metered-mode
    // display is actually wired in.
    expect(find.textContaining('₮'), findsWidgets);

    await tester.tap(find.text('Зорчигч сууллаа'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Аялал дууслаа'));
    await tester.pumpAndSettle();

    final endFrame =
        jsonDecode(
              sockets['wss://a']!.sent.lastWhere(
                (s) => s.contains('"kind":1059'),
              ),
            )
            as List<dynamic>;
    final endWrap = NostrEvent.fromJson(endFrame[1] as Map<String, dynamic>);
    final endUnwrapped = nip17Unwrap(endWrap, passenger.privateHex);
    final endPayload =
        RideDmPayload.decode(endUnwrapped.rumor.content)
            as RideTripStatusPayload;
    expect(endPayload.phase, TripPhase.arrived);
    // Computed from the driver's own two GPS fixes above -- exact match,
    // not just "some positive number".
    final expectedDistance = haversineMeters(
      47.90,
      106.90,
      47.92,
      106.93,
    ).round();
    expect(
      endPayload.finalFareMnt,
      computeFareMnt(mntPerKm: 1500, distanceMeters: expectedDistance),
    );
  });

  testWidgets(
    'passenger role, metered: an arrived status with a final fare shows a '
    'confirm step; confirming publishes a receipt priced at that fare',
    (tester) async {
      final passengerStore = InMemoryKeyStore();
      final passengerIdentity = await IdentityService(
        passengerStore,
      ).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 62));

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
                tripId: 'trip-metered-2',
                counterpartyPubHex: driver.publicHex,
                agreedPriceMnt: 0,
                kmTariffMnt: 1500,
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
      final statusWrap = nip17Wrap(
        senderPrivHex: driver.privateHex,
        recipientPubHex: passengerIdentity.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const RideTripStatusPayload(
          tripId: 'trip-metered-2',
          phase: TripPhase.arrived,
          finalFareMnt: 8200,
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', statusSubId, statusWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      // Confirm step reached, NOT the star-rating step yet.
      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(find.text('Батлах'), findsOneWidget);
      expect(find.text('Татгалзах'), findsOneWidget);

      await tester.tap(find.text('Батлах'));
      await tester.pumpAndSettle();

      // Now on the rating step.
      expect(find.byIcon(Icons.star_border), findsNWidgets(5));
      await tester.tap(find.byIcon(Icons.star_border).first);
      // The star tap's setState (which is what enables the submit button)
      // is only flushed by the next pump -- without this, the tap below
      // would hit a still-disabled button from the previous frame.
      await tester.pump();
      await tester.tap(find.text('Илгээх'));
      await tester.pumpAndSettle();

      final receiptFrame =
          jsonDecode(
                sockets['wss://a']!.sent.lastWhere(
                  (s) => s.contains('"kind":30177'),
                ),
              )
              as List<dynamic>;
      final receiptEvent = NostrEvent.fromJson(
        receiptFrame[1] as Map<String, dynamic>,
      );
      final receipt = parseTripReceipt(receiptEvent);
      expect(receipt.priceMnt, 8200);
    },
  );

  testWidgets(
    'passenger role, metered: a fare that includes waiting time is confirmed '
    'as a breakdown -- distance fare plus waiting fare, adding to the total',
    (tester) async {
      final passengerStore = InMemoryKeyStore();
      final passengerIdentity = await IdentityService(
        passengerStore,
      ).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 64));

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
                tripId: 'trip-metered-4',
                counterpartyPubHex: driver.publicHex,
                agreedPriceMnt: 0,
                kmTariffMnt: 1500,
                // The trip rate, not the waiting rate: a red light is part
                // of the trip. The waiting rate is for the passenger
                // keeping the driver, and only the driver invokes it.
                durationTariffMntPerMinute: 300,
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
      final statusWrap = nip17Wrap(
        senderPrivHex: driver.privateHex,
        recipientPubHex: passengerIdentity.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const RideTripStatusPayload(
          tripId: 'trip-metered-4',
          phase: TripPhase.arrived,
          finalFareMnt: 8200,
          finalWaitingFareMnt: 1500,
          finalWaitingSeconds: 300,
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', statusSubId, statusWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      // The total the passenger is asked to sign, and the two halves it is
      // made of -- 8200 - 1500 = 6700 of driving, 1500 of standing still.
      //
      // The figure and the word naming it are two lines on screen now,
      // so they are asserted as two widgets; the sentence a screen
      // reader hears instead is checked as well, because that spoken
      // form is the only place this number still arrives with its own
      // name attached to it.
      expect(find.text('${groupedMnt(8200)}\u00A0₮'), findsOneWidget);
      expect(find.text('Нийт'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Тохирсон үнэ: ${groupedMnt(8200)}\u00A0₮'),
        findsOneWidget,
      );
      expect(find.text('Замын хөлс'), findsOneWidget);
      expect(find.text('${groupedMnt(6700)}\u00A0₮'), findsOneWidget);
      expect(find.text('Зогсолтын хөлс (5 мин)'), findsOneWidget);
      expect(find.text('${groupedMnt(1500)}\u00A0₮'), findsOneWidget);

      await tester.tap(find.text('Батлах'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_border).first);
      await tester.pump();
      await tester.tap(find.text('Илгээх'));
      await tester.pumpAndSettle();

      final receipt = parseTripReceipt(
        NostrEvent.fromJson(
          (jsonDecode(
                    sockets['wss://a']!.sent.lastWhere(
                      (s) => s.contains('"kind":30177'),
                    ),
                  )
                  as List<dynamic>)[1]
              as Map<String, dynamic>,
        ),
      );
      expect(receipt.priceMnt, 8200);
      expect(receipt.waitingFareMnt, 1500);
      expect(receipt.distanceFareMnt, 6700);
    },
  );

  testWidgets(
    'passenger role, metered: a fare with a booking base and a floor lift is '
    'confirmed as a breakdown -- base and top-up as their own rows, neither '
    'folded into distance',
    (tester) async {
      final passengerStore = InMemoryKeyStore();
      final passengerIdentity = await IdentityService(
        passengerStore,
      ).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 69));

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
                tripId: 'trip-metered-fees-2',
                counterpartyPubHex: driver.publicHex,
                agreedPriceMnt: 0,
                kmTariffMnt: 1500,
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
      final statusWrap = nip17Wrap(
        senderPrivHex: driver.privateHex,
        recipientPubHex: passengerIdentity.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const RideTripStatusPayload(
          tripId: 'trip-metered-fees-2',
          phase: TripPhase.arrived,
          finalFareMnt: 10000,
          finalBaseFareMnt: 1500,
          finalMinFareTopUpMnt: 800,
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', statusSubId, statusWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      // Total, and the three rows it is made of: 1500 booking base + 7700 of
      // driving + 800 lifted to the floor = 10000. The distance row is the
      // total minus the base AND the top-up, so neither is reported as a
      // kilometre the car did not drive.
      expect(find.text('${groupedMnt(10000)} ₮'), findsOneWidget);
      expect(find.text('Нийт'), findsOneWidget);
      expect(find.text('Дуудлагын суурь'), findsOneWidget);
      expect(find.text('${groupedMnt(1500)} ₮'), findsOneWidget);
      expect(find.text('Замын хөлс'), findsOneWidget);
      expect(find.text('${groupedMnt(7700)} ₮'), findsOneWidget);
      expect(find.text('Доод хязгаарын нэмэгдэл'), findsOneWidget);
      expect(find.text('${groupedMnt(800)} ₮'), findsOneWidget);

      await tester.tap(find.text('Батлах'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_border).first);
      await tester.pump();
      await tester.tap(find.text('Илгээх'));
      await tester.pumpAndSettle();

      final receipt = parseTripReceipt(
        NostrEvent.fromJson(
          (jsonDecode(
                    sockets['wss://a']!.sent.lastWhere(
                      (s) => s.contains('"kind":30177'),
                    ),
                  )
                  as List<dynamic>)[1]
              as Map<String, dynamic>,
        ),
      );
      // The receipt still signs the one authoritative total.
      expect(receipt.priceMnt, 10000);
    },
  );

  testWidgets(
    'passenger role, metered: a fare with no waiting time is confirmed as the '
    'single figure it is -- no empty breakdown rows',
    (tester) async {
      final passengerStore = InMemoryKeyStore();
      final passengerIdentity = await IdentityService(
        passengerStore,
      ).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 65));

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
                tripId: 'trip-metered-5',
                counterpartyPubHex: driver.publicHex,
                agreedPriceMnt: 0,
                kmTariffMnt: 1500,
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
              tripId: 'trip-metered-5',
              phase: TripPhase.arrived,
              finalFareMnt: 7400,
            ).encode(),
            now: 1000,
          ).toJson(),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('${groupedMnt(7400)}\u00A0₮'), findsOneWidget);
      expect(find.text('Нийт'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Тохирсон үнэ: ${groupedMnt(7400)}\u00A0₮'),
        findsOneWidget,
      );
      expect(find.text('Замын хөлс'), findsNothing);
      expect(find.textContaining('Зогсолтын хөлс'), findsNothing);
    },
  );

  testWidgets(
    'driver role, metered: while the car is stopped the trip screen says so '
    'and shows what the wait has cost, so a frozen km figure reads as the '
    'other meter running rather than a broken one',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 66));

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
                tripId: 'trip-metered-6',
                counterpartyPubHex: passenger.publicHex,
                agreedPriceMnt: 0,
                kmTariffMnt: 1500,
                // The trip rate, not the waiting rate: a red light is part
                // of the trip. The waiting rate is for the passenger
                // keeping the driver, and only the driver invokes it.
                durationTariffMntPerMinute: 300,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Driving first: no waiting claimed before one has been measured.
      fakeLocation.emit(
        const GpsFix(lat: 47.90, lon: 106.90, timestampSeconds: 1000),
      );
      await tester.pump();
      fakeLocation.emit(
        const GpsFix(lat: 47.92, lon: 106.93, timestampSeconds: 1300),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Хүлээж байна'), findsNothing);

      // Then five minutes at a light, the phone's fix drifting two metres.
      fakeLocation.emit(
        const GpsFix(lat: 47.920018, lon: 106.93, timestampSeconds: 1600),
      );
      await tester.pumpAndSettle();

      // 300₮/мин × 5 мин -- and the drift is not billed as distance too.
      expect(
        find.text('Зогсож байна · ${groupedMnt(1500)}\u00A0₮'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'passenger role, metered: declining the final fare skips publishing a '
    'receipt entirely',
    (tester) async {
      final passengerStore = InMemoryKeyStore();
      final passengerIdentity = await IdentityService(
        passengerStore,
      ).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 63));

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
                tripId: 'trip-metered-3',
                counterpartyPubHex: driver.publicHex,
                agreedPriceMnt: 0,
                kmTariffMnt: 1500,
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
      final statusWrap = nip17Wrap(
        senderPrivHex: driver.privateHex,
        recipientPubHex: passengerIdentity.pubHex,
        rumorKind: kRumorKindRideDm,
        content: const RideTripStatusPayload(
          tripId: 'trip-metered-3',
          phase: TripPhase.arrived,
          finalFareMnt: 9100,
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', statusSubId, statusWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Татгалзах'));
      await tester.pumpAndSettle();

      expect(
        sockets['wss://a']!.sent.any((s) => s.contains('"kind":30177')),
        isFalse,
      );
      expect(
        find.text('Та дүнг батлаагүй тул баримт нийтлэгдсэнгүй'),
        findsOneWidget,
      );
    },
  );

  // The whole point of publishing the booking base and the minimum fare on the
  // driver profile: a matched (Nostr-arranged) trip must price them, not only
  // the offline street-hail meter. These two prove the wiring end to end --
  // `ActiveTripView` feeds its `bookingBaseMnt`/`minFareMnt` into the trip's
  // `MeterSession` (as its boarding fee and its floor), so the fare the driver
  // reports on ending the trip actually carries them.

  testWidgets('driver role, metered: the booking base is added once to the '
      'reported final fare', (tester) async {
    final fare = await _reportedFinalFare(
      tester,
      kmTariffMnt: 1500,
      bookingBaseMnt: 1000,
      // No floor, so the booking base is visible rather than absorbed under a
      // minimum -- this case isolates the base.
      minFareMnt: 0,
      passengerSeed: List<int>.filled(32, 67),
    );
    final distanceMeters = haversineMeters(47.90, 106.90, 47.92, 106.93).round();
    final distanceFare = computeFareMnt(
      mntPerKm: 1500,
      distanceMeters: distanceMeters,
    );
    // Distance fare plus the flat booking base charged once at trip start.
    expect(fare, distanceFare + 1000);
  });

  testWidgets('driver role, metered: a short trip is lifted to the minimum '
      'fare in the reported final fare', (tester) async {
    final fare = await _reportedFinalFare(
      tester,
      kmTariffMnt: 1500,
      bookingBaseMnt: 0,
      // Far above anything a ~3km trip at 1500₮/km could reach, so the floor
      // is what decides the total.
      minFareMnt: 50000,
      passengerSeed: List<int>.filled(32, 68),
    );
    expect(fare, 50000);
  });
}

/// Runs one whole driver-side metered trip -- two GPS fixes, board, end -- and
/// returns the `finalFareMnt` the driver reports to the passenger. Factored
/// out of the trip flow the tests above spell inline, so the booking-base and
/// minimum-fare cases can each state just the rates they vary and the number
/// they expect.
Future<int> _reportedFinalFare(
  WidgetTester tester, {
  required int kmTariffMnt,
  required int bookingBaseMnt,
  required int minFareMnt,
  required List<int> passengerSeed,
}) async {
  final driverStore = InMemoryKeyStore();
  await IdentityService(driverStore).createNew();
  final passenger = generateKeyPair(passengerSeed);

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
            tripId: 'trip-metered-fees',
            counterpartyPubHex: passenger.publicHex,
            agreedPriceMnt: 0,
            kmTariffMnt: kmTariffMnt,
            bookingBaseMnt: bookingBaseMnt,
            minFareMnt: minFareMnt,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  fakeLocation.emit(
    const GpsFix(lat: 47.90, lon: 106.90, timestampSeconds: 1000),
  );
  await tester.pump();
  fakeLocation.emit(
    const GpsFix(lat: 47.92, lon: 106.93, timestampSeconds: 1300),
  );
  await tester.pump();
  await tester.pumpAndSettle();

  await tester.tap(find.text('Зорчигч сууллаа'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Аялал дууслаа'));
  await tester.pumpAndSettle();

  final endFrame =
      jsonDecode(
            sockets['wss://a']!.sent.lastWhere((s) => s.contains('"kind":1059')),
          )
          as List<dynamic>;
  final endWrap = NostrEvent.fromJson(endFrame[1] as Map<String, dynamic>);
  final endUnwrapped = nip17Unwrap(endWrap, passenger.privateHex);
  final endPayload =
      RideDmPayload.decode(endUnwrapped.rumor.content) as RideTripStatusPayload;
  return endPayload.finalFareMnt!;
}
