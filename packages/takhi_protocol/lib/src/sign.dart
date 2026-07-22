// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:bip340/bip340.dart' as bip340;
import 'package:convert/convert.dart';
import 'event.dart';
import 'keys.dart';

/// Signs [unsigned] with [privateHex], filling in `pubkey`, `id`, and `sig`.
///
/// Pass [auxRand] (exactly 32 bytes) for deterministic output in tests;
/// otherwise cryptographically secure auxiliary randomness is generated
/// per BIP-340, using the same `dart:math` `Random.secure()` source as
/// [generateKeyPair] in `keys.dart`.
NostrEvent signEvent(NostrEvent unsigned, String privateHex,
    {List<int>? auxRand}) {
  final pub = pubkeyFromPrivate(privateHex);
  final withPub = NostrEvent(
    pubkey: pub,
    createdAt: unsigned.createdAt,
    kind: unsigned.kind,
    tags: unsigned.tags,
    content: unsigned.content,
  );
  final id = computeEventId(withPub);
  final aux = hex.encode(auxRand ?? _secureRandom32());
  final sig = bip340.sign(privateHex, id, aux);
  return withPub.copyWith(id: id).copyWith(sig: sig);
}

/// Cryptographically secure 32-byte auxiliary randomness for BIP-340
/// signing. Mirrors `keys.dart`'s private `_secureRandom32`.
List<int> _secureRandom32() {
  final r = math.Random.secure();
  return List<int>.generate(32, (_) => r.nextInt(256));
}

/// Recomputes the NIP-01 event id from [e]'s fields and checks the BIP-340
/// Schnorr signature. Returns `false` if `id`/`sig` are missing, the id does
/// not match the recomputed hash, or the signature is invalid.
bool verifyEvent(NostrEvent e) {
  if (e.id == null || e.sig == null) return false;
  final expectedId = computeEventId(e);
  if (expectedId != e.id) return false;
  return bip340.verify(e.pubkey, e.id!, e.sig!);
}
