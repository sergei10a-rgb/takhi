// SPDX-License-Identifier: AGPL-3.0-or-later
// Vector copied verbatim from the official NIP-44 v2 test vectors
// (https://github.com/paulmillr/nip44/blob/main/nip44.vectors.json),
// `v2.valid.encrypt_decrypt[0]`. `sec1`/`sec2` there are private keys;
// `kVecPubB` is the BIP-340 x-only public key derived from `sec2`
// (privkey = 2), computed with the same `bip340.getPublicKey` used
// throughout this package (see `lib/src/keys.dart`), so the tuple below
// is internally consistent with `v2.valid.get_conversation_key` entries
// keyed the same way.
const kVecPrivA =
    '0000000000000000000000000000000000000000000000000000000000000001';
const kVecPubB =
    'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
const kVecConversationKey =
    'c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d';
const kVecNonce =
    '0000000000000000000000000000000000000000000000000000000000000001';
const kVecPlaintext = 'a';
const kVecPayload =
    'AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb';
