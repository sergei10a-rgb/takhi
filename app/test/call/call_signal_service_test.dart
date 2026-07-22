// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_signal_service.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final caller = generateKeyPair(List<int>.filled(32, 111));
  final callee = generateKeyPair(List<int>.filled(32, 112));

  test('sendOffer delivers a CallOfferPayload, watchSignals filters by '
      'tripId', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = CallSignalService(RideDmChannel(pool));

    final got = <ReceivedCallSignal>[];
    final sub = service
        .watchSignals(callee.publicHex, callee.privateHex, 'trip-1')
        .listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);

    await service.sendOffer(
      privHex: caller.privateHex,
      recipientPubHex: callee.publicHex,
      tripId: 'trip-1',
      sdp: 'v=0\r\n...',
      now: 1000,
    );
    final sentFrame = _lastEventFrame(sockets['wss://a']!);
    sockets['wss://a']!.emit(_deliver(subId, sentFrame));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, caller.publicHex);
    expect(got.first.payload, isA<CallOfferPayload>());
    expect((got.first.payload as CallOfferPayload).sdp, 'v=0\r\n...');
    await sub.cancel();
  });

  test('watchSignals never yields a signal for a different tripId',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = CallSignalService(RideDmChannel(pool));

    final got = <ReceivedCallSignal>[];
    final sub = service
        .watchSignals(callee.publicHex, callee.privateHex, 'trip-1')
        .listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);

    await service.sendHangup(
      privHex: caller.privateHex,
      recipientPubHex: callee.publicHex,
      tripId: 'trip-OTHER',
      now: 1000,
    );
    final sentFrame = _lastEventFrame(sockets['wss://a']!);
    sockets['wss://a']!.emit(_deliver(subId, sentFrame));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got, isEmpty);
    await sub.cancel();
  });

  test(
    'watchSignals ignores a non-call payload sharing the same tripId '
    '(RideTripStatusPayload) -- neither emits nor throws',
    () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final dm = RideDmChannel(pool);
      final service = CallSignalService(dm);

      final got = <ReceivedCallSignal>[];
      final errors = <Object>[];
      final sub = service
          .watchSignals(callee.publicHex, callee.privateHex, 'trip-1')
          .listen(got.add, onError: errors.add);
      final subId = _reqSubId(sockets['wss://a']!);

      // A same-tripId RideTripStatusPayload arrives on the very same inbox
      // stream watchSignals filters -- this is the realistic collision
      // (one active trip shares its tripId across trip_status and call
      // signals), not just a different-tripId call payload.
      await dm.send(
        senderPrivHex: caller.privateHex,
        recipientPubHex: callee.publicHex,
        payload: const RideTripStatusPayload(
          tripId: 'trip-1',
          phase: TripPhase.arrived,
        ),
        now: 1000,
      );
      final sentFrame = _lastEventFrame(sockets['wss://a']!);
      sockets['wss://a']!.emit(_deliver(subId, sentFrame));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(got, isEmpty);
      expect(errors, isEmpty);
      await sub.cancel();
    },
  );
}

String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecodeList(raw);
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}

dynamic _lastEventFrame(FakeRelaySocket socket) =>
    jsonDecodeList(socket.sent.last)[1];

String _deliver(String subId, dynamic eventJson) =>
    jsonEncodeFrame(['EVENT', subId, eventJson]);

List<dynamic> jsonDecodeList(String raw) => (jsonDecode(raw) as List<dynamic>);
String jsonEncodeFrame(List<dynamic> frame) => jsonEncode(frame);
