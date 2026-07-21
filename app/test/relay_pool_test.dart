// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

class FakeRelaySocket implements RelaySocket {
  final _c = StreamController<String>.broadcast();
  final sent = <String>[];
  @override
  Stream<String> get messages => _c.stream;
  @override
  void send(String d) => sent.add(d);
  @override
  Future<void> close() async => _c.close();
  void emit(String s) => _c.add(s);
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
    final kp = generateKeyPair(List<int>.filled(32, 5));
    final e = signEvent(
      NostrEvent(
        pubkey: kp.publicHex,
        createdAt: 2,
        kind: 1,
        tags: [],
        content: 'x',
      ),
      kp.privateHex,
      auxRand: List<int>.filled(32, 0),
    );
    final got = <NostrEvent>[];
    final sub = pool.subscribe(RelayFilter(kinds: [1])).listen(got.add);
    final frame = jsonEncode(['EVENT', 'sub', e.toJson()]);
    sockets['wss://a']!.emit(frame);
    sockets['wss://b']!.emit(frame); // same event from 2nd relay
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(got.length, 1); // deduped
    expect(got.first.content, 'x');
    await sub.cancel();
  });
}
