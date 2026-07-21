// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/voice_note_service.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  group('validateVoiceNoteAudio', () {
    test('accepts audio within both limits', () {
      expect(
        () => validateVoiceNoteAudio(List.filled(1000, 0), 5),
        returnsNormally,
      );
    });

    test('rejects audio longer than kMaxVoiceNoteDurationSeconds', () {
      expect(
        () => validateVoiceNoteAudio(List.filled(1000, 0), 11),
        throwsA(isA<VoiceNoteTooLongException>()),
      );
    });

    test('rejects audio larger than kMaxVoiceNoteBytes', () {
      expect(
        () => validateVoiceNoteAudio(
          List.filled(kMaxVoiceNoteBytes + 1, 0),
          5,
        ),
        throwsA(isA<VoiceNoteTooLargeException>()),
      );
    });
  });

  group('VoiceNoteService', () {
    final sender = generateKeyPair(List<int>.filled(32, 71));
    final recipient = generateKeyPair(List<int>.filled(32, 72));

    test('send rejects an oversized note before touching the network',
        () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = VoiceNoteService(RideDmChannel(pool));

      await expectLater(
        () => service.send(
          senderPrivHex: sender.privateHex,
          recipientPubHex: recipient.publicHex,
          tripId: 'trip-1',
          audioBytes: List.filled(1000, 0),
          durationSeconds: 11,
          now: 1000,
        ),
        throwsA(isA<VoiceNoteTooLongException>()),
      );
      expect(sockets['wss://a']!.sent, isEmpty);
    });

    test('send delivers a base64-encoded note, watchVoiceNotes decodes it',
        () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = VoiceNoteService(RideDmChannel(pool));

      final got = <ReceivedVoiceNote>[];
      final sub = service
          .watchVoiceNotes(recipient.publicHex, recipient.privateHex)
          .listen(got.add);
      final subId = _reqSubId(sockets['wss://a']!);

      await service.send(
        senderPrivHex: sender.privateHex,
        recipientPubHex: recipient.publicHex,
        tripId: 'trip-1',
        audioBytes: [1, 2, 3, 4],
        durationSeconds: 3,
        now: 1000,
      );
      final sent = jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
      sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, sent[1]]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(got.length, 1);
      expect(got.first.senderPubkey, sender.publicHex);
      expect(got.first.payload.tripId, 'trip-1');
      expect(got.first.payload.durationSeconds, 3);
      expect(base64Decode(got.first.payload.audioBase64), [1, 2, 3, 4]);
      await sub.cancel();
    });
  });
}

String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}
