// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  final sender = generateKeyPair(List<int>.filled(32, 71));
  final recipient = generateKeyPair(List<int>.filled(32, 72));

  test('buildLiveLocationEvent has kind 20178, a p tag, a d tag, and an '
      'expiration tag', () {
    final e = buildLiveLocationEvent(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      now: 1000,
      tripId: 'trip-1',
      lat: 47.9186,
      lon: 106.9176,
    );
    expect(e.kind, kKindLiveLocation);
    expect(e.pubkey, sender.publicHex);
    expect(e.tags.firstWhere((t) => t.first == 'p')[1], recipient.publicHex);
    expect(e.tags.firstWhere((t) => t.first == 'd')[1], 'trip-1');
    expect(e.tags.firstWhere((t) => t.first == 'expiration')[1], '1030');
    // The plaintext content must not contain the raw coordinates.
    expect(e.content.contains('47.9186'), isFalse);
  });

  test('buildLiveLocationEvent produces a validly signed event', () {
    final e = buildLiveLocationEvent(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      now: 1000,
      tripId: 'trip-1',
      lat: 47.9186,
      lon: 106.9176,
      auxRand: List<int>.filled(32, 0),
    );
    expect(verifyEvent(e), isTrue);
  });

  test('parseLiveLocationEvent round-trips lat/lon/tripId', () {
    final e = buildLiveLocationEvent(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      now: 1000,
      tripId: 'trip-1',
      lat: 47.9186,
      lon: 106.9176,
    );
    final parsed = parseLiveLocationEvent(e, recipient.privateHex);
    expect(parsed.senderPubkey, sender.publicHex);
    expect(parsed.tripId, 'trip-1');
    expect(parsed.lat, 47.9186);
    expect(parsed.lon, 106.9176);
  });

  test('parseLiveLocationEvent rejects the wrong kind', () {
    final wrong = NostrEvent(
      pubkey: sender.publicHex,
      createdAt: 1000,
      kind: 1,
      tags: const [],
      content: 'x',
    );
    expect(() => parseLiveLocationEvent(wrong, recipient.privateHex),
        throwsFormatException);
  });

  test('parseLiveLocationEvent throws when decrypted with the wrong key',
      () {
    final stranger = generateKeyPair(List<int>.filled(32, 73));
    final e = buildLiveLocationEvent(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      now: 1000,
      tripId: 'trip-1',
      lat: 47.9186,
      lon: 106.9176,
    );
    expect(() => parseLiveLocationEvent(e, stranger.privateHex),
        throwsA(isA<Exception>()));
  });
}
