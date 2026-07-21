// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:bip340/bip340.dart' as bip340;
import 'package:convert/convert.dart';
import 'event.dart';
import 'keys.dart';

/// Signs [unsigned] with [privateHex], filling in `pubkey`, `id`, and `sig`.
///
/// Pass [auxRand] (exactly 32 bytes) for deterministic output in tests;
/// otherwise all-zero auxiliary randomness is used (callers that need
/// production-grade randomness should supply their own [auxRand]).
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
  final aux = hex.encode(auxRand ?? List<int>.filled(32, 0));
  final sig = bip340.sign(privateHex, id, aux);
  return withPub.copyWith(id: id).copyWith(sig: sig);
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
