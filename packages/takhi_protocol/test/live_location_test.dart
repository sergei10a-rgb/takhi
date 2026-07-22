// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  final sender = generateKeyPair(List<int>.filled(32, 71));
  final recipient = generateKeyPair(List<int>.filled(32, 72));

  test(
      'buildLiveLocationEvent has kind 20178, a p tag, a d tag, and an '
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

  test('parseLiveLocationEvent throws when decrypted with the wrong key', () {
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

  // Builds a live-location-kind event whose decrypted content is
  // [rawPayload] verbatim, bypassing buildLiveLocationEvent's
  // {tripId, lat, lon} shape so the malformed-payload guard clauses in
  // parseLiveLocationEvent can be exercised directly. Mirrors
  // takhi_events_test.dart's pattern of hand-building an event to hit a
  // specific parser guard branch. parseLiveLocationEvent does not call
  // verifyEvent, so the event need not be signed.
  NostrEvent eventWithRawPayload(String rawPayload) {
    final encrypted = nip44Encrypt(
      rawPayload,
      sender.privateHex,
      recipient.publicHex,
    );
    return NostrEvent(
      pubkey: sender.publicHex,
      createdAt: 1000,
      kind: kKindLiveLocation,
      tags: [
        ['p', recipient.publicHex],
        ['d', 'trip-1'],
        ['expiration', '1030'],
      ],
      content: encrypted,
    );
  }

  test(
      'parseLiveLocationEvent rejects a decrypted payload that is not a '
      'JSON object', () {
    final e = eventWithRawPayload(jsonEncode([1, 2, 3]));
    expect(() => parseLiveLocationEvent(e, recipient.privateHex),
        throwsFormatException);
  });

  test(
      'parseLiveLocationEvent rejects a payload whose tripId is not a '
      'String', () {
    final e = eventWithRawPayload(
        jsonEncode({'tripId': 42, 'lat': 47.9186, 'lon': 106.9176}));
    expect(() => parseLiveLocationEvent(e, recipient.privateHex),
        throwsFormatException);
  });

  test('parseLiveLocationEvent rejects a payload whose lat is not a num', () {
    final e = eventWithRawPayload(
        jsonEncode({'tripId': 'trip-1', 'lat': 'north', 'lon': 106.9176}));
    expect(() => parseLiveLocationEvent(e, recipient.privateHex),
        throwsFormatException);
  });

  test('parseLiveLocationEvent rejects a payload whose lon is not a num', () {
    final e = eventWithRawPayload(
        jsonEncode({'tripId': 'trip-1', 'lat': 47.9186, 'lon': 'east'}));
    expect(() => parseLiveLocationEvent(e, recipient.privateHex),
        throwsFormatException);
  });
}
