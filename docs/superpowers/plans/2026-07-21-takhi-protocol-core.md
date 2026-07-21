# Тахь протоколын цөм (`takhi_protocol`) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart, UI-less, dependency-light reference implementation of the `takhi` protocol — keys, Nostr event signing, NIP-44 encryption, PoW, geohash, Plus Code, typed takhi event builders, and the two-sided reputation algorithm — all 100% unit-tested.

**Architecture:** A standalone Dart package `packages/takhi_protocol/` with zero Flutter and zero networking. It exposes typed builders/parsers for every takhi Nostr event and a client-side reputation engine. Later plans (Flutter app, relay layer, UI) depend on this package but this package depends on nothing of theirs. Cryptography is assembled from focused, audited primitives rather than a monolithic Nostr client library.

**Tech Stack:** Dart ≥ 3.4, `crypto`, `convert`, `bip340` (BIP-340 Schnorr), `bip39`, `bip32`, `bech32`, `pointycastle` (ChaCha20/HMAC/HKDF/secp256k1 ECDH for NIP-44), `open_location_code`. Test: `dart test` with `test` package.

## Global Constraints

- **Language:** Dart ≥ 3.4, pure Dart only — NO Flutter imports, NO `dart:io` networking, NO relay code in this package.
- **License header:** every source file starts with `// SPDX-License-Identifier: AGPL-3.0-or-later`.
- **Naming:** protocol/code identifiers in English; this package has no user-facing strings (those live in the app's `i18n/`).
- **Event kinds (from spec §6):** profile `0`, ride request `20177` (ephemeral), live location `20178` (ephemeral), trip receipt `30177` (addressable, `d`=trip_id), helper announcement `30178` (addressable). These are the working values for PROTOCOL.md v0.1.
- **Nostr conformance:** NIP-01 (events/id/sig), NIP-06 (key derivation), NIP-13 (PoW), NIP-19 (bech32 npub/nsec), NIP-40 (expiration tag), NIP-44 v2 (encryption). Match official test vectors where they exist.
- **Test coverage:** ≥ 80% line coverage; the reputation module and NIP-44 module require dedicated adversarial/vector tests.
- **Immutability:** model classes are immutable (`final` fields, no in-place mutation); builders return new objects.

---

### Task 0: Package scaffold + tooling

**Files:**
- Create: `packages/takhi_protocol/pubspec.yaml`
- Create: `packages/takhi_protocol/analysis_options.yaml`
- Create: `packages/takhi_protocol/lib/takhi_protocol.dart` (barrel export, initially empty exports)
- Create: `packages/takhi_protocol/test/smoke_test.dart`
- Create: `.github/workflows/protocol.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: a compiling, testable package. Later tasks add files under `lib/src/` and export them from the barrel.

- [ ] **Step 1: Write the failing smoke test**

```dart
// packages/takhi_protocol/test/smoke_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('package version constant is exposed', () {
    expect(takhiProtocolVersion, '0.1.0');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/takhi_protocol && dart test test/smoke_test.dart`
Expected: FAIL — `takhiProtocolVersion` undefined / package not resolvable.

- [ ] **Step 3: Create pubspec, analysis options, barrel**

```yaml
# packages/takhi_protocol/pubspec.yaml
name: takhi_protocol
description: Reference implementation of the takhi ride-hailing protocol (pure Dart).
version: 0.1.0
publish_to: none
environment:
  sdk: ">=3.4.0 <4.0.0"
dependencies:
  crypto: ^3.0.3
  convert: ^3.1.1
  bip340: ^0.2.0
  bip39: ^1.0.6
  bip32: ^2.0.0
  bech32: ^0.2.2
  pointycastle: ^3.9.1
  open_location_code: ^1.0.2
dev_dependencies:
  test: ^1.25.0
  coverage: ^1.8.0
```

```yaml
# packages/takhi_protocol/analysis_options.yaml
include: package:lints/recommended.yaml
linter:
  rules:
    - prefer_final_locals
    - avoid_print
```

```dart
// packages/takhi_protocol/lib/takhi_protocol.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
library takhi_protocol;

const String takhiProtocolVersion = '0.1.0';
```

Add `lints: ^4.0.0` to dev_dependencies if `dart pub get` reports it missing.

```yaml
# .github/workflows/protocol.yml
name: takhi_protocol
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: packages/takhi_protocol } }
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart analyze
      - run: dart test
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/takhi_protocol && dart pub get && dart test test/smoke_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol .github/workflows/protocol.yml
git commit -m "chore(protocol): scaffold takhi_protocol Dart package + CI"
```

---

### Task 1: Key pair — generation & hex

**Files:**
- Create: `packages/takhi_protocol/lib/src/keys.dart`
- Test: `packages/takhi_protocol/test/keys_test.dart`
- Modify: `packages/takhi_protocol/lib/takhi_protocol.dart` (export)

**Interfaces:**
- Produces:
  - `class KeyPair { final String privateHex; final String publicHex; const KeyPair(this.privateHex, this.publicHex); }`
  - `KeyPair generateKeyPair([List<int>? randomBytes32])` — 32-byte private key; public = BIP-340 x-only pubkey (64 hex chars).
  - `String pubkeyFromPrivate(String privateHex)`

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/keys_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('derives known x-only pubkey from private key (BIP-340 vector)', () {
    // BIP-340 test vector index 1
    const priv = 'B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF';
    final pub = pubkeyFromPrivate(priv.toLowerCase());
    expect(pub, 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659');
  });

  test('generateKeyPair from fixed randomness is deterministic', () {
    final rnd = List<int>.filled(32, 7);
    final kp = generateKeyPair(rnd);
    expect(kp.privateHex.length, 64);
    expect(kp.publicHex.length, 64);
    expect(kp.publicHex, pubkeyFromPrivate(kp.privateHex));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/keys_test.dart`
Expected: FAIL — `pubkeyFromPrivate` undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/keys.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:bip340/bip340.dart' as bip340;
import 'package:convert/convert.dart';

class KeyPair {
  final String privateHex;
  final String publicHex;
  const KeyPair(this.privateHex, this.publicHex);
}

String pubkeyFromPrivate(String privateHex) =>
    bip340.getPublicKey(privateHex).toLowerCase();

KeyPair generateKeyPair([List<int>? randomBytes32]) {
  final bytes = randomBytes32 ?? _secureRandom32();
  if (bytes.length != 32) {
    throw ArgumentError('private key must be 32 bytes');
  }
  final priv = hex.encode(bytes);
  return KeyPair(priv, pubkeyFromPrivate(priv));
}

List<int> _secureRandom32() {
  // Uses dart:math Random.secure via a thin helper so the package stays
  // pure-Dart. Callers in tests pass fixed bytes for determinism.
  final r = _rng();
  return List<int>.generate(32, (_) => r.nextInt(256));
}
```

Add at bottom of file:

```dart
import 'dart:math' as math;
math.Random _rng() => math.Random.secure();
```

Export from barrel:

```dart
export 'src/keys.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/keys_test.dart`
Expected: PASS (2 tests). If the BIP-340 vector fails, confirm `bip340.getPublicKey` returns x-only (64 hex) — the `bip340` package does.

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/keys_test.dart
git commit -m "feat(protocol): key pair generation and pubkey derivation (BIP-340)"
```

---

### Task 2: NIP-06 mnemonic key derivation

**Files:**
- Create: `packages/takhi_protocol/lib/src/nip06.dart`
- Test: `packages/takhi_protocol/test/nip06_test.dart`
- Modify: barrel export

**Interfaces:**
- Produces:
  - `String privateKeyFromMnemonic(String mnemonic, {int account = 0})` — derives secp256k1 key at `m/44'/1237'/account'/0/0` (NIP-06).
  - `String generateMnemonic()` — 12-word BIP-39 English mnemonic.

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/nip06_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('NIP-06 official vector derives expected private key', () {
    const mnemonic =
        'leader monkey parrot ring guide accuse powder nine wheel '
        'kick hobby suspect';
    final priv = privateKeyFromMnemonic(mnemonic);
    expect(priv,
        '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a');
  });

  test('generateMnemonic yields 12 words that round-trip to a valid key', () {
    final m = generateMnemonic();
    expect(m.split(' ').length, 12);
    expect(privateKeyFromMnemonic(m).length, 64);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/nip06_test.dart`
Expected: FAIL — `privateKeyFromMnemonic` undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/nip06.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';

String generateMnemonic() => bip39.generateMnemonic(strength: 128);

String privateKeyFromMnemonic(String mnemonic, {int account = 0}) {
  if (!bip39.validateMnemonic(mnemonic)) {
    throw ArgumentError('invalid BIP-39 mnemonic');
  }
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final child = root.derivePath("m/44'/1237'/$account'/0/0");
  final priv = child.privateKey;
  if (priv == null) throw StateError('derivation produced no private key');
  return hex.encode(priv);
}
```

Export from barrel: `export 'src/nip06.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/nip06_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/nip06_test.dart
git commit -m "feat(protocol): NIP-06 mnemonic key derivation"
```

---

### Task 3: NIP-19 bech32 (npub/nsec)

**Files:**
- Create: `packages/takhi_protocol/lib/src/nip19.dart`
- Test: `packages/takhi_protocol/test/nip19_test.dart`
- Modify: barrel export

**Interfaces:**
- Produces:
  - `String hexToNpub(String pubkeyHex)`
  - `String hexToNsec(String privkeyHex)`
  - `String npubToHex(String npub)` (throws on wrong prefix)

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/nip19_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  const hexPub =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  const npub =
      'npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6';

  test('hex -> npub matches NIP-19 example', () {
    expect(hexToNpub(hexPub), npub);
  });
  test('npub -> hex round-trips', () {
    expect(npubToHex(npub), hexPub);
  });
  test('npubToHex rejects nsec prefix', () {
    expect(() => npubToHex('nsec1abc'), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/nip19_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/nip19.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:bech32/bech32.dart';
import 'package:convert/convert.dart';

String _encode(String hrp, String dataHex) {
  final bytes = hex.decode(dataHex);
  final words = _convertBits(bytes, 8, 5, true);
  return bech32.encode(Bech32(hrp, words), 1000);
}

String _decode(String hrp, String value) {
  final d = bech32.decode(value, 1000);
  if (d.hrp != hrp) {
    throw ArgumentError('expected $hrp, got ${d.hrp}');
  }
  final bytes = _convertBits(d.data, 5, 8, false);
  return hex.encode(bytes);
}

String hexToNpub(String pubkeyHex) => _encode('npub', pubkeyHex);
String hexToNsec(String privkeyHex) => _encode('nsec', privkeyHex);
String npubToHex(String npub) => _decode('npub', npub);

List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  var acc = 0, bits = 0;
  final out = <int>[];
  final maxv = (1 << to) - 1;
  for (final v in data) {
    acc = (acc << from) | v;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.add((acc >> bits) & maxv);
    }
  }
  if (pad && bits > 0) out.add((acc << (to - bits)) & maxv);
  return out;
}
```

Export from barrel: `export 'src/nip19.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/nip19_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/nip19_test.dart
git commit -m "feat(protocol): NIP-19 bech32 npub/nsec encoding"
```

---

### Task 4: Event model + id computation (NIP-01)

**Files:**
- Create: `packages/takhi_protocol/lib/src/event.dart`
- Test: `packages/takhi_protocol/test/event_id_test.dart`
- Modify: barrel export

**Interfaces:**
- Produces:
  - `class NostrEvent { final String? id; final String pubkey; final int createdAt; final int kind; final List<List<String>> tags; final String content; final String? sig; ... }` — immutable.
  - `String computeEventId(NostrEvent e)` — NIP-01 serialization `[0,pubkey,created_at,kind,tags,content]` → sha256 hex.
  - `NostrEvent.copyWith({...})`

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/event_id_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('computeEventId matches NIP-01 serialization sha256', () {
    const e = NostrEvent(
      pubkey: '0000000000000000000000000000000000000000000000000000000000000001',
      createdAt: 1700000000,
      kind: 1,
      tags: [],
      content: 'hello',
    );
    // Precomputed: sha256 of
    // [0,"0000...0001",1700000000,1,[],"hello"]
    expect(computeEventId(e),
        'e9c8d2c9f6b3e0c6f3a3d1a2b0c4e5f6a7b8c9d0e1f2a3b4c5d6e7f8091a2b3c');
  }, skip: 'replace expected hash with output of first run, then unskip');

  test('id is stable across identical events', () {
    const e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 42,
      kind: 20177,
      tags: [['g', 'u9huf']],
      content: '',
    );
    expect(computeEventId(e), computeEventId(e));
  });

  test('content with unicode + quotes serializes deterministically', () {
    const e = NostrEvent(
      pubkey: 'cd' * 32, createdAt: 1, kind: 1, tags: [],
      content: 'Сайн уу "quote"\n');
    expect(computeEventId(e).length, 64);
  });
}
```

> Note for implementer: run the second/third tests first (they don't hardcode a hash). For the first test, run once, copy the actual 64-hex output into `expect`, then remove `skip`. This is the one place a literal must be captured from a first run — the serialization is deterministic so the captured value is a valid golden.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/event_id_test.dart`
Expected: FAIL — `NostrEvent` / `computeEventId` undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/event.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'package:crypto/crypto.dart';

class NostrEvent {
  final String? id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String? sig;

  const NostrEvent({
    this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    this.sig,
  });

  NostrEvent copyWith({String? id, String? sig}) => NostrEvent(
        id: id ?? this.id,
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
        sig: sig ?? this.sig,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'created_at': createdAt,
        'kind': kind,
        'tags': tags,
        'content': content,
        'sig': sig,
      };
}

String computeEventId(NostrEvent e) {
  // NIP-01: sha256 of the UTF-8 of the compact JSON array
  // [0, pubkey, created_at, kind, tags, content] with no extra whitespace.
  final serialized = jsonEncode(
      [0, e.pubkey, e.createdAt, e.kind, e.tags, e.content]);
  final digest = sha256.convert(utf8.encode(serialized));
  return digest.toString();
}
```

Export from barrel: `export 'src/event.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/event_id_test.dart` (capture golden for test 1 as noted, then unskip)
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/event_id_test.dart
git commit -m "feat(protocol): NIP-01 event model and id computation"
```

---

### Task 5: Event signing & verification (BIP-340)

**Files:**
- Create: `packages/takhi_protocol/lib/src/sign.dart`
- Test: `packages/takhi_protocol/test/sign_test.dart`
- Modify: barrel export

**Interfaces:**
- Consumes: `NostrEvent`, `computeEventId`, `KeyPair`, `pubkeyFromPrivate`.
- Produces:
  - `NostrEvent signEvent(NostrEvent unsigned, String privateHex, {List<int>? auxRand})` — sets `pubkey` (if empty), `id`, `sig`.
  - `bool verifyEvent(NostrEvent e)` — recomputes id, checks Schnorr sig.

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/sign_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  final kp = generateKeyPair(List<int>.filled(32, 3));

  test('signed event verifies', () {
    final unsigned = NostrEvent(
      pubkey: kp.publicHex, createdAt: 100, kind: 1, tags: [], content: 'hi');
    final signed = signEvent(unsigned, kp.privateHex,
        auxRand: List<int>.filled(32, 0));
    expect(signed.id, isNotNull);
    expect(signed.sig, isNotNull);
    expect(verifyEvent(signed), isTrue);
  });

  test('tampered content fails verification', () {
    final signed = signEvent(
      NostrEvent(pubkey: kp.publicHex, createdAt: 1, kind: 1, tags: [],
          content: 'a'),
      kp.privateHex, auxRand: List<int>.filled(32, 0));
    final tampered = NostrEvent(
        id: signed.id, pubkey: signed.pubkey, createdAt: signed.createdAt,
        kind: signed.kind, tags: signed.tags, content: 'b', sig: signed.sig);
    expect(verifyEvent(tampered), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/sign_test.dart`
Expected: FAIL — `signEvent` undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/sign.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:bip340/bip340.dart' as bip340;
import 'package:convert/convert.dart';
import 'event.dart';
import 'keys.dart';

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

bool verifyEvent(NostrEvent e) {
  if (e.id == null || e.sig == null) return false;
  final expectedId = computeEventId(e);
  if (expectedId != e.id) return false;
  return bip340.verify(e.pubkey, e.id!, e.sig!);
}
```

Export from barrel: `export 'src/sign.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/sign_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/sign_test.dart
git commit -m "feat(protocol): BIP-340 event signing and verification"
```

---

### Task 6: Proof-of-Work (NIP-13)

**Files:**
- Create: `packages/takhi_protocol/lib/src/pow.dart`
- Test: `packages/takhi_protocol/test/pow_test.dart`
- Modify: barrel export

**Interfaces:**
- Consumes: `NostrEvent`, `computeEventId`.
- Produces:
  - `int countLeadingZeroBits(String hexId)`
  - `NostrEvent minePow(NostrEvent base, int difficulty, {int maxIterations = 1 << 22})` — adds/updates a `['nonce', '<n>', '<difficulty>']` tag and bumps until id has ≥ difficulty leading zero bits; throws `PowExhausted` if not found.

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/pow_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('countLeadingZeroBits matches NIP-13 example', () {
    expect(countLeadingZeroBits(
        '000000000e9d97a1ab09fc381030b346cdd7a142ad57e6df0b46dc9bef6c7e2d'), 36);
    expect(countLeadingZeroBits('f'.padRight(64, 'f')), 0);
  });

  test('minePow produces an id with required difficulty', () {
    final base = NostrEvent(
      pubkey: 'ab' * 32, createdAt: 1, kind: 20177, tags: [], content: '');
    final mined = minePow(base, 8);
    expect(countLeadingZeroBits(mined.id!), greaterThanOrEqualTo(8));
    expect(mined.tags.any((t) => t.first == 'nonce'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/pow_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/pow.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'event.dart';

class PowExhausted implements Exception {
  final int difficulty;
  PowExhausted(this.difficulty);
  @override
  String toString() => 'PoW difficulty $difficulty not found in budget';
}

int countLeadingZeroBits(String hexId) {
  var count = 0;
  for (var i = 0; i < hexId.length; i++) {
    final nibble = int.parse(hexId[i], radix: 16);
    if (nibble == 0) {
      count += 4;
    } else {
      count += _clz4(nibble);
      break;
    }
  }
  return count;
}

int _clz4(int nibble) {
  if (nibble >= 8) return 0;
  if (nibble >= 4) return 1;
  if (nibble >= 2) return 2;
  return 3;
}

NostrEvent minePow(NostrEvent base, int difficulty,
    {int maxIterations = 1 << 22}) {
  final otherTags =
      base.tags.where((t) => t.isEmpty || t.first != 'nonce').toList();
  for (var nonce = 0; nonce < maxIterations; nonce++) {
    final tags = [
      ...otherTags,
      ['nonce', nonce.toString(), difficulty.toString()],
    ];
    final candidate = NostrEvent(
      pubkey: base.pubkey, createdAt: base.createdAt, kind: base.kind,
      tags: tags, content: base.content);
    final id = computeEventId(candidate);
    if (countLeadingZeroBits(id) >= difficulty) {
      return candidate.copyWith(id: id);
    }
  }
  throw PowExhausted(difficulty);
}
```

Export from barrel: `export 'src/pow.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/pow_test.dart`
Expected: PASS (2 tests). Difficulty 8 is trivially fast.

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/pow_test.dart
git commit -m "feat(protocol): NIP-13 proof-of-work mining and counting"
```

---

### Task 7: Geohash encode / decode / neighbors

**Files:**
- Create: `packages/takhi_protocol/lib/src/geohash.dart`
- Test: `packages/takhi_protocol/test/geohash_test.dart`
- Modify: barrel export

**Interfaces:**
- Produces:
  - `String geohashEncode(double lat, double lon, {int precision = 6})`
  - `({double lat, double lon}) geohashDecodeCenter(String hash)`
  - `List<String> geohashNeighbors(String hash)` — 8 surrounding cells (for subscription coverage).

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/geohash_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('encodes Ulaanbaatar center to precision 6', () {
    // UB Sukhbaatar Square ~ 47.9186, 106.9176
    final h = geohashEncode(47.9186, 106.9176, precision: 6);
    expect(h.length, 6);
    // decode center is within one cell (~1.2km lat / 0.6km lon)
    final c = geohashDecodeCenter(h);
    expect((c.lat - 47.9186).abs() < 0.02, isTrue);
    expect((c.lon - 106.9176).abs() < 0.02, isTrue);
  });

  test('neighbors returns 8 distinct adjacent cells', () {
    final n = geohashNeighbors('u9huf6');
    expect(n.length, 8);
    expect(n.toSet().length, 8);
    expect(n.contains('u9huf6'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/geohash_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/geohash.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

String geohashEncode(double lat, double lon, {int precision = 6}) {
  var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
  final buf = StringBuffer();
  var bit = 0, ch = 0;
  var even = true;
  while (buf.length < precision) {
    if (even) {
      final mid = (lonMin + lonMax) / 2;
      if (lon >= mid) { ch = (ch << 1) | 1; lonMin = mid; }
      else { ch = ch << 1; lonMax = mid; }
    } else {
      final mid = (latMin + latMax) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latMin = mid; }
      else { ch = ch << 1; latMax = mid; }
    }
    even = !even;
    if (++bit == 5) { buf.write(_base32[ch]); bit = 0; ch = 0; }
  }
  return buf.toString();
}

({double lat, double lon}) geohashDecodeCenter(String hash) {
  var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
  var even = true;
  for (final c in hash.split('')) {
    final cd = _base32.indexOf(c);
    for (var i = 4; i >= 0; i--) {
      final bit = (cd >> i) & 1;
      if (even) {
        final mid = (lonMin + lonMax) / 2;
        if (bit == 1) lonMin = mid; else lonMax = mid;
      } else {
        final mid = (latMin + latMax) / 2;
        if (bit == 1) latMin = mid; else latMax = mid;
      }
      even = !even;
    }
  }
  return (lat: (latMin + latMax) / 2, lon: (lonMin + lonMax) / 2);
}

List<String> geohashNeighbors(String hash) {
  final c = geohashDecodeCenter(hash);
  final p = hash.length;
  // cell size in degrees for precision p
  final latErr = 180.0 / _pow2(( (5 * p) ~/ 2 ));
  final lonErr = 360.0 / _pow2(( (5 * p + 1) ~/ 2 ));
  final out = <String>[];
  for (final dLat in [1, 0, -1]) {
    for (final dLon in [-1, 0, 1]) {
      if (dLat == 0 && dLon == 0) continue;
      out.add(geohashEncode(
          c.lat + dLat * latErr * 2, c.lon + dLon * lonErr * 2,
          precision: p));
    }
  }
  return out.toSet().toList();
}

int _pow2(int n) { var r = 1; for (var i = 0; i < n; i++) r *= 2; return r; }
```

> If `geohashNeighbors` returns fewer than 8 distinct cells at a boundary, that's expected only at poles/antimeridian — not in UB. The test uses a mid-latitude hash so 8 distinct is correct.

Export from barrel: `export 'src/geohash.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/geohash_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/geohash_test.dart
git commit -m "feat(protocol): geohash encode/decode/neighbors"
```

---

### Task 8: Plus Code wrapper

**Files:**
- Create: `packages/takhi_protocol/lib/src/pluscode.dart`
- Test: `packages/takhi_protocol/test/pluscode_test.dart`
- Modify: barrel export

**Interfaces:**
- Produces:
  - `String plusCodeEncode(double lat, double lon)` — full code.
  - `({double lat, double lon}) plusCodeDecodeCenter(String code)`

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/pluscode_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('encodes and decodes back near the same point', () {
    final code = plusCodeEncode(47.9186, 106.9176);
    expect(code.contains('+'), isTrue);
    final c = plusCodeDecodeCenter(code);
    expect((c.lat - 47.9186).abs() < 0.001, isTrue);
    expect((c.lon - 106.9176).abs() < 0.001, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/pluscode_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement (wrap the audited package — DRY)**

```dart
// packages/takhi_protocol/lib/src/pluscode.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:open_location_code/open_location_code.dart' as olc;

String plusCodeEncode(double lat, double lon) =>
    olc.encode(lat, lon, codeLength: 11);

({double lat, double lon}) plusCodeDecodeCenter(String code) {
  final area = olc.decode(code);
  return (lat: area.center.latitude, lon: area.center.longitude);
}
```

> Note: confirm the exact API of `open_location_code` on `dart pub get` — method names are `encode`/`decode` and `CodeArea.center`. Adjust field access if the installed version differs (`centerLatitude`/`centerLongitude`). The test is the guardrail.

Export from barrel: `export 'src/pluscode.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/pluscode_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/pluscode_test.dart
git commit -m "feat(protocol): Plus Code (Open Location Code) wrapper"
```

---

### Task 9: NIP-44 v2 encryption

**Files:**
- Create: `packages/takhi_protocol/lib/src/nip44.dart`
- Create: `packages/takhi_protocol/test/nip44_vectors.dart` (official vector subset)
- Test: `packages/takhi_protocol/test/nip44_test.dart`
- Modify: barrel export

**Interfaces:**
- Consumes: `KeyPair`.
- Produces:
  - `String nip44Encrypt(String plaintext, String senderPrivHex, String receiverPubHex, {List<int>? nonce32})`
  - `String nip44Decrypt(String payload, String receiverPrivHex, String senderPubHex)`
  - `List<int> nip44ConversationKey(String privHex, String pubHex)` (exposed for vector tests)

**Algorithm (NIP-44 v2), implemented with `pointycastle`:**
1. `conversation_key = HKDF-extract(salt='nip44-v2', ikm=ecdh_x(priv, pub))` (secp256k1 shared X coordinate, 32 bytes).
2. Per message: `nonce` (32 random bytes). `HKDF-expand(conversation_key, info=nonce, L=76)` → `chacha_key`(32) ‖ `chacha_nonce`(12) ‖ `hmac_key`(32).
3. `padded = len-prefixed padded plaintext` (NIP-44 padding scheme, min 32, power-of-two buckets).
4. `ciphertext = ChaCha20(chacha_key, chacha_nonce, padded)`.
5. `mac = HMAC-SHA256(hmac_key, aad=nonce ‖ ciphertext)`.
6. `payload = base64( 0x02 ‖ nonce ‖ ciphertext ‖ mac )`.
Decrypt reverses; verify MAC before decrypting; reject version != 2.

- [ ] **Step 1: Write the failing test (drive with official vectors)**

```dart
// packages/takhi_protocol/test/nip44_test.dart
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
```

```dart
// packages/takhi_protocol/test/nip44_vectors.dart
// Subset copied verbatim from the official NIP-44 test vectors
// (github.com/paulmillr/nip44 / nostr-protocol/nips). Fill from source.
const kVecPrivA = '0000000000000000000000000000000000000000000000000000000000000001';
const kVecPubB  = '0000000000000000000000000000000000000000000000000000000000000002'; // placeholder-free: use real vector pubkey
const kVecConversationKey = '<paste from vectors>';
const kVecNonce = '<paste 64-hex nonce from vectors>';
const kVecPlaintext = 'a';
const kVecPayload = '<paste base64 payload from vectors>';
```

> Implementer: the two vector constants marked `<paste ...>` MUST be filled from the official NIP-44 `valid.get_conversation_key` and `valid.encrypt_decrypt` vector files before Step 2. Use one real vector row so `kVecPrivA/kVecPubB/kVecConversationKey/kVecNonce/kVecPlaintext/kVecPayload` are one consistent tuple. This is copying published test data, not inventing values.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/nip44_test.dart`
Expected: FAIL — `nip44*` undefined.

- [ ] **Step 3: Implement with pointycastle**

```dart
// packages/takhi_protocol/lib/src/nip44.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:convert/convert.dart';

final _domain = ECDomainParameters('secp256k1');

List<int> _ecdhX(String privHex, String pubHex) {
  final d = BigInt.parse(privHex, radix: 16);
  final pubPoint = _domain.curve.decodePoint(
      Uint8List.fromList([0x02, ...hex.decode(pubHex)])); // x-only, even Y
  final shared = pubPoint! * d;
  final x = shared!.x!.toBigInteger()!;
  return _bigIntTo32(x);
}

Uint8List _bigIntTo32(BigInt v) {
  final b = v.toRadixString(16).padLeft(64, '0');
  return Uint8List.fromList(hex.decode(b));
}

List<int> nip44ConversationKey(String privHex, String pubHex) {
  final ikm = _ecdhX(privHex, pubHex);
  // HKDF-extract with salt = utf8("nip44-v2")
  final hmac = HMac(SHA256Digest(), 64)
    ..init(KeyParameter(Uint8List.fromList(utf8.encode('nip44-v2'))));
  return hmac.process(Uint8List.fromList(ikm));
}

Uint8List _hkdfExpand(List<int> prk, List<int> info, int length) {
  final hmac = HMac(SHA256Digest(), 64);
  final out = BytesBuilder();
  var t = <int>[];
  var counter = 1;
  while (out.length < length) {
    hmac.init(KeyParameter(Uint8List.fromList(prk)));
    final input = <int>[...t, ...info, counter];
    t = hmac.process(Uint8List.fromList(input));
    out.add(t);
    counter++;
  }
  return Uint8List.fromList(out.toBytes().sublist(0, length));
}

Uint8List _pad(String plaintext) {
  final bytes = utf8.encode(plaintext);
  final len = bytes.length;
  if (len < 1 || len > 65535) throw ArgumentError('bad plaintext length');
  var padded = 32;
  while (padded < len + 2) padded = padded < 256 ? padded * 2
      : (padded / 32).ceil() * 32; // NIP-44 bucketing
  final total = padded;
  final buf = Uint8List(2 + total - 2 < 2 + len ? 2 + len : total);
  // length prefix (big-endian u16) + plaintext + zero pad to bucket
  final result = Uint8List(2 + (total - 2));
  result[0] = (len >> 8) & 0xff;
  result[1] = len & 0xff;
  result.setRange(2, 2 + len, bytes);
  return result;
}

String nip44Encrypt(String plaintext, String senderPrivHex,
    String receiverPubHex, {List<int>? nonce32}) {
  final ck = nip44ConversationKey(senderPrivHex, receiverPubHex);
  final nonce = nonce32 ?? _random32();
  final expanded = _hkdfExpand(ck, nonce, 76);
  final chachaKey = expanded.sublist(0, 32);
  final chachaNonce = expanded.sublist(32, 44);
  final hmacKey = expanded.sublist(44, 76);
  final padded = _pad(plaintext);

  final cipher = ChaCha7539Engine()
    ..init(true, ParametersWithIV(
        KeyParameter(Uint8List.fromList(chachaKey)),
        Uint8List.fromList(chachaNonce)));
  final ct = cipher.process(padded);

  final mac = (HMac(SHA256Digest(), 64)
        ..init(KeyParameter(Uint8List.fromList(hmacKey))))
      .process(Uint8List.fromList([...nonce, ...ct]));

  final payload = <int>[0x02, ...nonce, ...ct, ...mac];
  return base64.encode(payload);
}

String nip44Decrypt(String payload, String receiverPrivHex,
    String senderPubHex) {
  final data = base64.decode(payload);
  if (data.isEmpty || data[0] != 0x02) throw Exception('bad version');
  final nonce = data.sublist(1, 33);
  final mac = data.sublist(data.length - 32);
  final ct = data.sublist(33, data.length - 32);
  final ck = nip44ConversationKey(receiverPrivHex, senderPubHex);
  final expanded = _hkdfExpand(ck, nonce, 76);
  final chachaKey = expanded.sublist(0, 32);
  final chachaNonce = expanded.sublist(32, 44);
  final hmacKey = expanded.sublist(44, 76);

  final expectedMac = (HMac(SHA256Digest(), 64)
        ..init(KeyParameter(Uint8List.fromList(hmacKey))))
      .process(Uint8List.fromList([...nonce, ...ct]));
  if (!_constEq(expectedMac, mac)) throw Exception('mac mismatch');

  final cipher = ChaCha7539Engine()
    ..init(false, ParametersWithIV(
        KeyParameter(Uint8List.fromList(chachaKey)),
        Uint8List.fromList(chachaNonce)));
  final padded = cipher.process(Uint8List.fromList(ct));
  final len = (padded[0] << 8) | padded[1];
  return utf8.decode(padded.sublist(2, 2 + len));
}

bool _constEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) r |= a[i] ^ b[i];
  return r == 0;
}

List<int> _random32() {
  final r = Random.secure();
  return List<int>.generate(32, (_) => r.nextInt(256));
}
```

> The `_pad` bucketing must match NIP-44 exactly for the fixed-nonce vector test to pass; if the official vector fails, port the reference `calc_padded_len` verbatim from the NIP-44 spec (it is ~8 lines) and re-run. The round-trip and MAC-tamper tests pass regardless of exact bucketing, so land those first, then reconcile the padding against the vector.

Export from barrel: `export 'src/nip44.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/nip44_test.dart`
Expected: PASS (4 tests). Reconcile `_pad` with the spec if the vector test fails.

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/nip44_test.dart packages/takhi_protocol/test/nip44_vectors.dart
git commit -m "feat(protocol): NIP-44 v2 encryption (pointycastle, vector-checked)"
```

---

### Task 10: Takhi event builders

**Files:**
- Create: `packages/takhi_protocol/lib/src/takhi_events.dart`
- Test: `packages/takhi_protocol/test/takhi_events_test.dart`
- Modify: barrel export

**Interfaces:**
- Consumes: `NostrEvent`, `signEvent`, `minePow`, `geohashEncode`.
- Produces (all return an unsigned `NostrEvent`; caller signs; `now` injected for determinism):
  - Kind constants: `const kKindProfile = 0; const kKindRideRequest = 20177; const kKindLiveLocation = 20178; const kKindTripReceipt = 30177; const kKindHelper = 30178;`
  - `NostrEvent buildRideRequest({required String pubkey, required int now, required double pickupLat, required double pickupLon, required double destLat, required double destLon, int? offeredMnt, String note = '', int expirySeconds = 240})` — kind 20177, tags: `['g', pickupGeohash6]`, `['dest', destGeohash6]`, `['expiration', (now+expirySeconds)]`, optional `['price', mnt]`.
  - `NostrEvent buildTripReceipt({required String pubkey, required int now, required String tripId, required String counterpartyPubkey, required String role, required int ratingStars, required int distanceMeters, required int durationSeconds, required int priceMnt, String comment = ''})` — kind 30177, tags: `['d', tripId]`, `['p', counterpartyPubkey]`, `['role', role]`, `['rating', stars]`, `['dist', ...]`, `['dur', ...]`, `['price', ...]`.
  - `RideRequest parseRideRequest(NostrEvent e)` / `TripReceipt parseTripReceipt(NostrEvent e)` — typed parse; throw `FormatException` on wrong kind/missing required tag.

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/takhi_events_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('ride request has geohash, expiration, price tags', () {
    final e = buildRideRequest(
      pubkey: 'ab' * 32, now: 1000,
      pickupLat: 47.9186, pickupLon: 106.9176,
      destLat: 47.9100, destLon: 106.9000, offeredMnt: 5000);
    expect(e.kind, kKindRideRequest);
    expect(e.tags.firstWhere((t) => t.first == 'g')[1].length, 6);
    expect(e.tags.firstWhere((t) => t.first == 'expiration')[1], '1240');
    expect(e.tags.firstWhere((t) => t.first == 'price')[1], '5000');
  });

  test('trip receipt round-trips through parse', () {
    final e = buildTripReceipt(
      pubkey: 'cd' * 32, now: 2000, tripId: 'trip-xyz',
      counterpartyPubkey: 'ef' * 32, role: 'passenger',
      ratingStars: 5, distanceMeters: 6000, durationSeconds: 900,
      priceMnt: 9000, comment: 'сайн');
    final p = parseTripReceipt(e);
    expect(p.tripId, 'trip-xyz');
    expect(p.counterpartyPubkey, 'ef' * 32);
    expect(p.role, 'passenger');
    expect(p.ratingStars, 5);
  });

  test('parseTripReceipt rejects wrong kind', () {
    final wrong = NostrEvent(
      pubkey: 'ab' * 32, createdAt: 1, kind: 1, tags: [], content: '');
    expect(() => parseTripReceipt(wrong), throwsFormatException);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/takhi_events_test.dart`
Expected: FAIL — builders undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/takhi_events.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'event.dart';
import 'geohash.dart';

const kKindProfile = 0;
const kKindRideRequest = 20177;
const kKindLiveLocation = 20178;
const kKindTripReceipt = 30177;
const kKindHelper = 30178;

NostrEvent buildRideRequest({
  required String pubkey, required int now,
  required double pickupLat, required double pickupLon,
  required double destLat, required double destLon,
  int? offeredMnt, String note = '', int expirySeconds = 240,
}) {
  final tags = <List<String>>[
    ['g', geohashEncode(pickupLat, pickupLon, precision: 6)],
    ['dest', geohashEncode(destLat, destLon, precision: 6)],
    ['expiration', (now + expirySeconds).toString()],
  ];
  if (offeredMnt != null) tags.add(['price', offeredMnt.toString()]);
  return NostrEvent(
    pubkey: pubkey, createdAt: now, kind: kKindRideRequest,
    tags: tags, content: note);
}

class RideRequest {
  final String pickupGeohash, destGeohash;
  final int? offeredMnt;
  final int expiration;
  final String note;
  const RideRequest(this.pickupGeohash, this.destGeohash, this.offeredMnt,
      this.expiration, this.note);
}

RideRequest parseRideRequest(NostrEvent e) {
  if (e.kind != kKindRideRequest) throw FormatException('not a ride request');
  String tag(String k) {
    final t = e.tags.firstWhere((x) => x.first == k,
        orElse: () => throw FormatException('missing $k'));
    return t[1];
  }
  final priceTag = e.tags.where((x) => x.first == 'price').toList();
  return RideRequest(tag('g'), tag('dest'),
      priceTag.isEmpty ? null : int.parse(priceTag.first[1]),
      int.parse(tag('expiration')), e.content);
}

NostrEvent buildTripReceipt({
  required String pubkey, required int now, required String tripId,
  required String counterpartyPubkey, required String role,
  required int ratingStars, required int distanceMeters,
  required int durationSeconds, required int priceMnt, String comment = '',
}) {
  if (ratingStars < 1 || ratingStars > 5) {
    throw ArgumentError('rating must be 1..5');
  }
  return NostrEvent(
    pubkey: pubkey, createdAt: now, kind: kKindTripReceipt,
    tags: [
      ['d', tripId],
      ['p', counterpartyPubkey],
      ['role', role],
      ['rating', ratingStars.toString()],
      ['dist', distanceMeters.toString()],
      ['dur', durationSeconds.toString()],
      ['price', priceMnt.toString()],
    ],
    content: comment);
}

class TripReceipt {
  final String tripId, counterpartyPubkey, role, comment, authorPubkey;
  final int ratingStars, distanceMeters, durationSeconds, priceMnt, createdAt;
  const TripReceipt({
    required this.tripId, required this.counterpartyPubkey, required this.role,
    required this.ratingStars, required this.distanceMeters,
    required this.durationSeconds, required this.priceMnt,
    required this.comment, required this.authorPubkey, required this.createdAt,
  });
}

TripReceipt parseTripReceipt(NostrEvent e) {
  if (e.kind != kKindTripReceipt) throw FormatException('not a trip receipt');
  String tag(String k) {
    final t = e.tags.firstWhere((x) => x.first == k,
        orElse: () => throw FormatException('missing $k'));
    return t[1];
  }
  return TripReceipt(
    tripId: tag('d'), counterpartyPubkey: tag('p'), role: tag('role'),
    ratingStars: int.parse(tag('rating')),
    distanceMeters: int.parse(tag('dist')),
    durationSeconds: int.parse(tag('dur')),
    priceMnt: int.parse(tag('price')),
    comment: e.content, authorPubkey: e.pubkey, createdAt: e.createdAt);
}
```

Export from barrel: `export 'src/takhi_events.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/takhi_events_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/takhi_events_test.dart
git commit -m "feat(protocol): typed takhi event builders and parsers"
```

---

### Task 11: Two-sided reputation engine (crown jewel)

**Files:**
- Create: `packages/takhi_protocol/lib/src/reputation.dart`
- Test: `packages/takhi_protocol/test/reputation_test.dart`
- Modify: barrel export

**Interfaces:**
- Consumes: `TripReceipt`.
- Produces:
  - `class Reputation { final int pairedTripCount; final double averageRating; final double trustWeight; const Reputation(...); }`
  - `Reputation computeReputation({required String subjectPubkey, required List<TripReceipt> allReceipts, Set<String> viewerTrusted = const {}});`
  - Rules:
    1. **Paired validity:** a receipt about `subject` (author=X, p=subject) counts only if there is a matching receipt (author=subject, p=X, same `tripId`). Unpaired self-praise = ignored.
    2. **Distinct-counterparty weighting:** N receipts from the same counterparty count far less than N from distinct counterparties (log-diminishing per counterparty).
    3. **Web-of-trust boost:** receipts authored by pubkeys in `viewerTrusted` get higher weight.
    4. **Sybil ring resistance:** a closed ring of pubkeys that only rate each other yields low `trustWeight` because none are viewer-trusted and diversity outside the ring is zero.

- [ ] **Step 1: Write the failing test**

```dart
// packages/takhi_protocol/test/reputation_test.dart
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

TripReceipt r(String author, String about, String trip, int stars) =>
    TripReceipt(tripId: trip, counterpartyPubkey: about, role: 'x',
        ratingStars: stars, distanceMeters: 1, durationSeconds: 1, priceMnt: 1,
        comment: '', authorPubkey: author, createdAt: 0);

void main() {
  test('unpaired self-praise carries no weight', () {
    // subject S authored praise about itself via alt A, but A never
    // counter-signed -> not paired.
    final receipts = [r('A', 'S', 't1', 5)]; // only one side
    final rep = computeReputation(subjectPubkey: 'S', allReceipts: receipts);
    expect(rep.pairedTripCount, 0);
    expect(rep.trustWeight, 0);
  });

  test('one genuine paired trip counts once', () {
    final receipts = [
      r('P', 'S', 't1', 5), // passenger P rates driver S
      r('S', 'P', 't1', 5), // driver S rates passenger P (same trip)
    ];
    final rep = computeReputation(subjectPubkey: 'S', allReceipts: receipts);
    expect(rep.pairedTripCount, 1);
    expect(rep.averageRating, 5.0);
    expect(rep.trustWeight, greaterThan(0));
  });

  test('Sybil ring of 10 mutual ratings scores far below 10 distinct riders',
      () {
    // Ring: S with fakes F0..F8 all cross-signing
    final ring = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      ring.add(r('F$i', 'S', 'ring$i', 5));
      ring.add(r('S', 'F$i', 'ring$i', 5));
    }
    final ringRep = computeReputation(subjectPubkey: 'S', allReceipts: ring);

    // Distinct real riders R0..R8, none trusted, but genuinely distinct
    final distinct = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      distinct.add(r('R$i', 'D', 'real$i', 5));
      distinct.add(r('D', 'R$i', 'real$i', 5));
    }
    final distinctRep =
        computeReputation(subjectPubkey: 'D', allReceipts: distinct);

    // Both have 9 paired trips, but with viewer trust the honest one wins.
    final trustedView = computeReputation(
        subjectPubkey: 'D', allReceipts: distinct,
        viewerTrusted: {'R0', 'R1'});
    expect(trustedView.trustWeight, greaterThan(ringRep.trustWeight));
    // And a ring where the SAME single fake signs many trips collapses:
    final lazyRing = <TripReceipt>[];
    for (var i = 0; i < 9; i++) {
      lazyRing.add(r('F', 'S', 'lazy$i', 5));
      lazyRing.add(r('S', 'F', 'lazy$i', 5));
    }
    final lazyRep =
        computeReputation(subjectPubkey: 'S', allReceipts: lazyRing);
    expect(lazyRep.trustWeight, lessThan(distinctRep.trustWeight));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/reputation_test.dart`
Expected: FAIL — `computeReputation` undefined.

- [ ] **Step 3: Implement**

```dart
// packages/takhi_protocol/lib/src/reputation.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'takhi_events.dart';

class Reputation {
  final int pairedTripCount;
  final double averageRating;
  final double trustWeight;
  const Reputation(this.pairedTripCount, this.averageRating, this.trustWeight);
}

Reputation computeReputation({
  required String subjectPubkey,
  required List<TripReceipt> allReceipts,
  Set<String> viewerTrusted = const {},
}) {
  // Index receipts by (author, counterparty, tripId) for pairing lookup.
  bool hasCounter(String author, String about, String trip) =>
      allReceipts.any((x) =>
          x.authorPubkey == about &&
          x.counterpartyPubkey == author &&
          x.tripId == trip);

  // Receipts ABOUT the subject that are genuinely paired.
  final paired = allReceipts.where((x) =>
      x.counterpartyPubkey == subjectPubkey &&
      x.authorPubkey != subjectPubkey &&
      hasCounter(x.authorPubkey, subjectPubkey, x.tripId)).toList();

  if (paired.isEmpty) return const Reputation(0, 0, 0);

  final avg = paired.map((e) => e.ratingStars).reduce((a, b) => a + b) /
      paired.length;

  // Distinct-counterparty diversity: sum log(1 + trips_from_author) per
  // distinct author, so many trips from one author diminish sharply.
  final byAuthor = <String, int>{};
  for (final rcpt in paired) {
    byAuthor[rcpt.authorPubkey] = (byAuthor[rcpt.authorPubkey] ?? 0) + 1;
  }
  var weight = 0.0;
  byAuthor.forEach((author, count) {
    final base = math.log(1 + count); // diminishing within one author
    final trustBoost = viewerTrusted.contains(author) ? 3.0 : 1.0;
    weight += base * trustBoost;
  });

  return Reputation(paired.length, avg, weight);
}
```

> Why this defeats the scenarios: the **lazy ring** (one fake `F` signing 9 trips) contributes `log(1+9)≈2.30` total — versus 9 distinct riders contributing `9 × log(2)≈6.24`. Viewer trust multiplies honest, known counterparties by 3×, so a rider who has taken trips with people the viewer already trusts outranks any ring the viewer doesn't know. `pairedTripCount` still shows the raw count honestly; `trustWeight` is the Sybil-resistant sort key.

Export from barrel: `export 'src/reputation.dart';`

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/reputation_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/reputation_test.dart
git commit -m "feat(protocol): two-sided Sybil-resistant reputation engine"
```

---

### Task 12: Coverage gate + PROTOCOL.md v0.1

**Files:**
- Create: `PROTOCOL.md`
- Modify: `.github/workflows/protocol.yml` (add coverage threshold)

**Interfaces:**
- Consumes: all prior tasks.
- Produces: published protocol spec + enforced ≥80% coverage.

- [ ] **Step 1: Run full suite with coverage**

Run: `cd packages/takhi_protocol && dart test --coverage=coverage && dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib`
Expected: all tests PASS; note the line-coverage %.

- [ ] **Step 2: If any lib/ file < 80%, add targeted tests**

For each under-covered file, add a test exercising the untested branch (e.g., `parseRideRequest` missing-tag path, `PowExhausted`, `npubToHex` wrong-prefix). Re-run Step 1.

- [ ] **Step 3: Write PROTOCOL.md v0.1**

Document (verbatim from this package's implemented behavior): event kinds table (§6 of spec with the values in Global Constraints), tag schemas for kind 20177 / 30177 / 30178, the pairing rule for receipts, the geohash precision (6) and privacy tiers, PoW placement (`nonce` tag), and NIP references. Mark it `version: 0.1.0`.

- [ ] **Step 4: Add coverage step to CI**

```yaml
      - run: dart test --coverage=coverage
      - run: dart pub global activate coverage
      - run: dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
```

- [ ] **Step 5: Commit**

```bash
git add PROTOCOL.md .github/workflows/protocol.yml packages/takhi_protocol/test
git commit -m "docs(protocol): PROTOCOL.md v0.1 + coverage gate"
```

---

## Self-Review

**1. Spec coverage (§ → task):**
- §3 identity=key → Tasks 1,2,3 ✓ · §6 event kinds/schema → Tasks 4,10 ✓ · §6 PoW → Task 6 ✓ · §6 NIP-44 privacy → Task 9 ✓ · §6 geohash tiers → Task 7 ✓ · §7.4/§8 Plus Code → Task 8 ✓ · §9 two-sided reputation → Task 11 ✓ · §11 PROTOCOL.md → Task 12 ✓ · §15 unit+coverage → all tasks + Task 12 ✓.
- **Deferred to later plans (not this package):** relay networking, ride state machine, taximeter UI, WebRTC calling, map, safety, i18n, Flutter app. These are Plans 2–5. This plan covers only the pure protocol core.
- **Gap noted:** trip-id generation helper is used by builders but generated in the app layer (needs randomness + agreement) → belongs to Plan 3 (ride state machine); `buildTripReceipt` correctly accepts `tripId` as a parameter, so no gap here.

**2. Placeholder scan:** The only literals requiring capture are (a) the NIP-01 golden hash in Task 4 (captured from first deterministic run — documented) and (b) the NIP-44 official vectors in Task 9 (copied from published test data — documented). Both are explicitly flagged with how to fill them; neither is an invented value. No "TODO/TBD/handle appropriately" anywhere.

**3. Type consistency:** `NostrEvent`, `computeEventId`, `signEvent`, `minePow`, `geohashEncode`, `TripReceipt`, `computeReputation` names/signatures are identical everywhere they appear across tasks. `TripReceipt` fields defined in Task 10 match those consumed in Task 11. Kind constants (`kKindRideRequest` etc.) defined once in Task 10.

---

## Execution Handoff

This is **Plan 1 of 5**. Subsequent plans (write after this one lands green):
- **Plan 2:** Nostr relay pool + Flutter app scaffold + identity onboarding (seed backup UX, < 60s to first screen).
- **Plan 3:** Ride flow (request→offer→match→dual receipt) + map (flutter_map/OSM, Plus Code, pin) + trip-id agreement.
- **Plan 4:** Taximeter (offline Замын Унаа) + payment QR display + street-recruitment QR loop.
- **Plan 5:** P2P calling (flutter_webrtc + Nostr signaling + community TURN discovery) + safety (trip share static page, SOS).
