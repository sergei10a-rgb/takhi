// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi/safety/emergency_contact_store.dart';
import 'package:takhi/safety/safety_providers.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// Guards Task 9 Step 10's wiring of `SosButton` into `ActiveTripView`'s
/// tracking row -- mirrors `active_trip_view_call_test.dart`
/// (`Icons.call`) and `active_trip_view_test.dart`'s share test
/// (`Icons.share`), which each assert their button is actually present
/// and reachable in the composed tree. Without this, a future edit could
/// silently drop `SosButton(lastFix: lastFix)` from `_TrackingView` and
/// nothing would fail.
void main() {
  testWidgets(
    'tapping the SOS button in the tracking view opens the emergency '
    'action sheet',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 97));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();
      final contactStore = InMemoryEmergencyContactStore();
      await contactStore.savePhone('99887766');

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(driverStore),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            emergencyContactStoreProvider.overrideWithValue(contactStore),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: Scaffold(
              body: ActiveTripView(
                role: TripRole.driver,
                tripId: 'trip-sos-1',
                counterpartyPubHex: passenger.publicHex,
                agreedPriceMnt: 5000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The SOS button itself must be present in the tracking row.
      expect(find.byIcon(Icons.emergency), findsOneWidget);

      await tester.tap(find.byIcon(Icons.emergency));
      await tester.pumpAndSettle();

      // The action sheet opened with the expected emergency options --
      // proves the button is wired to `_openSheet`, not merely present
      // and inert.
      expect(find.text('102 — цагдаа'), findsOneWidget);
      expect(find.text('103 — түргэн тусламж'), findsOneWidget);
      expect(
        find.text('Яаралтай холбоо барих хүнд SMS'),
        findsOneWidget,
      );
    },
  );
}
