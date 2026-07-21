// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';
import 'package:convert/convert.dart';

import 'nip44_vectors.dart';

void main() {
  test('conversation key matches official vector', () {
    final ck = nip44ConversationKey(kVecPrivA, kVecPubB);
    expect(hex.encode(ck), kVecConversationKey);
  });

  test('encrypt with fixed nonce matches official payload', () {
    final out = nip44Encrypt(kVecPlaintext, kVecPrivA, kVecPubB,
        nonce32: hex.decode(kVecNonce));
    expect(out, kVecPayload);
  });

  test('round-trip encrypt/decrypt between two parties', () {
    final a = generateKeyPair(List<int>.filled(32, 11));
    final b = generateKeyPair(List<int>.filled(32, 22));
    final ct = nip44Encrypt('Сайн байна уу', a.privateHex, b.publicHex);
    final pt = nip44Decrypt(ct, b.privateHex, a.publicHex);
    expect(pt, 'Сайн байна уу');
  });

  test('tampered mac is rejected', () {
    final a = generateKeyPair(List<int>.filled(32, 1));
    final b = generateKeyPair(List<int>.filled(32, 2));
    final ct = nip44Encrypt('x', a.privateHex, b.publicHex);
    final bad = ct.substring(0, ct.length - 2) + 'AA';
    expect(() => nip44Decrypt(bad, b.privateHex, a.publicHex),
        throwsA(isA<Exception>()));
  });
}
