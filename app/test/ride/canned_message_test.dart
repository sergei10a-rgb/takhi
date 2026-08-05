// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Canned messages are the one-tap "on my way" / "I'm here" / "coming out"
// presets two people trade while finding each other at the kerb. These pin
// the wire contract (rename-safe tokens, an unknown preset dropped rather
// than guessed), the role split, and one end-to-end send/receive over the
// same NIP-17 channel every ride DM uses.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/canned_message.dart';
import 'package:takhi/ride/canned_message_service.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  group('CannedMessage wire', () {
    test('every value has a distinct wire token', () {
      final tokens = CannedMessage.values.map((m) => m.wireValue).toSet();
      expect(tokens.length, CannedMessage.values.length);
    });

    test('fromWire round-trips every value', () {
      for (final m in CannedMessage.values) {
        expect(CannedMessage.fromWire(m.wireValue), m);
      }
    });

    test('fromWire throws on an unrecognized token, so a preset a newer '
        'client added is dropped rather than guessed', () {
      expect(
        () => CannedMessage.fromWire('driver_landed_helicopter'),
        throwsFormatException,
      );
    });

    test('the driver sends two, the passenger the other two', () {
      final fromDriver =
          CannedMessage.values.where((m) => m.isFromDriver).toSet();
      expect(fromDriver, {
        CannedMessage.driverOnMyWay,
        CannedMessage.driverArrived,
      });
      final fromPassenger =
          CannedMessage.values.where((m) => !m.isFromDriver).toSet();
      expect(fromPassenger, {
        CannedMessage.passengerComingOut,
        CannedMessage.passengerOneMoment,
      });
    });
  });

  group('RideCannedMessagePayload', () {
    test('round-trips through encode/decode', () {
      final payload = const RideCannedMessagePayload(
        tripId: 'trip1',
        message: CannedMessage.driverArrived,
      );
      final decoded =
          RideDmPayload.decode(payload.encode())
              as RideCannedMessagePayload;
      expect(decoded.tripId, 'trip1');
      expect(decoded.message, CannedMessage.driverArrived);
    });

    test('decode drops a message with an unknown preset token', () {
      // Thrown, then swallowed by the inbox's per-wrap guard — the banner
      // is simply never raised, and the trip around it is untouched.
      expect(
        () => RideDmPayload.decode(
          jsonEncode({
            'type': 'canned_message',
            'tripId': 'trip1',
            'message': 'passenger_ordered_pizza',
          }),
        ),
        throwsFormatException,
      );
    });

    test('decode throws when tripId is missing', () {
      expect(
        () => RideDmPayload.decode(
          jsonEncode({
            'type': 'canned_message',
            'message': 'driver_arrived',
          }),
        ),
        throwsFormatException,
      );
    });
  });

  test('a sent canned message reaches the other side, decoded', () async {
    final sender = generateKeyPair(List<int>.filled(32, 121));
    final receiver = generateKeyPair(List<int>.filled(32, 122));

    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = CannedMessageService(RideDmChannel(pool));

    final got = <ReceivedCannedMessage>[];
    final sub = service
        .watch(receiver.publicHex, receiver.privateHex)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await service.send(
      senderPrivHex: sender.privateHex,
      recipientPubHex: receiver.publicHex,
      tripId: 'trip1',
      message: CannedMessage.passengerComingOut,
      now: 1000,
    );
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, sender.publicHex);
    expect(got.first.tripId, 'trip1');
    expect(got.first.message, CannedMessage.passengerComingOut);

    await sub.cancel();
  });
}
