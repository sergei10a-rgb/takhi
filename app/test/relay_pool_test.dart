// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

class FakeRelaySocket implements RelaySocket {
  final _c = StreamController<String>.broadcast();
  final sent = <String>[];
  bool closed = false;
  @override
  Stream<String> get messages => _c.stream;
  @override
  void send(String d) => sent.add(d);
  @override
  Future<void> close() async {
    closed = true;
    await _c.close();
  }

  @override
  Future<void> get ready => Future<void>.value();
  @override
  Future<void> get done => Completer<void>().future;
  void emit(String s) => _c.add(s);
}

/// A [RelaySocket] whose [ready] future fails, as a real [WsRelaySocket]'s
/// would for a DNS failure / connection refused / TLS failure — the socket
/// is constructed synchronously without error, but never actually connects.
class FailingReadyRelaySocket implements RelaySocket {
  final _c = StreamController<String>.broadcast();
  final sent = <String>[];
  bool closed = false;
  @override
  Stream<String> get messages => _c.stream;
  @override
  void send(String d) => sent.add(d);
  @override
  Future<void> close() async {
    closed = true;
    await _c.close();
  }

  @override
  Future<void> get ready => Future<void>.error(Exception('unreachable'));
  @override
  Future<void> get done => Completer<void>().future;
}

/// Extracts the subId (second element) from a `["REQ", subId, filter]`
/// frame previously sent on [socket].
String subIdOf(FakeRelaySocket socket) {
  final frame = jsonDecode(socket.sent.first) as List<dynamic>;
  return frame[1] as String;
}

NostrEvent _signedEvent({required int seed, required int kind}) {
  final kp = generateKeyPair(List<int>.filled(32, seed));
  return signEvent(
    NostrEvent(
      pubkey: kp.publicHex,
      createdAt: 1,
      kind: kind,
      tags: [],
      content: 'seed-$seed-kind-$kind',
    ),
    kp.privateHex,
    auxRand: List<int>.filled(32, 0),
  );
}

void main() {
  test('publish sends EVENT frame to all relays', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
      'wss://b',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final kp = generateKeyPair(List<int>.filled(32, 9));
    final e = signEvent(
      NostrEvent(
        pubkey: kp.publicHex,
        createdAt: 1,
        kind: 1,
        tags: [],
        content: 'hi',
      ),
      kp.privateHex,
      auxRand: List<int>.filled(32, 0),
    );
    await pool.publish(e);
    expect(sockets['wss://a']!.sent.first.contains('"EVENT"'), isTrue);
    expect(sockets['wss://b']!.sent.length, 1);
  });

  test('subscribe yields verified events, deduped across relays', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
      'wss://b',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final e = _signedEvent(seed: 5, kind: 1);
    final got = <NostrEvent>[];
    final sub = pool.subscribe(RelayFilter(kinds: [1])).listen(got.add);
    // Use the sub id the pool actually generated and sent in its REQ frame,
    // not a hardcoded literal — the pool checks this id when routing
    // incoming EVENT frames back to the subscription that requested them.
    final subId = subIdOf(sockets['wss://a']!);
    final frame = jsonEncode(['EVENT', subId, e.toJson()]);
    sockets['wss://a']!.emit(frame);
    sockets['wss://b']!.emit(frame); // same event from 2nd relay
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(got.length, 1); // deduped
    expect(got.first.content, 'seed-5-kind-1');
    await sub.cancel();
  });

  test('routes EVENT frames to the subscription whose subId they carry, not '
      'whichever subscription listened first on the shared socket', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final socket = sockets['wss://a']!;

    final gotKind0 = <NostrEvent>[];
    final gotKind1 = <NostrEvent>[];
    final subKind0 = pool
        .subscribe(RelayFilter(kinds: [0]))
        .listen(gotKind0.add);
    final subKind1 = pool
        .subscribe(RelayFilter(kinds: [1]))
        .listen(gotKind1.add);

    expect(socket.sent.length, 2);
    final subId0 = (jsonDecode(socket.sent[0]) as List<dynamic>)[1] as String;
    final subId1 = (jsonDecode(socket.sent[1]) as List<dynamic>)[1] as String;
    expect(subId0, isNot(subId1));

    // A kind:1 event tagged with the *second* subscription's subId must
    // land only in that subscription's stream.
    final kind1Event = _signedEvent(seed: 11, kind: 1);
    socket.emit(jsonEncode(['EVENT', subId1, kind1Event.toJson()]));

    // A kind:0 event tagged with the *first* subscription's subId must
    // land only in that subscription's stream.
    final kind0Event = _signedEvent(seed: 12, kind: 0);
    socket.emit(jsonEncode(['EVENT', subId0, kind0Event.toJson()]));

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(gotKind0.length, 1);
    expect(gotKind0.first.content, 'seed-12-kind-0');
    expect(gotKind1.length, 1);
    expect(gotKind1.first.content, 'seed-11-kind-1');

    await subKind0.cancel();
    await subKind1.cancel();
  });

  test('ignores EVENT frames tagged with an unknown/foreign subId', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final socket = sockets['wss://a']!;
    final got = <NostrEvent>[];
    final sub = pool.subscribe(RelayFilter(kinds: [1])).listen(got.add);
    final e = _signedEvent(seed: 21, kind: 1);
    socket.emit(jsonEncode(['EVENT', 'not-our-subid', e.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(got, isEmpty);
    await sub.cancel();
  });

  test('ignores malformed and structurally-wrong frames', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final socket = sockets['wss://a']!;
    final got = <NostrEvent>[];
    final sub = pool.subscribe(RelayFilter(kinds: [1])).listen(got.add);
    final subId = subIdOf(socket);

    socket.emit('not json at all {{{'); // FormatException branch
    socket.emit(jsonEncode(['NOTICE', 'hello'])); // not an EVENT frame
    socket.emit(jsonEncode(['EVENT', subId])); // too short
    socket.emit(jsonEncode(['EVENT', subId, 'not-a-map'])); // TypeError branch

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(got, isEmpty);
    await sub.cancel();
  });

  test('connectAll skips a relay whose connection never becomes ready and '
      'keeps the rest connected', () async {
    final sockets = <String, RelaySocket>{};
    final pool = RelayPool(
      ['wss://good', 'wss://bad'],
      connect: (u) => sockets[u] = u.contains('bad')
          ? FailingReadyRelaySocket()
          : FakeRelaySocket(),
    );

    await pool.connectAll();

    expect(pool.connectedUrls, {'wss://good'});
    final badSocket = sockets['wss://bad']! as FailingReadyRelaySocket;
    expect(badSocket.closed, isTrue);

    // The unreachable relay must never receive traffic.
    final e = _signedEvent(seed: 31, kind: 1);
    await pool.publish(e);
    expect(badSocket.sent, isEmpty);
    expect((sockets['wss://good']! as FakeRelaySocket).sent, isNotEmpty);
  });

  test('seenEventIdsCap rejects a non-positive cap', () {
    expect(
      () => RelayPool(['wss://a'], seenEventIdsCap: 0),
      throwsArgumentError,
    );
    expect(
      () => RelayPool(['wss://a'], seenEventIdsCap: -1),
      throwsArgumentError,
    );
  });

  test('caps the dedup set: once seenEventIdsCap distinct ids have been seen, '
      'the oldest is evicted (FIFO), so re-emitting it is treated as new '
      'again instead of leaking memory forever', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(
      ['wss://a'],
      connect: (u) => sockets[u] = FakeRelaySocket(),
      seenEventIdsCap: 3,
    );
    await pool.connectAll();
    final socket = sockets['wss://a']!;
    final got = <NostrEvent>[];
    final sub = pool.subscribe(RelayFilter(kinds: [1])).listen(got.add);
    final subId = subIdOf(socket);

    // Four distinct events against a cap of 3: the 4th eviction pushes
    // the very first event's id out of the dedup set.
    final events = List.generate(4, (i) => _signedEvent(seed: 40 + i, kind: 1));
    for (final e in events) {
      socket.emit(jsonEncode(['EVENT', subId, e.toJson()]));
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(got.length, 4);

    // Re-emitting the (now-evicted) first event: an unbounded set would
    // dedupe and drop it; the capped set no longer remembers it, so it
    // is delivered again.
    socket.emit(jsonEncode(['EVENT', subId, events[0].toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(got.length, 5);
    expect(got.last.content, events[0].content);

    await sub.cancel();
  });

  test(
    'dispose closes every connected socket and clears connectedUrls',
    () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
        'wss://b',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      expect(pool.connectedUrls, {'wss://a', 'wss://b'});

      pool.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(pool.connectedUrls, isEmpty);
      expect(sockets['wss://a']!.closed, isTrue);
      expect(sockets['wss://b']!.closed, isTrue);
    },
  );

  // Two features can legitimately want the same event. The driver inbox
  // watches gift wraps for handoffs and, since spec §7.5, for
  // cancellations -- two `REQ`s, one filter, and a relay answers each
  // separately. A pool-wide dedup set turned that into a silent kill
  // switch: the first subscription banked the id and every later
  // subscription's copy was dropped, so the second stream received nothing
  // for the app's whole lifetime. Nothing failed, nothing logged; the
  // feature was simply off.
  test('two subscriptions matching the same event each receive it -- dedup '
      'is per subscription, not shared across the pool', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final socket = sockets['wss://a']!;

    final first = <NostrEvent>[];
    final second = <NostrEvent>[];
    final subA = pool.subscribe(RelayFilter(kinds: [1])).listen(first.add);
    final subIdA = subIdOf(socket);
    final subB = pool.subscribe(RelayFilter(kinds: [1])).listen(second.add);
    final subIdB = (jsonDecode(socket.sent.last) as List<dynamic>)[1] as String;
    expect(subIdA, isNot(subIdB));

    // What a relay actually does with two open REQs: one frame per
    // subscription, same event id in both.
    final e = _signedEvent(seed: 77, kind: 1);
    socket.emit(jsonEncode(['EVENT', subIdA, e.toJson()]));
    socket.emit(jsonEncode(['EVENT', subIdB, e.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(first.map((e) => e.id), [e.id]);
    expect(
      second.map((e) => e.id),
      [e.id],
      reason:
          'the second subscription was starved by the first -- any feature '
          'built on it would be dead on arrival',
    );

    // And the guarantee that made the shared set look right in the first
    // place still holds *within* a subscription: the same relay (or four
    // relays carrying the same event) cannot deliver it twice.
    socket.emit(jsonEncode(['EVENT', subIdA, e.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(first.length, 1);

    await subA.cancel();
    await subB.cancel();
  });
}
