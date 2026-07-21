// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_engine.dart';
import 'package:takhi/call/call_service.dart';
import 'package:takhi/call/call_signal_service.dart';
import 'package:takhi/call/helper_directory_service.dart';
import 'package:takhi/call/phone_share_settings.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_call_engine.dart';
import '../support/fake_relay_socket.dart';

void main() {
  final caller = generateKeyPair(List<int>.filled(32, 121));
  final callee = generateKeyPair(List<int>.filled(32, 122));

  ({RelayPool pool, Map<String, FakeRelaySocket> sockets}) freshPool() {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    return (pool: pool, sockets: sockets);
  }

  test('startAsCaller creates an offer, sends it, and reaches connected '
      'once the engine reports connected', () async {
    final rp = freshPool();
    await rp.pool.connectAll();
    final engine = FakeCallEngine();
    final service = CallService(
      engine: engine,
      signal: CallSignalService(RideDmChannel(rp.pool)),
      helperDirectory: HelperDirectoryService(rp.pool),
      phoneShareSettings: InMemoryPhoneShareSettingsStore(),
      myPubHex: caller.publicHex,
      myPrivHex: caller.privateHex,
      counterpartyPubHex: callee.publicHex,
      tripId: 'trip-1',
    );

    final states = <CallState>[];
    final sub = service.state.listen(states.add);

    await service.startAsCaller(now: () => 1000);
    expect(states.whereType<CallStateDialing>(), isNotEmpty);
    // The offer was actually published as a gift-wrapped DM.
    expect(
      rp.sockets['wss://a']!.sent.any((f) => f.contains('"kind":1059')),
      isTrue,
    );

    engine.emitConnectionState(CallConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    expect(states.whereType<CallStateConnected>(), isNotEmpty);

    await sub.cancel();
    await service.dispose();
  });

  test('a WebRTC failure with no known phone number falls to a voice-note '
      'offer', () async {
    final rp = freshPool();
    await rp.pool.connectAll();
    final engine = FakeCallEngine();
    final service = CallService(
      engine: engine,
      signal: CallSignalService(RideDmChannel(rp.pool)),
      helperDirectory: HelperDirectoryService(rp.pool),
      phoneShareSettings: InMemoryPhoneShareSettingsStore(),
      myPubHex: caller.publicHex,
      myPrivHex: caller.privateHex,
      counterpartyPubHex: callee.publicHex,
      tripId: 'trip-1',
      counterpartyPhone: null,
    );

    final states = <CallState>[];
    final sub = service.state.listen(states.add);
    await service.startAsCaller(now: () => 1000);

    engine.emitConnectionState(CallConnectionState.failed);
    await Future<void>.delayed(Duration.zero);

    expect(states.whereType<CallStateFallbackVoiceNote>(), isNotEmpty);
    await sub.cancel();
    await service.dispose();
  });

  test('a WebRTC failure with a known, shared phone number falls to '
      'offering a phone call', () async {
    final rp = freshPool();
    await rp.pool.connectAll();
    final engine = FakeCallEngine();
    final phoneSettings = InMemoryPhoneShareSettingsStore();
    final service = CallService(
      engine: engine,
      signal: CallSignalService(RideDmChannel(rp.pool)),
      helperDirectory: HelperDirectoryService(rp.pool),
      phoneShareSettings: phoneSettings,
      myPubHex: caller.publicHex,
      myPrivHex: caller.privateHex,
      counterpartyPubHex: callee.publicHex,
      tripId: 'trip-1',
      counterpartyPhone: '99112233',
    );

    final states = <CallState>[];
    final sub = service.state.listen(states.add);
    await service.startAsCaller(now: () => 1000);

    engine.emitConnectionState(CallConnectionState.failed);
    await Future<void>.delayed(Duration.zero);

    final fallback = states.whereType<CallStateFallbackPhone>().single;
    expect(fallback.phone, '99112233');
    await sub.cancel();
    await service.dispose();
  });

  test('hangUp sends a CallHangupPayload and emits CallStateEnded',
      () async {
    final rp = freshPool();
    await rp.pool.connectAll();
    final service = CallService(
      engine: FakeCallEngine(),
      signal: CallSignalService(RideDmChannel(rp.pool)),
      helperDirectory: HelperDirectoryService(rp.pool),
      phoneShareSettings: InMemoryPhoneShareSettingsStore(),
      myPubHex: caller.publicHex,
      myPrivHex: caller.privateHex,
      counterpartyPubHex: callee.publicHex,
      tripId: 'trip-1',
    );
    final states = <CallState>[];
    final sub = service.state.listen(states.add);

    await service.startAsCaller(now: () => 1000);
    await service.hangUp(now: () => 1001);

    expect(states.whereType<CallStateEnded>(), isNotEmpty);
    final hangupSent = rp.sockets['wss://a']!.sent
        .where((f) => f.contains('"kind":1059'))
        .length;
    expect(hangupSent, greaterThanOrEqualTo(2)); // offer + hangup
    await sub.cancel();
  });
}
