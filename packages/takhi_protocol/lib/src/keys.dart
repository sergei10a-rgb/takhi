// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:bip340/bip340.dart' as bip340;
import 'package:convert/convert.dart';

/// A secp256k1 key pair, hex-encoded per Nostr conventions.
class KeyPair {
  final String privateHex;
  final String publicHex;
  const KeyPair(this.privateHex, this.publicHex);
}

/// Derives the BIP-340 x-only public key (64 hex chars) from a 32-byte
/// hex-encoded private key.
String pubkeyFromPrivate(String privateHex) =>
    bip340.getPublicKey(privateHex).toLowerCase();

/// Generates a new [KeyPair]. Pass [randomBytes32] (exactly 32 bytes) for
/// deterministic output in tests; otherwise a cryptographically secure
/// random source is used.
KeyPair generateKeyPair([List<int>? randomBytes32]) {
  final bytes = randomBytes32 ?? _secureRandom32();
  if (bytes.length != 32) {
    throw ArgumentError('private key must be 32 bytes');
  }
  final priv = hex.encode(bytes);
  return KeyPair(priv, pubkeyFromPrivate(priv));
}

List<int> _secureRandom32() {
  final r = _rng();
  return List<int>.generate(32, (_) => r.nextInt(256));
}

math.Random _rng() => math.Random.secure();
