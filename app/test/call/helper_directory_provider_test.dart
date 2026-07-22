// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_providers.dart';
import 'package:takhi/call/ice_servers.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

/// Regression coverage for Plan 5's review CRITICAL-1: before this fix,
/// nothing in production ever subscribed `HelperDirectoryService
/// .watchHelpers()`, so `helperDirectoryServiceProvider`/`HelperDirectory`
/// never received a single real kind-30178 announcement and the
/// community-TURN fallback (spec §7.3-①) was permanently dead outside
/// tests. This file proves `helperDirectoryProvider` -- the provider added
/// to close that gap -- actually subscribes over the (fake) relay socket
/// and folds a real announcement into its live accumulator.
String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}

void main() {
  test('reading helperDirectoryProvider subscribes over the relay pool, and '
      'an incoming kind-30178 announcement lands in current()', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();

    final container = ProviderContainer(
      overrides: [relayPoolProvider.overrideWithValue(pool)],
    );
    addTearDown(container.dispose);

    // Reading the provider is what starts the subscription -- exactly
    // what `CallScreen`/`ActiveTripView` do via `ref.read`.
    final dir = container.read(helperDirectoryProvider);
    expect(dir.current(), isEmpty);

    final subId = _reqSubId(sockets['wss://a']!);
    // Both `HelperDirectoryService.watchHelpers` and `HelperDirectory
    // .current()` default their own `now` parameter to the real system
    // clock -- so, unlike `helper_directory_service_test.dart` (which
    // injects a fixed `now` into both), this announcement's `now`/
    // `expirySeconds` must be realistic (i.e. "not already expired
    // relative to the real clock") or `watchHelpers` itself silently
    // drops it before it ever reaches [dir].
    final realNowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final event = buildHelperAnnouncement(
      pubkey: 'ab' * 32,
      now: realNowSeconds,
      helperId: 'h1',
      host: 'turn.example.mn',
      port: 3478,
      credential: 'secret',
    );
    final keys = generateKeyPair(List<int>.filled(32, 9));
    final signed = signEvent(
      event.copyWith(id: computeEventId(event)),
      keys.privateHex,
    );
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, signed.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Reading the provider again returns the SAME accumulator instance
    // (a plain, non-autoDispose `Provider`) -- its `.current()` reflects
    // the announcement that arrived after the first read, with no need
    // to re-read/re-subscribe.
    expect(identical(container.read(helperDirectoryProvider), dir), isTrue);
    final current = dir.current();
    expect(current, hasLength(1));
    expect(current.first.helperId, 'h1');

    // The whole point: that live snapshot, handed to `buildIceServers`
    // (exactly as `CallScreen._startCall` does), actually produces a
    // `turn:` ICE server entry -- proving the fallback chain's helper
    // rung is reachable end to end, not just accumulated and discarded.
    final iceServers = buildIceServers(helpers: current);
    expect(iceServers.length, 2);
    expect(iceServers[1]['urls'], ['turn:turn.example.mn:3478']);
    expect(iceServers[1]['credential'], 'secret');
  });
}
