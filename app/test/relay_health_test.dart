// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

/// A relay that connects, and whose connection can be dropped from the test
/// the way a real one drops when the phone loses its network.
class _FakeRelaySocket implements RelaySocket {
  final _messages = StreamController<String>.broadcast();
  final _done = Completer<void>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_done.isCompleted) _done.complete();
    await _messages.close();
  }

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Future<void> get done => _done.future;

  /// The connection dying under the app -- what a real socket reports
  /// through `WebSocketChannel.sink.done` when the network goes away.
  void dropFromTheOtherEnd() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// A relay whose [ready] never succeeds: DNS failure, connection refused,
/// TLS failure -- everything that makes a configured relay unreachable.
class _UnreachableRelaySocket implements RelaySocket {
  final _messages = StreamController<String>.broadcast();
  bool closed = false;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void send(String data) {}

  @override
  Future<void> close() async {
    closed = true;
    await _messages.close();
  }

  @override
  Future<void> get ready => Future<void>.error(Exception('unreachable'));

  @override
  Future<void> get done => Completer<void>().future;
}

NostrEvent _event() {
  final kp = generateKeyPair(List<int>.filled(32, 7));
  return signEvent(
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
}

const _urls = ['wss://a', 'wss://b'];

void main() {
  group('publish tells the caller how far it got', () {
    test('returns the number of relays the event was handed to', () async {
      final pool = RelayPool(_urls, connect: (u) => _FakeRelaySocket());
      await pool.connectAll();

      expect(await pool.publish(_event()), 2);
    });

    test('returns 0 -- never a silent success -- when no relay is '
        'connected, which is the whole failure this reports on', () async {
      final pool = RelayPool(_urls, connect: (u) => _UnreachableRelaySocket());
      await pool.connectAll();

      expect(pool.connectedUrls, isEmpty);
      expect(await pool.publish(_event()), 0);
    });

    test('publishing with nothing connected still does not throw, so no '
        'existing caller (trip pings, receipts, DMs) breaks', () async {
      final pool = RelayPool(_urls, connect: (u) => _UnreachableRelaySocket());
      await pool.connectAll();

      await expectLater(pool.publish(_event()), completion(0));
    });
  });

  group('health is readable without guessing', () {
    test('isOffline is true only when not one relay holds a socket', () async {
      var first = true;
      final pool = RelayPool(
        _urls,
        connect: (u) {
          // One reachable relay, one not.
          if (first) {
            first = false;
            return _FakeRelaySocket();
          }
          return _UnreachableRelaySocket();
        },
      );

      expect(pool.isOffline, isTrue); // before connectAll
      await pool.connectAll();

      expect(pool.isOffline, isFalse);
      expect(pool.connectedUrls, {'wss://a'});
      expect(pool.unreachableUrls, {'wss://b'});
    });

    test('status names every configured relay, connected or not', () async {
      final pool = RelayPool(_urls, connect: (u) => _UnreachableRelaySocket());
      await pool.connectAll();

      final status = pool.status;
      expect(status.urls, _urls);
      expect(status.total, 2);
      expect(status.connectedCount, 0);
      expect(status.isOffline, isTrue);
      expect(status.unreachableUrls, _urls.toSet());
    });
  });

  group('a dropped connection stops counting as connected', () {
    test('a socket that dies under the app leaves connectedUrls', () async {
      final sockets = <String, _FakeRelaySocket>{};
      final pool = RelayPool(
        _urls,
        connect: (u) => sockets[u] = _FakeRelaySocket(),
      );
      await pool.connectAll();
      expect(pool.connectedUrls, _urls.toSet());

      sockets['wss://a']!.dropFromTheOtherEnd();
      await pumpEventQueue();

      expect(pool.connectedUrls, {'wss://b'});
      expect(pool.isOffline, isFalse);

      sockets['wss://b']!.dropFromTheOtherEnd();
      await pumpEventQueue();

      // The exact state the app used to render as "Холбогдлоо (0)".
      expect(pool.isOffline, isTrue);
      expect(await pool.publish(_event()), 0);
    });

    test('watchStatus emits the current status immediately and again on '
        'every connect and drop', () async {
      final sockets = <String, _FakeRelaySocket>{};
      final pool = RelayPool(
        _urls,
        connect: (u) => sockets[u] = _FakeRelaySocket(),
      );

      final seen = <int>[];
      final sub = pool.watchStatus().listen((s) => seen.add(s.connectedCount));
      await pumpEventQueue();
      expect(seen, [0]);

      await pool.connectAll();
      await pumpEventQueue();
      expect(seen.last, 2);

      sockets['wss://a']!.dropFromTheOtherEnd();
      await pumpEventQueue();
      expect(seen.last, 1);

      await sub.cancel();
    });

    test('a connect that resolves in the same turn as the subscribe is not '
        'lost -- the listener must not be left holding the pre-connect '
        'reading forever', () async {
      final pool = RelayPool(_urls, connect: (u) => _FakeRelaySocket());

      final seen = <int>[];
      // No pump between these two: a fast connection really does resolve
      // inside this window, and an `async*` generator would not have
      // subscribed to the pool's announcements yet.
      final sub = pool.watchStatus().listen((s) => seen.add(s.connectedCount));
      await pool.connectAll();
      await pumpEventQueue();

      expect(seen.last, 2);
      await sub.cancel();
    });
  });

  group('reconnecting is safe to call again', () {
    test('a second connectAll retries only the relays that are down, and '
        'does not replace -- or leak -- a socket that is still up', () async {
      final built = <String, List<RelaySocket>>{};
      var reachable = false;
      final pool = RelayPool(
        _urls,
        connect: (u) {
          // 'wss://a' is always fine; 'wss://b' only comes up on the retry.
          final socket = (u == 'wss://a' || reachable)
              ? _FakeRelaySocket()
              : _UnreachableRelaySocket();
          (built[u] ??= []).add(socket);
          return socket;
        },
      );

      await pool.connectAll();
      expect(pool.connectedUrls, {'wss://a'});
      final firstA = built['wss://a']!.single;

      reachable = true;
      await pool.connectAll();

      expect(pool.connectedUrls, _urls.toSet());
      // The relay that was already up was never dialled a second time --
      // the old socket would otherwise be overwritten in the map and left
      // open forever, taking every live subscription on it with it.
      expect(built['wss://a']!.length, 1);
      expect(identical(built['wss://a']!.single, firstA), isTrue);
      expect((firstA as _FakeRelaySocket).closed, isFalse);
      expect(built['wss://b']!.length, 2);
    });

    test(
      'a relay that dropped is dialled again by the next connectAll',
      () async {
        final sockets = <String, List<_FakeRelaySocket>>{};
        final pool = RelayPool(
          _urls,
          connect: (u) {
            final socket = _FakeRelaySocket();
            (sockets[u] ??= []).add(socket);
            return socket;
          },
        );
        await pool.connectAll();

        sockets['wss://a']!.single.dropFromTheOtherEnd();
        await pumpEventQueue();
        expect(pool.connectedUrls, {'wss://b'});

        await pool.connectAll();

        expect(pool.connectedUrls, _urls.toSet());
        expect(sockets['wss://a']!.length, 2);
        expect(sockets['wss://b']!.length, 1);
      },
    );
  });
}
