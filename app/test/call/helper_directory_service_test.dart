// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/helper_directory_service.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  group('HelperDirectory (pure accumulator)', () {
    test('current() returns only non-expired helpers, keyed by helperId', () {
      final dir = HelperDirectory();
      dir.add(
        HelperAnnouncement(
          helperId: 'fresh',
          host: 'a',
          port: 1,
          credential: '',
          announcerPubkey: 'ab' * 32,
          expiration: 2000,
          createdAt: 1000,
        ),
      );
      dir.add(
        HelperAnnouncement(
          helperId: 'stale',
          host: 'b',
          port: 2,
          credential: '',
          announcerPubkey: 'cd' * 32,
          expiration: 500,
          createdAt: 100,
        ),
      );
      final current = dir.current(now: () => 1500);
      expect(current.length, 1);
      expect(current.first.helperId, 'fresh');
    });

    test('current() replaces an earlier announcement from the same '
        'helperId', () {
      final dir = HelperDirectory();
      dir.add(
        HelperAnnouncement(
          helperId: 'h1',
          host: 'old-host',
          port: 1,
          credential: '',
          announcerPubkey: 'ab' * 32,
          expiration: 9999,
          createdAt: 1000,
        ),
      );
      dir.add(
        HelperAnnouncement(
          helperId: 'h1',
          host: 'new-host',
          port: 2,
          credential: '',
          announcerPubkey: 'ab' * 32,
          expiration: 9999,
          createdAt: 2000,
        ),
      );
      final current = dir.current(now: () => 1500);
      expect(current.length, 1);
      expect(current.first.host, 'new-host');
    });
  });

  group('HelperDirectoryService (relay-backed)', () {
    test('watchHelpers yields a parsed announcement from the relay', () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = HelperDirectoryService(pool);

      final got = <HelperAnnouncement>[];
      final sub = service.watchHelpers(now: () => 1000).listen(got.add);
      final subId = _reqSubId(sockets['wss://a']!);

      final event = buildHelperAnnouncement(
        pubkey: 'ab' * 32,
        now: 1000,
        helperId: 'h1',
        host: 'turn.example.mn',
        port: 3478,
      );
      final keys = generateKeyPair(List<int>.filled(32, 9));
      final signed = signEvent(
        event.copyWith(id: computeEventId(event)),
        keys.privateHex,
      );
      sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, signed.toJson()]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(got.length, 1);
      expect(got.first.helperId, 'h1');
      await sub.cancel();
    });

    test(
      'watchHelpers silently drops a foreign-kind event, even if a '
      'misbehaving relay forwards it anyway despite our kind filter',
      () async {
        final sockets = <String, FakeRelaySocket>{};
        final pool = RelayPool([
          'wss://a',
        ], connect: (u) => sockets[u] = FakeRelaySocket());
        await pool.connectAll();
        final service = HelperDirectoryService(pool);

        final got = <HelperAnnouncement>[];
        final sub = service.watchHelpers(now: () => 1000).listen(got.add);
        final subId = _reqSubId(sockets['wss://a']!);

        // A misbehaving relay ignores our `kinds` filter and forwards a
        // foreign-kind event (a live-location ping, not a kind-30178
        // helper announcement) anyway.
        final keys = generateKeyPair(List<int>.filled(32, 9));
        final foreign = NostrEvent(
          pubkey: keys.publicHex,
          createdAt: 1000,
          kind: kKindLiveLocation,
          tags: const [],
          content: '',
        );
        final signedForeign = signEvent(
          foreign.copyWith(id: computeEventId(foreign)),
          keys.privateHex,
        );
        sockets['wss://a']!.emit(
          jsonEncode(['EVENT', subId, signedForeign.toJson()]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(got, isEmpty);
        await sub.cancel();
      },
    );

    test(
      'watchHelpers drops an announcement that is already expired by the '
      'time it arrives from the relay',
      () async {
        final sockets = <String, FakeRelaySocket>{};
        final pool = RelayPool([
          'wss://a',
        ], connect: (u) => sockets[u] = FakeRelaySocket());
        await pool.connectAll();
        final service = HelperDirectoryService(pool);

        final got = <HelperAnnouncement>[];
        final sub = service.watchHelpers(now: () => 1000).listen(got.add);
        final subId = _reqSubId(sockets['wss://a']!);

        // Published long enough ago that its own `expiration` tag has
        // already lapsed (NIP-40) by the time `now()` is checked.
        final expired = buildHelperAnnouncement(
          pubkey: 'ab' * 32,
          now: 100,
          helperId: 'expired-helper',
          host: 'turn.example.mn',
          port: 3478,
          expirySeconds: 200,
        );
        final keys = generateKeyPair(List<int>.filled(32, 9));
        final signedExpired = signEvent(
          expired.copyWith(id: computeEventId(expired)),
          keys.privateHex,
        );
        sockets['wss://a']!.emit(
          jsonEncode(['EVENT', subId, signedExpired.toJson()]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(got, isEmpty);
        await sub.cancel();
      },
    );
  });
}

String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}
