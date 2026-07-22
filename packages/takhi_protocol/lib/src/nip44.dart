// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';

/// NIP-44 v2 payload version byte.
const int _nip44Version = 0x02;

final ECDomainParameters _domain = ECDomainParameters('secp256k1');

/// Computes the secp256k1 ECDH shared X coordinate between [privHex] and
/// the x-only public key [pubHex] (even-Y convention per BIP-340/NIP-44).
///
/// Throws [Exception] (never [ArgumentError]) for any input-driven failure —
/// malformed hex, an x-coordinate not on the curve, or a shared point at
/// infinity — so callers (including [nip44Decrypt] via
/// [nip44ConversationKey]) see the same recoverable-failure type as every
/// other decrypt-side error path.
Uint8List _ecdhX(String privHex, String pubHex) {
  final d = BigInt.parse(privHex, radix: 16);
  ECPoint? pubPoint;
  try {
    pubPoint = _domain.curve
        .decodePoint(Uint8List.fromList([0x02, ...hex.decode(pubHex)]));
  } on FormatException {
    throw Exception('invalid public key: not valid hex');
  } on ArgumentError {
    throw Exception('invalid public key');
  }
  if (pubPoint == null) {
    throw Exception('invalid public key');
  }
  final shared = pubPoint * d;
  final x = shared?.x?.toBigInteger();
  if (x == null) {
    throw Exception('ECDH failed: shared point at infinity');
  }
  return _bigIntTo32(x);
}

Uint8List _bigIntTo32(BigInt v) {
  final b = v.toRadixString(16).padLeft(64, '0');
  return Uint8List.fromList(hex.decode(b));
}

/// HMAC-SHA256(key, data).
Uint8List _hmacSha256(List<int> key, List<int> data) {
  final hmac = HMac(SHA256Digest(), 64)
    ..init(KeyParameter(Uint8List.fromList(key)));
  return hmac.process(Uint8List.fromList(data));
}

/// Derives the NIP-44 v2 conversation key shared by [privHex] and
/// [pubHex]: `HKDF-extract(salt='nip44-v2', ikm=ecdh_x(priv, pub))`.
List<int> nip44ConversationKey(String privHex, String pubHex) {
  final ikm = _ecdhX(privHex, pubHex);
  return _hmacSha256(utf8.encode('nip44-v2'), ikm);
}

/// HKDF-expand(prk, info, length) built from HMAC-SHA256, per RFC 5869.
Uint8List _hkdfExpand(List<int> prk, List<int> info, int length) {
  final out = BytesBuilder();
  var t = <int>[];
  var counter = 1;
  while (out.length < length) {
    final input = <int>[...t, ...info, counter];
    t = _hmacSha256(prk, input);
    out.add(t);
    counter++;
  }
  return Uint8List.fromList(out.toBytes().sublist(0, length));
}

/// Message keys derived per-message from the conversation key and a
/// 32-byte nonce: `chacha_key(32) || chacha_nonce(12) || hmac_key(32)`.
class _MessageKeys {
  final Uint8List chachaKey;
  final Uint8List chachaNonce;
  final Uint8List hmacKey;
  _MessageKeys(this.chachaKey, this.chachaNonce, this.hmacKey);
}

_MessageKeys _messageKeys(List<int> conversationKey, List<int> nonce) {
  final expanded = _hkdfExpand(conversationKey, nonce, 76);
  return _MessageKeys(
    expanded.sublist(0, 32),
    expanded.sublist(32, 44),
    expanded.sublist(44, 76),
  );
}

/// NIP-44 padded-length bucketing: `calc_padded_len` from the spec.
/// Ported verbatim (chunk-doubling scheme) so the fixed-nonce vector
/// matches byte-for-byte.
int _calcPaddedLen(int unpaddedLen) {
  if (unpaddedLen <= 32) return 32;
  final nextPower = 1 << (_log2Floor(unpaddedLen - 1) + 1);
  final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
  return chunk * ((unpaddedLen - 1) ~/ chunk + 1);
}

int _log2Floor(int n) {
  var result = 0;
  var v = n;
  while (v > 1) {
    v >>= 1;
    result++;
  }
  return result;
}

/// Length-prefixed, zero-padded plaintext per NIP-44:
/// `u16be(len) || plaintext || zero-pad-to-bucket`.
Uint8List _pad(String plaintext) {
  final bytes = utf8.encode(plaintext);
  final len = bytes.length;
  if (len < 1 || len > 65535) {
    throw ArgumentError('plaintext length must be 1..65535 bytes');
  }
  final paddedLen = _calcPaddedLen(len);
  final result = Uint8List(2 + paddedLen);
  result[0] = (len >> 8) & 0xff;
  result[1] = len & 0xff;
  result.setRange(2, 2 + len, bytes);
  return result;
}

/// Strips the length prefix + zero padding added by [_pad], validating the
/// declared length is consistent with the padding scheme (defends against
/// truncation/length-extension tampering that survives the MAC check).
String _unpad(Uint8List padded) {
  if (padded.length < 2) {
    throw Exception('invalid padding: too short');
  }
  final len = (padded[0] << 8) | padded[1];
  if (len < 1 || len > 65535) {
    throw Exception('invalid padding: bad length prefix');
  }
  if (padded.length != 2 + _calcPaddedLen(len)) {
    throw Exception('invalid padding: length/bucket mismatch');
  }
  return utf8.decode(padded.sublist(2, 2 + len));
}

Uint8List _chacha20(
    Uint8List key, Uint8List nonce, Uint8List input, bool forEncryption) {
  final cipher = ChaCha7539Engine()
    ..init(forEncryption, ParametersWithIV(KeyParameter(key), nonce));
  return cipher.process(input);
}

/// Constant-time byte comparison.
bool _constEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}

List<int> _random32() {
  final r = math.Random.secure();
  return List<int>.generate(32, (_) => r.nextInt(256));
}

/// Encrypts [plaintext] from [senderPrivHex] to [receiverPubHex] per
/// NIP-44 v2. Pass [nonce32] for deterministic output (tests only) —
/// otherwise a secure random nonce is generated.
String nip44Encrypt(
    String plaintext, String senderPrivHex, String receiverPubHex,
    {List<int>? nonce32}) {
  final nonce = nonce32 ?? _random32();
  if (nonce.length != 32) {
    throw ArgumentError('nonce must be 32 bytes');
  }
  final ck = nip44ConversationKey(senderPrivHex, receiverPubHex);
  final keys = _messageKeys(ck, nonce);
  final padded = _pad(plaintext);

  final ct = _chacha20(keys.chachaKey, keys.chachaNonce, padded, true);
  final mac = _hmacSha256(keys.hmacKey, [...nonce, ...ct]);

  final payload = <int>[_nip44Version, ...nonce, ...ct, ...mac];
  return base64.encode(payload);
}

/// Decrypts a NIP-44 v2 [payload] addressed to [receiverPrivHex] from
/// [senderPubHex]. Verifies the MAC before decrypting and rejects any
/// payload whose version byte is not `0x02`.
String nip44Decrypt(
    String payload, String receiverPrivHex, String senderPubHex) {
  final Uint8List data;
  try {
    data = base64.decode(payload);
  } on FormatException {
    throw Exception('invalid payload: not valid base64');
  }
  if (data.isEmpty || data[0] != _nip44Version) {
    throw Exception('unsupported NIP-44 version');
  }
  if (data.length < 1 + 32 + 32) {
    throw Exception('invalid payload: too short');
  }
  final nonce = data.sublist(1, 33);
  final mac = data.sublist(data.length - 32);
  final ct = data.sublist(33, data.length - 32);

  final ck = nip44ConversationKey(receiverPrivHex, senderPubHex);
  final keys = _messageKeys(ck, nonce);

  final expectedMac = _hmacSha256(keys.hmacKey, [...nonce, ...ct]);
  if (!_constEq(expectedMac, mac)) {
    throw Exception('MAC verification failed');
  }

  final padded = _chacha20(
      keys.chachaKey, keys.chachaNonce, Uint8List.fromList(ct), false);
  return _unpad(padded);
}
