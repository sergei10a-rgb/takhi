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
}
