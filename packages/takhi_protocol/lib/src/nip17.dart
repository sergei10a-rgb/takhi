// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math' as math;

import 'event.dart';
import 'keys.dart';
import 'nip44.dart';
import 'sign.dart';

/// NIP-59 kind for a seal: an event signed by the real sender, whose
/// content is a NIP-44-encrypted [NostrEvent] JSON blob (the rumor).
const int kKindSeal = 13;

/// NIP-59 kind for a gift wrap: an event signed by a one-time ephemeral
/// key, whose content is a NIP-44-encrypted seal. This is the only kind
/// ever published to a relay for a private takhi message -- it reveals
/// neither the real sender's pubkey nor the message content to anyone but
/// the `p`-tagged recipient.
const int kKindGiftWrap = 1059;

/// Upper bound (seconds) on how far into the past a gift wrap's
/// `created_at` is randomized, per NIP-59 guidance -- large enough that
/// wraps for messages sent minutes apart are not distinguishable by
/// timing alone.
const int kGiftWrapRandomizationWindowSeconds = 2 * 24 * 60 * 60; // 2 days

/// Builds an unsigned "rumor": the real message, with its NIP-01 [id]
/// computed but never signed. A rumor must only ever travel inside a
/// seal's encrypted content -- publishing it on its own would both prove
/// nothing (no signature) and leak [pubkey]/[content] in the clear.
NostrEvent buildRumor({
  required String pubkey,
  required int createdAt,
  required int kind,
  List<List<String>> tags = const [],
  required String content,
}) {
  final unsigned = NostrEvent(
    pubkey: pubkey,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
  );
  return unsigned.copyWith(id: computeEventId(unsigned));
}

/// Seals [rumor] for [recipientPubHex]: NIP-44-encrypts the rumor's JSON
/// under (sender, recipient), then signs the result with the sender's
/// real key. Tags are always empty -- tags are public relay-routing
/// metadata, and a private message must carry none.
///
/// Pass [nonce32]/[auxRand] for deterministic output in tests; otherwise
/// secure randomness is used (via [nip44Encrypt] and [signEvent]).
NostrEvent sealRumor(
  NostrEvent rumor,
  String senderPrivHex,
  String recipientPubHex, {
  required int now,
  List<int>? nonce32,
  List<int>? auxRand,
}) {
  final encryptedRumor = nip44Encrypt(
    jsonEncode(rumor.toJson()),
    senderPrivHex,
    recipientPubHex,
    nonce32: nonce32,
  );
  final unsignedSeal = NostrEvent(
    pubkey: pubkeyFromPrivate(senderPrivHex),
    createdAt: now,
    kind: kKindSeal,
    tags: const [],
    content: encryptedRumor,
  );
  return signEvent(unsignedSeal, senderPrivHex, auxRand: auxRand);
}

/// Gift-wraps [seal] for [recipientPubHex]: NIP-44-encrypts the seal's
/// JSON under a one-time [ephemeralKeyPair], then signs the result with
/// that same ephemeral key. [randomizedCreatedAt] should already be
/// randomized into the recent past (see [nip17Wrap]/[randomTimestamp]) so
/// relays and observers cannot correlate wrap timing with the real
/// message time.
///
/// The only public tag is `['p', recipientPubHex]`, so relays can route
/// the wrap to the recipient's subscription without learning anything
/// else about it.
NostrEvent giftWrap(
  NostrEvent seal,
  String recipientPubHex, {
  required int randomizedCreatedAt,
  required KeyPair ephemeralKeyPair,
  List<int>? nonce32,
  List<int>? auxRand,
}) {
  final encryptedSeal = nip44Encrypt(
    jsonEncode(seal.toJson()),
    ephemeralKeyPair.privateHex,
    recipientPubHex,
    nonce32: nonce32,
  );
  final unsignedWrap = NostrEvent(
    pubkey: ephemeralKeyPair.publicHex,
    createdAt: randomizedCreatedAt,
    kind: kKindGiftWrap,
    tags: [
      ['p', recipientPubHex],
    ],
    content: encryptedSeal,
  );
  return signEvent(unsignedWrap, ephemeralKeyPair.privateHex, auxRand: auxRand);
}

/// A timestamp randomized into the past within
/// [kGiftWrapRandomizationWindowSeconds] of [now], per NIP-59 guidance.
int randomTimestamp(int now) =>
    now - math.Random.secure().nextInt(kGiftWrapRandomizationWindowSeconds + 1);

/// Builds and wraps a private takhi message end-to-end: rumor -> seal ->
/// gift wrap, ready to hand to `RelayPool.publish`.
///
/// [now] is the real message time (used for the rumor and the seal).
/// [wrapCreatedAt] is the gift wrap's own timestamp; if omitted, it is
/// randomized into the past via [randomTimestamp]. Pass
/// [ephemeralKeyPair] and the `*32`/`*Rand` parameters for deterministic
/// output in tests.
NostrEvent nip17Wrap({
  required String senderPrivHex,
  required String recipientPubHex,
  required int rumorKind,
  List<List<String>> rumorTags = const [],
  required String content,
  required int now,
  KeyPair? ephemeralKeyPair,
  int? wrapCreatedAt,
  List<int>? sealNonce32,
  List<int>? sealAuxRand,
  List<int>? wrapNonce32,
  List<int>? wrapAuxRand,
}) {
  final senderPub = pubkeyFromPrivate(senderPrivHex);
  final rumor = buildRumor(
    pubkey: senderPub,
    createdAt: now,
    kind: rumorKind,
    tags: rumorTags,
    content: content,
  );
  final seal = sealRumor(
    rumor,
    senderPrivHex,
    recipientPubHex,
    now: now,
    nonce32: sealNonce32,
    auxRand: sealAuxRand,
  );
  final ephemeral = ephemeralKeyPair ?? generateKeyPair();
  final wrapTime = wrapCreatedAt ?? randomTimestamp(now);
  return giftWrap(
    seal,
    recipientPubHex,
    randomizedCreatedAt: wrapTime,
    ephemeralKeyPair: ephemeral,
    nonce32: wrapNonce32,
    auxRand: wrapAuxRand,
  );
}

/// A private takhi message recovered from a gift wrap: the inner [rumor]
/// plus the cryptographically verified real [senderPubkey].
class UnwrappedDm {
  final NostrEvent rumor;
  final String senderPubkey;
  const UnwrappedDm(this.rumor, this.senderPubkey);
}

/// Reverses [nip17Wrap]/[giftWrap]: decrypts [wrap] with
/// [recipientPrivHex], verifies the inner seal's signature, decrypts the
/// rumor, and checks that the rumor's claimed [NostrEvent.pubkey] matches
/// the seal's signer -- otherwise a malicious sender could seal a rumor
/// claiming to be from someone else entirely.
///
/// Throws [FormatException] if [wrap] is not a gift wrap, the inner seal
/// has the wrong kind or an invalid signature, or the rumor's pubkey does
/// not match the seal's signer. Throws the underlying [Exception] (from
/// [nip44Decrypt]) if [wrap] cannot be decrypted with [recipientPrivHex]
/// at all -- e.g. it was addressed to someone else.
UnwrappedDm nip17Unwrap(NostrEvent wrap, String recipientPrivHex) {
  if (wrap.kind != kKindGiftWrap) {
    throw FormatException('not a gift wrap (kind ${wrap.kind})');
  }
  final sealJson = nip44Decrypt(wrap.content, recipientPrivHex, wrap.pubkey);
  final seal =
      NostrEvent.fromJson(jsonDecode(sealJson) as Map<String, dynamic>);
  if (seal.kind != kKindSeal) {
    throw FormatException('inner event is not a seal (kind ${seal.kind})');
  }
  if (!verifyEvent(seal)) {
    throw FormatException('seal signature does not verify');
  }
  final rumorJson = nip44Decrypt(seal.content, recipientPrivHex, seal.pubkey);
  final rumor =
      NostrEvent.fromJson(jsonDecode(rumorJson) as Map<String, dynamic>);
  if (rumor.pubkey != seal.pubkey) {
    throw FormatException(
        "rumor pubkey does not match the seal's signer (spoofed sender)");
  }
  return UnwrappedDm(rumor, seal.pubkey);
}
