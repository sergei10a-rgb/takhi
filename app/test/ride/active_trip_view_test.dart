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
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

void main() {
  testWidgets(
    'driver role: live-location ping, phase buttons, rating publish a '
    'receipt',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      final driver = await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 91));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();

      // `ActiveTripView.initState` starts subscribing (live-location watch)
      // as soon as identity resolves, which can happen during the
      // `pumpWidget` await itself -- mirrors `DriverInboxPage`'s test.
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
                tripId: 'trip-1',
                counterpartyPubHex: passenger.publicHex,
                agreedPriceMnt: 5000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Two fixes: the throttle forwards every 2nd fix, so this guarantees
      // at least one live-location ping (kind 20178) was published.
      fakeLocation.emit(
        const GpsFix(lat: 47.90, lon: 106.90, timestampSeconds: 1000),
      );
      await tester.pump();
      fakeLocation.emit(
        const GpsFix(lat: 47.91, lon: 106.91, timestampSeconds: 1010),
      );
      await tester.pump();

      expect(
        sockets['wss://a']!.sent.any((s) => s.contains('"kind":20178')),
        isTrue,
      );

      // Phase 1: driver marks the passenger boarded.
      await tester.tap(find.text('Зорчигч сууллаа'));
      await tester.pumpAndSettle();

      final boardedFrame =
          jsonDecode(
                sockets['wss://a']!.sent.lastWhere(
                  (s) => s.contains('"kind":1059'),
                ),
              )
              as List<dynamic>;
      final boardedWrap = NostrEvent.fromJson(
        boardedFrame[1] as Map<String, dynamic>,
      );
      final boardedUnwrapped = nip17Unwrap(boardedWrap, passenger.privateHex);
      final boardedPayload =
          RideDmPayload.decode(boardedUnwrapped.rumor.content)
              as RideTripStatusPayload;
      expect(boardedUnwrapped.senderPubkey, driver.pubHex);
      expect(boardedPayload.tripId, 'trip-1');
      expect(boardedPayload.phase, TripPhase.tripInProgress);

      // Phase 2: driver ends the trip.
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
      expect(endPayload.tripId, 'trip-1');
      expect(endPayload.phase, TripPhase.arrived);

      // Now in the rating step -- select 4 stars and submit.
      final starButtons = find.byIcon(Icons.star_border);
      expect(starButtons, findsNWidgets(5));
      await tester.tap(starButtons.at(3));
      await tester.pumpAndSettle();
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
      expect(receipt.tripId, 'trip-1');
      expect(receipt.priceMnt, 5000);
      expect(receipt.ratingStars, 4);
      expect(receipt.role, 'driver');

      // Done step.
      expect(find.text('Баримт нийтлэгдлээ'), findsOneWidget);
    },
  );

  testWidgets(
    'passenger role: an incoming arrived status reaches the rating step '
    'without any local button tap',
    (tester) async {
      final passengerStore = InMemoryKeyStore();
      final passengerIdentity = await IdentityService(
        passengerStore,
      ).createNew();
      final driver = generateKeyPair(List<int>.filled(32, 92));

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
                tripId: 'trip-2',
                counterpartyPubHex: driver.publicHex,
                agreedPriceMnt: 7000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No driver-only phase buttons on the passenger side.
      expect(find.text('Зорчигч сууллаа'), findsNothing);
      expect(find.text('Аялал дууслаа'), findsNothing);

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
          tripId: 'trip-2',
          phase: TripPhase.arrived,
        ).encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', statusSubId, statusWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      // Reached the rating step (5 star toggles visible) with no local tap.
      expect(find.byIcon(Icons.star_border), findsNWidgets(5));
    },
  );

  testWidgets('rating step: submitting with zero stars selected is a no-op '
      '(no ArgumentError, no receipt published)', (tester) async {
    final passengerStore = InMemoryKeyStore();
    final passengerIdentity = await IdentityService(passengerStore).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 94));

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
              tripId: 'trip-4',
              counterpartyPubHex: driver.publicHex,
              agreedPriceMnt: 4000,
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
        tripId: 'trip-4',
        phase: TripPhase.arrived,
      ).encode(),
      now: 1000,
    );
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', statusSubId, statusWrap.toJson()]),
    );
    await tester.pumpAndSettle();

    // Rating step reached, nothing selected yet.
    expect(find.byIcon(Icons.star_border), findsNWidgets(5));

    // Tapping submit with 0 stars must not throw and must not publish a
    // trip receipt (kind 30177) or advance to the done step.
    await tester.tap(find.text('Илгээх'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      sockets['wss://a']!.sent.any((s) => s.contains('"kind":30177')),
      isFalse,
    );
    expect(find.byIcon(Icons.star_border), findsNWidgets(5));
  });

  testWidgets(
    'denied location permission shows the retry view, and retrying with '
    'permission granted reaches tracking',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 93));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();

      // First call (initial `initState`-driven `_startTracking`) denies;
      // every call after (the retry tap) grants -- exercises both the
      // `_locationPermissionDenied = true` branch (`_LocationPermissionDeniedView`)
      // and the retry path back into `_startTracking`, neither of which
      // the other two scenarios above cover (both override this provider
      // with a constant `() async => true`).
      var callCount = 0;
      Future<bool> checkPermission() async {
        callCount++;
        return callCount > 1;
      }

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(driverStore),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(checkPermission),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: Scaffold(
              body: ActiveTripView(
                role: TripRole.driver,
                tripId: 'trip-3',
                counterpartyPubHex: passenger.publicHex,
                agreedPriceMnt: 3000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Denied: the retry view is shown, not the map/tracking controls.
      expect(
        find.text('Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай'),
        findsOneWidget,
      );
      expect(find.text('Зорчигч сууллаа'), findsNothing);

      // Retry: permission now granted, tracking view takes over.
      await tester.tap(find.text('Зөвшөөрөл өгөх'));
      await tester.pumpAndSettle();

      expect(
        find.text('Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай'),
        findsNothing,
      );
      expect(find.text('Зорчигч сууллаа'), findsOneWidget);
    },
  );
}
