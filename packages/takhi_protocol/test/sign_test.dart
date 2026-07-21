// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  final kp = generateKeyPair(List<int>.filled(32, 3));

  test('signed event verifies', () {
    final unsigned = NostrEvent(
        pubkey: kp.publicHex, createdAt: 100, kind: 1, tags: [], content: 'hi');
    final signed =
        signEvent(unsigned, kp.privateHex, auxRand: List<int>.filled(32, 0));
    expect(signed.id, isNotNull);
    expect(signed.sig, isNotNull);
    expect(verifyEvent(signed), isTrue);
  });

  test('tampered content fails verification', () {
    final signed = signEvent(
        NostrEvent(
            pubkey: kp.publicHex,
            createdAt: 1,
            kind: 1,
            tags: [],
            content: 'a'),
        kp.privateHex,
        auxRand: List<int>.filled(32, 0));
    final tampered = NostrEvent(
        id: signed.id,
        pubkey: signed.pubkey,
        createdAt: signed.createdAt,
        kind: signed.kind,
        tags: signed.tags,
        content: 'b',
        sig: signed.sig);
    expect(verifyEvent(tampered), isFalse);
  });
}
