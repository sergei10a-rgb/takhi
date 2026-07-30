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
                waitTariffMntPerMinute: 300,
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
      expect(find.text('Хүлээлгийн хөлс (5 мин)'), findsOneWidget);
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
      expect(find.textContaining('Хүлээлгийн хөлс'), findsNothing);
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
                waitTariffMntPerMinute: 300,
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
        find.text('Хүлээж байна · ${groupedMnt(1500)}\u00A0₮'),
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
}
