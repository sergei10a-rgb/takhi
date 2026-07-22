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

  test(
      'signEvent without auxRand uses secure randomness, not an all-zero '
      'default', () {
    final unsigned = NostrEvent(
        pubkey: kp.publicHex, createdAt: 200, kind: 1, tags: [], content: 'hi');
    final signedA = signEvent(unsigned, kp.privateHex);
    final signedB = signEvent(unsigned, kp.privateHex);
    expect(verifyEvent(signedA), isTrue);
    expect(verifyEvent(signedB), isTrue);
    // Same message + key, but BIP-340 aux randomness must differ per call,
    // so the two Schnorr signatures must not collide.
    expect(signedA.sig, isNot(equals(signedB.sig)));
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
