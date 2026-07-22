// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';

class _FakeRelaySocket implements RelaySocket {
  final _c = StreamController<String>.broadcast();
  final sent = <String>[];
  @override
  Stream<String> get messages => _c.stream;
  @override
  void send(String d) => sent.add(d);
  @override
  Future<void> close() async => _c.close();
  @override
  Future<void> get ready => Future<void>.value();
}

void main() {
  test('defaultRelayUrls ships at least 3 well-known public relays', () {
    expect(defaultRelayUrls.length, greaterThanOrEqualTo(3));
    for (final url in defaultRelayUrls) {
      expect(url, startsWith('wss://'));
    }
    expect(
      defaultRelayUrls.toSet().length,
      defaultRelayUrls.length,
    ); // no dupes
  });

  test('relayPoolProvider builds a RelayPool over defaultRelayUrls', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final pool = container.read(relayPoolProvider);
    expect(pool.urls, defaultRelayUrls);
    expect(pool.connectedUrls, isEmpty); // not connected until connectAll()
  });

  test('relayConnectionProvider connects the pool to every relay without '
      'touching the network, using a fake-socket-backed override', () async {
    final sockets = <String, _FakeRelaySocket>{};
    final fakePool = RelayPool(
      defaultRelayUrls,
      connect: (u) => sockets[u] = _FakeRelaySocket(),
    );
    final container = ProviderContainer(
      overrides: [relayPoolProvider.overrideWithValue(fakePool)],
    );
    addTearDown(container.dispose);

    final pool = await container.read(relayConnectionProvider.future);

    expect(identical(pool, fakePool), isTrue);
    expect(pool.connectedUrls, defaultRelayUrls.toSet());
    expect(pool.connectedUrls.length, greaterThanOrEqualTo(3));
  });
}
