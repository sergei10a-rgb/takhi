// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('helper announcement has d/host/port/expiration tags', () {
    final e = buildHelperAnnouncement(
      pubkey: 'ab' * 32,
      now: 1000,
      helperId: 'ub-helper-1',
      host: 'turn.example.mn',
      port: 3478,
      credential: 'shared-secret',
    );
    expect(e.kind, kKindHelper);
    expect(e.tags.firstWhere((t) => t.first == 'd')[1], 'ub-helper-1');
    expect(e.tags.firstWhere((t) => t.first == 'host')[1], 'turn.example.mn');
    expect(e.tags.firstWhere((t) => t.first == 'port')[1], '3478');
    expect(e.tags.firstWhere((t) => t.first == 'expiration')[1], '4600');
    expect(e.content, 'shared-secret');
  });

  test('helper announcement round-trips through parse', () {
    final e = buildHelperAnnouncement(
      pubkey: 'cd' * 32,
      now: 2000,
      helperId: 'helper-2',
      host: '203.0.113.5',
      port: 3479,
    );
    final p = parseHelperAnnouncement(e);
    expect(p.helperId, 'helper-2');
    expect(p.host, '203.0.113.5');
    expect(p.port, 3479);
    expect(p.credential, '');
    expect(p.announcerPubkey, 'cd' * 32);
    expect(p.expiration, 5600);
    expect(p.createdAt, 2000);
  });

  test('parseHelperAnnouncement rejects the wrong kind', () {
    final wrong = NostrEvent(
        pubkey: 'ab' * 32, createdAt: 1, kind: 1, tags: const [], content: '');
    expect(() => parseHelperAnnouncement(wrong), throwsFormatException);
  });

  test('parseHelperAnnouncement rejects an event missing a required tag',
      () {
    final missingPort = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1000,
      kind: kKindHelper,
      tags: const [
        ['d', 'helper-1'],
        ['host', 'turn.example.mn'],
        ['expiration', '4600'],
      ],
      content: '',
    );
    expect(() => parseHelperAnnouncement(missingPort), throwsFormatException);
  });
}
