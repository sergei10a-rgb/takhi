// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_providers.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';
import '../support/fake_voice_note_player.dart';

/// Regression coverage for Plan 5's review CRITICAL-3: before this fix,
/// `VoiceNoteService.watchVoiceNotes`/`VoiceNotePlayer` were never wired
/// into any screen in production -- sending a voice note worked
/// (`CallScreen._stopRecordingAndSend`), but the recipient had no way to
/// know one had arrived, let alone play it back.
void main() {
  testWidgets(
    'driver role: a received voice note shows a notification and a play '
    'chip, and tapping the chip plays it through VoiceNotePlayer',
    (tester) async {
      final driverStore = InMemoryKeyStore();
      final driverIdentity = await IdentityService(driverStore).createNew();
      final passenger = generateKeyPair(List<int>.filled(32, 99));

      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      final fakeLocation = FakeLocationSource();
      final fakePlayer = FakeVoiceNotePlayer();

      await pool.connectAll();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyStoreProvider.overrideWithValue(driverStore),
            relayPoolProvider.overrideWithValue(pool),
            locationSourceProvider.overrideWithValue(fakeLocation),
            locationPermissionCheckProvider.overrideWithValue(() async => true),
            voiceNotePlayerProvider.overrideWithValue(fakePlayer),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: Scaffold(
              body: ActiveTripView(
                role: TripRole.driver,
                tripId: 'trip-voice-1',
                counterpartyPubHex: passenger.publicHex,
                agreedPriceMnt: 5000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No player chip before anything has arrived.
      expect(find.byIcon(Icons.play_arrow), findsNothing);

      // The voice-note subscription is the *first* kind-1059 REQ sent for
      // the driver role -- `IncomingCallListener`'s own call-signal
      // subscription (also kind 1059) is always sent second, from a
      // sibling widget's own identity-future callback (see
      // `ActiveTripView._startTracking`'s doc comment on subscription
      // ordering).
      final voiceNoteSubId =
          (jsonDecode(
                    sockets['wss://a']!.sent.firstWhere(
                      (s) => s.contains('"kinds":[1059]'),
                    ),
                  )
                  as List<dynamic>)[1]
              as String;

      final notePayload = VoiceNotePayload(
        tripId: 'trip-voice-1',
        audioBase64: base64Encode([1, 2, 3, 4]),
        durationSeconds: 4,
      );
      final noteWrap = nip17Wrap(
        senderPrivHex: passenger.privateHex,
        recipientPubHex: driverIdentity.pubHex,
        rumorKind: kRumorKindRideDm,
        content: notePayload.encode(),
        now: 1000,
      );
      sockets['wss://a']!.emit(
        jsonEncode(['EVENT', voiceNoteSubId, noteWrap.toJson()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Дуут зурвас ирлээ'), findsOneWidget); // notification
      expect(find.byIcon(Icons.play_arrow), findsOneWidget); // player chip

      // Tapping the chip itself, not the icon glyph directly -- the whole
      // `ActionChip` (avatar + label) shares one tap target, and its
      // avatar icon's exact hit-testable bounds inside the chip's custom
      // layout are narrower than `find.byIcon` alone would suggest.
      await tester.tap(find.byType(ActionChip));
      await tester.pump();

      expect(fakePlayer.played, [notePayload.audioBase64]);
      expect(find.byIcon(Icons.stop), findsOneWidget);

      await tester.tap(find.byType(ActionChip));
      await tester.pump();

      expect(fakePlayer.stopped, isTrue);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    },
  );

  testWidgets('a voice note for a different trip id is ignored', (
    tester,
  ) async {
    final driverStore = InMemoryKeyStore();
    final driverIdentity = await IdentityService(driverStore).createNew();
    final passenger = generateKeyPair(List<int>.filled(32, 100));

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
          voiceNotePlayerProvider.overrideWithValue(FakeVoiceNotePlayer()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Scaffold(
            body: ActiveTripView(
              role: TripRole.driver,
              tripId: 'trip-voice-2',
              counterpartyPubHex: passenger.publicHex,
              agreedPriceMnt: 5000,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final voiceNoteSubId =
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kinds":[1059]'),
                  ),
                )
                as List<dynamic>)[1]
            as String;

    final noteWrap = nip17Wrap(
      senderPrivHex: passenger.privateHex,
      recipientPubHex: driverIdentity.pubHex,
      rumorKind: kRumorKindRideDm,
      content: const VoiceNotePayload(
        tripId: 'some-other-trip',
        audioBase64: 'AQID',
        durationSeconds: 2,
      ).encode(),
      now: 1000,
    );
    sockets['wss://a']!.emit(
      jsonEncode(['EVENT', voiceNoteSubId, noteWrap.toJson()]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('Дуут зурвас ирлээ'), findsNothing);
  });
}
