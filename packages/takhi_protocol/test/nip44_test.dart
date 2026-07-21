// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

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

  // `_calcPaddedLen` buckets 1..32 unpadded bytes into a fixed 32-byte
  // bucket; every payload test above uses `kVecPlaintext` ('a', 1 byte),
  // so the >32-byte doubling-chunk branch was previously untested. These
  // two vectors (43 bytes -> 64-byte bucket, 224 bytes -> 224-byte bucket)
  // are official NIP-44 v2 test vectors, so a byte-for-byte payload match
  // is a direct interop guarantee, not just an internal round-trip.
  test(
      'encrypt with fixed nonce matches official payload '
      '(43-byte multi-script plaintext, >32-byte padding bucket)', () {
    final out = nip44Encrypt(kVecPlaintext2, kVecPrivA2, kVecPubB2,
        nonce32: hex.decode(kVecNonce2));
    expect(out, kVecPayload2);
  });

  test(
      'decrypt of the 43-byte official vector recovers the exact '
      'plaintext', () {
    final pt = nip44Decrypt(kVecPayload2, kVecPrivA2, kVecPubB2);
    expect(pt, kVecPlaintext2);
  });

  test(
      'conversation key for the 43-byte vector matches the official '
      'vector', () {
    final ck = nip44ConversationKey(kVecPrivA2, kVecPubB2);
    expect(hex.encode(ck), kVecConversationKey2);
  });

  test(
      'encrypt with fixed nonce matches official payload '
      '(224-byte Arabic plaintext, larger padding bucket)', () {
    final out = nip44Encrypt(kVecPlaintext6, kVecPrivA6, kVecPubB6,
        nonce32: hex.decode(kVecNonce6));
    expect(out, kVecPayload6);
  });

  test(
      'decrypt of the 224-byte official vector recovers the exact '
      'plaintext', () {
    final pt = nip44Decrypt(kVecPayload6, kVecPrivA6, kVecPubB6);
    expect(pt, kVecPlaintext6);
  });

  test(
      'conversation key for the 224-byte vector matches the official '
      'vector', () {
    final ck = nip44ConversationKey(kVecPrivA6, kVecPubB6);
    expect(hex.encode(ck), kVecConversationKey6);
  });

  test(
      'round-trips a >=100-byte Mongolian plaintext (own-generated nonce, '
      'not a fixed vector)', () {
    const longMn = 'Энэ бол Тахь протоколын NIP-44 шифрлэлтийн урт мессежийн '
        'туршилт бөгөөд зуун байтаас илүү урттай Монгол хэлний текст '
        'байх ёстой гэж найдаж байна.';
    expect(utf8.encode(longMn).length, greaterThanOrEqualTo(100));
    final a = generateKeyPair(List<int>.filled(32, 33));
    final b = generateKeyPair(List<int>.filled(32, 44));
    final ct = nip44Encrypt(longMn, a.privateHex, b.publicHex);
    final pt = nip44Decrypt(ct, b.privateHex, a.publicHex);
    expect(pt, longMn);
  });

  test('tampered mac is rejected', () {
    final a = generateKeyPair(List<int>.filled(32, 1));
    final b = generateKeyPair(List<int>.filled(32, 2));
    final ct = nip44Encrypt('x', a.privateHex, b.publicHex);
    final bad = '${ct.substring(0, ct.length - 2)}AA';
    expect(() => nip44Decrypt(bad, b.privateHex, a.publicHex),
        throwsA(isA<Exception>()));
  });

  test('encrypt rejects a nonce32 that is not exactly 32 bytes', () {
    final a = generateKeyPair(List<int>.filled(32, 1));
    final b = generateKeyPair(List<int>.filled(32, 2));
    expect(
        () => nip44Encrypt('x', a.privateHex, b.publicHex,
            nonce32: List<int>.filled(10, 0)),
        throwsA(isA<ArgumentError>()));
  });

  test('decrypt rejects a payload that is not valid base64', () {
    final b = generateKeyPair(List<int>.filled(32, 2));
    expect(() => nip44Decrypt('***not-base64***', b.privateHex, kVecPubB),
        throwsA(isA<Exception>()));
  });

  test('decrypt rejects a payload with a non-0x02 version byte', () {
    final b = generateKeyPair(List<int>.filled(32, 2));
    final payload = base64.encode(Uint8List(65)..[0] = 0x01);
    expect(() => nip44Decrypt(payload, b.privateHex, kVecPubB),
        throwsA(isA<Exception>()));
  });

  test('decrypt rejects a payload shorter than version+nonce+mac', () {
    final b = generateKeyPair(List<int>.filled(32, 2));
    final payload = base64.encode(Uint8List(4)..[0] = 0x02);
    expect(() => nip44Decrypt(payload, b.privateHex, kVecPubB),
        throwsA(isA<Exception>()));
  });

  test(
      'conversation key rejects a malformed public key as Exception, '
      'not ArgumentError', () {
    try {
      nip44ConversationKey(kVecPrivA, 'not-a-valid-pubkey');
      fail('expected an exception to be thrown');
    } catch (e) {
      expect(e, isA<Exception>());
      expect(e, isNot(isA<Error>()));
    }
  });

  test(
      'conversation key rejects a public key with an off-curve '
      'x-coordinate as Exception, not ArgumentError', () {
    try {
      nip44ConversationKey(kVecPrivA, 'f' * 64);
      fail('expected an exception to be thrown');
    } catch (e) {
      expect(e, isA<Exception>());
      expect(e, isNot(isA<Error>()));
    }
  });

  test(
      'conversation key rejects a shared point at infinity (private key '
      'of zero) as Exception, not ArgumentError', () {
    try {
      nip44ConversationKey('0' * 64, kVecPubB);
      fail('expected an exception to be thrown');
    } catch (e) {
      expect(e, isA<Exception>());
      expect(e, isNot(isA<Error>()));
    }
  });
}
