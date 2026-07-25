// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/ice_servers.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('buildIceServers with no helpers returns only the STUN entry', () {
    final servers = buildIceServers();
    expect(servers.length, 1);
    expect(servers.first['urls'], kDefaultStunServers);
  });

  test('buildIceServers appends one turn: entry per helper', () {
    final helper = HelperAnnouncement(
      helperId: 'h1',
      host: 'turn.example.mn',
      port: 3478,
      credential: 'secret',
      announcerPubkey: 'ab' * 32,
      expiration: 9999,
      createdAt: 1000,
    );
    final servers = buildIceServers(helpers: [helper]);
    expect(servers.length, 2);
    expect(servers[1]['urls'], ['turn:turn.example.mn:3478']);
    expect(servers[1]['credential'], 'secret');
    expect(servers[1]['username'], 'h1');
  });

  test('buildIceServers omits credential/username for an open helper', () {
    final helper = HelperAnnouncement(
      helperId: 'h2',
      host: '203.0.113.9',
      port: 3479,
      credential: '',
      announcerPubkey: 'cd' * 32,
      expiration: 9999,
      createdAt: 1000,
    );
    final servers = buildIceServers(helpers: [helper]);
    expect(servers[1].containsKey('credential'), isFalse);
    expect(servers[1].containsKey('username'), isFalse);
  });

  test('buildIceServers drops a helper whose announced host is not a bare '
      'IP-or-domain, even though anyone can publish a kind-30178 '
      'announcement', () {
    final malicious = HelperAnnouncement(
      helperId: 'evil',
      host: 'turn.example.mn/;transport=tcp',
      port: 3478,
      credential: '',
      announcerPubkey: 'ef' * 32,
      expiration: 9999,
      createdAt: 1000,
    );
    final servers = buildIceServers(helpers: [malicious]);
    expect(servers.length, 1);
    expect(servers.first['urls'], kDefaultStunServers);
  });

  test('buildIceServers drops a helper with an empty announced host', () {
    final helper = HelperAnnouncement(
      helperId: 'blank',
      host: '',
      port: 3478,
      credential: '',
      announcerPubkey: 'ef' * 32,
      expiration: 9999,
      createdAt: 1000,
    );
    final servers = buildIceServers(helpers: [helper]);
    expect(servers.length, 1);
  });

  test('buildIceServers keeps valid helpers while dropping only the '
      'malformed one from the same list', () {
    final good = HelperAnnouncement(
      helperId: 'good',
      host: 'turn.example.mn',
      port: 3478,
      credential: '',
      announcerPubkey: 'ab' * 32,
      expiration: 9999,
      createdAt: 1000,
    );
    final bad = HelperAnnouncement(
      helperId: 'bad',
      host: 'evil host with spaces',
      port: 3478,
      credential: '',
      announcerPubkey: 'cd' * 32,
      expiration: 9999,
      createdAt: 1000,
    );
    final servers = buildIceServers(helpers: [good, bad]);
    expect(servers.length, 2);
    expect(servers[1]['urls'], ['turn:turn.example.mn:3478']);
  });

  group('isValidTurnHost', () {
    test('accepts a bare domain', () {
      expect(isValidTurnHost('turn.example.mn'), isTrue);
    });

    test('accepts a bare IPv4 address', () {
      expect(isValidTurnHost('203.0.113.9'), isTrue);
    });

    test('rejects an empty host', () {
      expect(isValidTurnHost(''), isFalse);
    });

    test('rejects a host carrying a path/query injection attempt', () {
      expect(isValidTurnHost('turn.example.mn/;transport=tcp'), isFalse);
    });

    test('rejects a host containing whitespace', () {
      expect(isValidTurnHost('turn example.mn'), isFalse);
    });

    test('rejects a host containing an embedded extra port', () {
      expect(isValidTurnHost('turn.example.mn:3478'), isFalse);
    });

    test('rejects a host carrying userinfo (credential injection)', () {
      expect(isValidTurnHost('user@turn.example.mn'), isFalse);
    });
  });
}
