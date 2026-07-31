// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/call/call_engine.dart';
import 'package:takhi/call/call_providers.dart';
import 'package:takhi/call/call_screen.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_call_engine.dart';
import '../support/fake_relay_socket.dart';

const _home = 'нүүр';
const _tripId = 'trip-call-back';

/// Everything a test needs to keep driving the call it just opened.
class _Call {
  final FakeRelaySocket socket;
  final FakeCallEngine engine;
  const _Call(this.socket, this.engine);

  /// The payload of the last gift wrap this device published, decrypted
  /// with the counterparty's key.
  RideDmPayload lastDmTo(String counterpartyPrivHex) {
    final frame =
        jsonDecode(socket.sent.lastWhere((s) => s.contains('"kind":1059')))
            as List<dynamic>;
    return RideDmPayload.decode(
      nip17Unwrap(
        NostrEvent.fromJson(frame[1] as Map<String, dynamic>),
        counterpartyPrivHex,
      ).rumor.content,
    );
  }
}

/// Pushes [CallScreen] on top of a plain first route, the way
/// `ActiveTripView._startCall` and `IncomingCallListener._accept` both do.
/// `CallScreen` has no `AppBar`, so the only back it can ever receive is
/// the system one -- which is exactly the gesture this file is about.
Future<_Call> _pumpPushedCall(
  WidgetTester t, {
  required InMemoryKeyStore keyStore,
  required String counterpartyPubHex,
}) async {
  final engine = FakeCallEngine();
  final sockets = <String, FakeRelaySocket>{};
  final pool = RelayPool([
    'wss://a',
  ], connect: (u) => sockets[u] = FakeRelaySocket());
  await pool.connectAll();

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(keyStore),
        relayPoolProvider.overrideWithValue(pool),
        callEngineFactoryProvider.overrideWithValue((iceServers) => engine),
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
                    builder: (_) => CallScreen(
                      tripId: _tripId,
                      counterpartyPubHex: counterpartyPubHex,
                      isCaller: true,
                    ),
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

  await t.tap(find.text(_home));
  // The dialing state shows an indefinite spinner, so `pumpAndSettle` would
  // time out -- a handful of explicit pumps is enough for the pushed route
  // to settle and `CallService.startAsCaller` to run to completion (same
  // reasoning as `active_trip_view_call_test.dart`).
  await _pumpABit(t);
  expect(find.byType(CallScreen), findsOneWidget);
  return _Call(sockets['wss://a']!, engine);
}

Future<void> _pumpABit(WidgetTester t, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Delivers the platform's `popRoute` message -- Android's hardware back
/// and iOS' back swipe -- and lets the hang-up it triggers play out.
///
/// The generous trailing pump is deliberate. `_hangUp` awaits the whole of
/// `CallService.hangUp`, whose teardown cancels live relay subscriptions;
/// under `flutter_test`'s fake async those cancellations only settle once
/// the test body itself yields, so the screen leaves through the 2-second
/// auto-pop `CallStateEnded` arms rather than through `_hangUp`'s own pop.
/// Either way it leaves -- and the assertion that matters, the hangup
/// actually reaching the wire, has already happened by then. The pump also
/// flushes that auto-pop timer, which would otherwise still be pending at
/// the end of the test.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await _pumpABit(t);
  await t.pump(const Duration(seconds: 3));
  // ...and then enough frames for the route's exit transition to finish.
  await _pumpABit(t, frames: 10);
}

void main() {
  // `CallService` reads `phoneShareSettingsStoreProvider`, backed by real
  // `shared_preferences` -- same mock the sibling call tests install.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('backing out of a connected call hangs up for real -- the other '
      'side is told, instead of being left on an open mic waiting for a '
      'call nobody is on', (t) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final counterparty = generateKeyPair(List<int>.filled(32, 91));

    final call = await _pumpPushedCall(
      t,
      keyStore: keyStore,
      counterpartyPubHex: counterparty.publicHex,
    );

    call.engine.emitConnectionState(CallConnectionState.connected);
    await _pumpABit(t);
    expect(find.byIcon(Icons.mic), findsOneWidget); // the connected body

    await _systemBack(t);

    // Same outcome as the red hang-up button: a hangup on the wire, and the
    // screen gone. Before this, back popped straight to `dispose`, which
    // sends nothing at all.
    expect(call.lastDmTo(counterparty.privateHex), isA<CallHangupPayload>());
    expect(find.byType(CallScreen), findsNothing);
    expect(find.text(_home), findsOneWidget);
  });

  testWidgets('backing out while still dialing also signals -- a caller who '
      'changes their mind must not leave the callee ringing', (t) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final counterparty = generateKeyPair(List<int>.filled(32, 92));

    final call = await _pumpPushedCall(
      t,
      keyStore: keyStore,
      counterpartyPubHex: counterparty.publicHex,
    );

    // Still dialing: the offer is out, no answer has come back.
    expect(call.lastDmTo(counterparty.privateHex), isA<CallOfferPayload>());

    await _systemBack(t);

    final hangup = call.lastDmTo(counterparty.privateHex);
    expect(hangup, isA<CallHangupPayload>());
    expect(find.byType(CallScreen), findsNothing);
  });
}
