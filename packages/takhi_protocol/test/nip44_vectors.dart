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

// Two more official vectors from `v2.valid.encrypt_decrypt`, chosen because
// their plaintext exceeds the 32-byte bucket boundary in `_calcPaddedLen`
// (indices 2 and 6 of the vector array) — the padding path with zero direct
// test coverage before this fix. `sec1`/`sec2` are copied verbatim as the
// private-key scalars from the vector file; `kVecPubB2`/`kVecPubB6` are the
// BIP-340 x-only public keys derived from `sec2` with the same
// `bip340.getPublicKey` used throughout this package, exactly as done for
// `kVecPubB` above. Independently verified against the vector file's
// `conversation_key` and `payload` fields before being hardcoded here.

// v2.valid.encrypt_decrypt[2] — 43-byte multi-script plaintext
// (CJK + Latin + combining diacritics), unpadded len 43 -> padded bucket 64.
const kVecPrivA2 =
    '5c0c523f52a5b6fad39ed2403092df8cebc36318b39383bca6c00808626fab3a';
const kVecPubB2 =
    'fa3b4f81a620c66514bda0302847df167ed02a483141b5939e57bdd0cf76ad3b';
const kVecConversationKey2 =
    '3e2b52a63be47d34fe0a80e34e73d436d6963bc8f39827f327057a9986c20a45';
const kVecNonce2 =
    'b635236c42db20f021bb8d1cdff5ca75dd1a0cc72ea742ad750f33010b24f73b';
const kVecPlaintext2 = '表ポあA鷗ŒéＢ逍Üßªąñ丂㐀𠀀';
const kVecPayload2 =
    'ArY1I2xC2yDwIbuNHN/1ynXdGgzHLqdCrXUPMwELJPc7s7JqlCMJBAIIjfkpHReBPXeoMCyuClwgbT419jUWU1PwaNl4FEQYKCDKVJz+97Mp3K+Q2YGa77B6gpxB/lr1QgoqpDf7wDVrDmOqGoiPjWDqy8KzLueKDcm9BVP8xeTJIxs=';

// v2.valid.encrypt_decrypt[6] — 224-byte Arabic plaintext, unpadded len
// 224 -> padded bucket 224 (exercises a much larger bucket than index 2).
const kVecPrivA6 =
    'd5633530f5bcfebceb5584cfbbf718a30df0751b729dd9a789b9f30c0587d74e';
const kVecPubB6 =
    '36bdaf1199ab9408f21d77f2e3e1bff575d7b2bc882e408de8f954752cb9e729';
const kVecConversationKey6 =
    '75fe686d21a035f0c7cd70da64ba307936e5ca0b20710496a6b6b5f573377bdd';
const kVecNonce6 =
    'e4cd5f7ce4eea024bc71b17ad456a986a74ac426c2c62b0a15eb5c5c8f888b68';
const kVecPlaintext6 = 'مُنَاقَشَةُ سُبُلِ اِسْتِخْدَامِ اللُّغَةِ فِي '
    'النُّظُمِ الْقَائِمَةِ وَفِيم يَخُصَّ التَّطْبِيقَاتُ '
    'الْحاسُوبِيَّةُ،';
const kVecPayload6 =
    'AuTNX3zk7qAkvHGxetRWqYanSsQmwsYrChXrXFyPiItoIBsWu1CB+sStla2M4VeANASHxM78i1CfHQQH1YbBy24Tng7emYW44ol6QkFD6D8Zq7QPl+8L1c47lx8RoODEQMvNCbOk5ffUV3/AhONHBXnffrI+0025c+uRGzfqpYki4lBqm9iYU+k3Tvjczq9wU0mkVDEaM34WiQi30MfkJdRbeeYaq6kNvGPunLb3xdjjs5DL720d61Flc5ZfoZm+CBhADy9D9XiVZYLKAlkijALJur9dATYKci6OBOoc2SJS2Clai5hOVzR0yVeyHRgRfH9aLSlWW5dXcUxTo7qqRjNf8W5+J4jF4gNQp5f5d0YA4vPAzjBwSP/5bGzNDslKfcAH';
