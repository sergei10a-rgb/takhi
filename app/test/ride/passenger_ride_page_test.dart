// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/passenger_ride_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
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

    expect(find.textContaining('6000'), findsOneWidget);

    await tester.tap(find.textContaining('6000'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Prius'), findsOneWidget);
  });
}
