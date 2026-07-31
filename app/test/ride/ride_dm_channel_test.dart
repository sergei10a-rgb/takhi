// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final alice = generateKeyPair(List<int>.filled(32, 51));
  final bob = generateKeyPair(List<int>.filled(32, 52));

  test('send publishes a gift wrap tagged to the recipient', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = RideDmChannel(pool);

    const payload = RideCancelPayload(rideRequestId: 'req1', reason: 'test');
    final wrap = await channel.send(
      senderPrivHex: alice.privateHex,
      recipientPubHex: bob.publicHex,
      payload: payload,
      now: 1700000000,
    );

    expect(wrap.kind, kKindGiftWrap);
    expect(wrap.tags, [
      ['p', bob.publicHex],
    ]);
    final sentFrame =
        jsonDecode(sockets['wss://a']!.sent.single) as List<dynamic>;
    expect(sentFrame[0], 'EVENT');
  });

  test('inbox decrypts and decodes wraps addressed to me', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = RideDmChannel(pool);

    final payload = RideOfferPayload(
      rideRequestId: 'req1',
      priceMnt: 5000,
      etaMinutes: 4,
      vehicleDescription: 'Prius',
    );
    final wrap = await channel.send(
      senderPrivHex: alice.privateHex,
      recipientPubHex: bob.publicHex,
      payload: payload,
      now: 1700000000,
    );

    final got = <InboundRideDm>[];
    final sub = channel
        .inbox(bob.publicHex, bob.privateHex, now: () => 1800000000)
        .listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, wrap.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, alice.publicHex);
    expect(got.first.payload, isA<RideOfferPayload>());
    expect((got.first.payload as RideOfferPayload).priceMnt, 5000);
    await sub.cancel();
  });

  test('inbox stamps wrapCreatedAt from the wrap itself and receivedAt from '
      'the injected clock, which are distinct by NIP-59 design', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = RideDmChannel(pool);

    const payload = RideCancelPayload(rideRequestId: 'req1', reason: 'test');
    final wrap = await channel.send(
      senderPrivHex: alice.privateHex,
      recipientPubHex: bob.publicHex,
      payload: payload,
      now: 1700000000,
    );

    // Deliberately far from `wrap.createdAt` (which is randomized to
    // within a couple of days of 1700000000) so the test would fail if
    // `receivedAt` were ever accidentally wired back to `wrap.createdAt`.
    const fakeClockValue = 1800000000;
    final got = <InboundRideDm>[];
    final sub = channel
        .inbox(bob.publicHex, bob.privateHex, now: () => fakeClockValue)
        .listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, wrap.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.wrapCreatedAt, wrap.createdAt);
    expect(got.first.receivedAt, fakeClockValue);
    expect(got.first.receivedAt, isNot(got.first.wrapCreatedAt));
    await sub.cancel();
  });

  test('inbox defaults to the real system clock for receivedAt when no '
      'clock is injected', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = RideDmChannel(pool);

    const payload = RideCancelPayload(rideRequestId: 'req1', reason: 'test');
    final wrap = await channel.send(
      senderPrivHex: alice.privateHex,
      recipientPubHex: bob.publicHex,
      payload: payload,
      now: 1700000000,
    );

    final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final got = <InboundRideDm>[];
    final sub = channel.inbox(bob.publicHex, bob.privateHex).listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, wrap.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    expect(got.length, 1);
    expect(got.first.receivedAt, greaterThanOrEqualTo(before));
    expect(got.first.receivedAt, lessThanOrEqualTo(after));
    await sub.cancel();
  });

  test('inbox silently drops wraps addressed to someone else, even if a '
      'misbehaving relay forwards them anyway', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = RideDmChannel(pool);
    final eve = generateKeyPair(List<int>.filled(32, 53));

    const payload = RideCancelPayload(rideRequestId: 'req1');
    final wrapForEve = await channel.send(
      senderPrivHex: alice.privateHex,
      recipientPubHex: eve.publicHex,
      payload: payload,
      now: 1700000000,
    );

    final got = <InboundRideDm>[];
    final sub = channel.inbox(bob.publicHex, bob.privateHex).listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, wrapForEve.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got, isEmpty);
    await sub.cancel();
  });
}

/// Finds the subscription id from the most recent `["REQ", subId, filter]`
/// frame sent on [socket]. `RideDmChannel.send` and `.inbox` share the same
/// underlying socket, so `sent` also carries earlier `["EVENT", ...]`
/// frames -- this looks the REQ frame up by shape rather than assuming
/// it's first, since `send()` is called (and its EVENT frame queued)
/// before `inbox()` opens the subscription in these tests.
String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}
