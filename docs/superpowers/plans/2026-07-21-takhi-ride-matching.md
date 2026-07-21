# Тахь дуудлага-тохироо урсгал (Ride Matching) — Implementation Plan (Plan 3/5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full ride-matching pipeline end to end: a NIP-17/NIP-59 encrypted-DM layer in `takhi_protocol`; passenger ride-request publishing; driver geohash-scoped inbox; a reputation-ranked driver-offer channel; a passenger→driver exact-location handoff; an OSM map for picking/showing locations; and the two mode-specific screens that wire all of it together. The pipeline ends the moment the passenger has selected a driver and the driver has the exact pickup point — trip progress, the taximeter, payment, and dual receipts are Plan 4; calling and safety are Plan 5.

**Architecture:** One new protocol module (`packages/takhi_protocol/lib/src/nip17.dart`) implements the generic NIP-59 gift-wrap envelope (rumor → seal → gift wrap → unwrap) on top of Plan 1's `nip44Encrypt`/`nip44Decrypt`/`signEvent`/`verifyEvent`. Everything ride-specific — the DM payload schema, the shared send/receive transport, and the five services (request, driver inbox, offer+ranking, handoff, trip id) — lives under `app/lib/ride/` as thin, individually testable classes over Plan 2's `RelayPool`. `app/lib/map/` adds `flutter_map`/OSM widgets that the two new screens (`app/lib/ride/passenger_ride_page.dart`, `app/lib/ride/driver_inbox_page.dart`) compose. Every network-facing service is driven in tests by the same fake-socket pattern Plan 2 established for `RelayPool` — no test in this plan touches a real relay.

**Tech Stack:** Dart 3 sealed classes for the DM payload schema, `flutter_map` + `latlong2` for the map (OSM raster tiles, no paid geocoding), everything else reusing Plan 1 (`takhi_protocol`) and Plan 2 (`RelayPool`, `IdentityService`, Riverpod, ARB i18n, `go_router`) exactly as already committed. Test: `dart test` for the protocol package, `flutter test` (unit + widget) for the app.

## Global Constraints

- **SPDX header** on every new Dart file: `// SPDX-License-Identifier: AGPL-3.0-or-later`.
- **ALL user-facing text via ARB** (`app/lib/l10n/app_mn.arb` is the template/default, `app_en.arb` the translation) — no hardcoded string literals in widgets. New keys are added to both files in the same task that first uses them. The one carve-out is the OpenStreetMap tile attribution string (`© OpenStreetMap contributors`), which stays as the standard, policy-expected attribution text rather than app copy.
- **Kind constants.** Reused from Plan 1: `kKindRideRequest = 20177`, `kKindTripReceipt = 30177`. Added by this plan: `kKindSeal = 13` and `kKindGiftWrap = 1059` (the official NIP-59 values, in `takhi_protocol`) and the app-level `kRumorKindRideDm = 20179` (`app/lib/ride/ride_dm_channel.dart`) — the `kind` every takhi ride DM's inner rumor carries, distinct from any relay-published kind so it can never collide with `kKindRideRequest`/`kKindTripReceipt` even conceptually.
- **NIP-17/NIP-59 layering is strict and one-directional:** rumor (unsigned, `id` computed, never published) → seal (kind 13, signed by the real sender, NIP-44-encrypted to the recipient, empty tags) → gift wrap (kind 1059, signed by a one-time ephemeral key, NIP-44-encrypted to the recipient, `created_at` randomized into the past, the only public tag is `['p', recipient]`). Only the gift wrap is ever handed to `RelayPool.publish`.
- **Pure-logic services stay unit-testable without a relay.** The DM payload codec, the reputation-ranking function, and trip-id generation are pure (no `RelayPool` dependency) and live in their own files, separate from the thin network-glue classes that use them — mirrors Plan 1 (crypto/geohash/PoW have zero networking) and Plan 2 (`IdentityService` has zero networking).
- **Immutability.** All model classes: `final` fields, `const` constructors where possible, no in-place mutation; state transitions go through `copyWith`/`setState` with a freshly-built value, never a mutated one.
- **`NostrEvent.tags` stays defensively copied and unmodifiable** (Plan 1's `event.dart`) — nothing in this plan reaches around that by holding a separately-mutable tags reference.
- **Map = `flutter_map` + OpenStreetMap raster tiles only**, attribution widget included, no paid/closed geocoding API (spec §5 decision record — `what3words` was explicitly rejected for this reason).
- **Inherited invariants (unaffected by this plan):** no author-run server, no phone number as identity, no fee/subscription layer, identity = keypair only.

---

### Task 1: NIP-17 / NIP-59 gift-wrap encrypted-DM layer (protocol package)

**Files:**
- Create: `packages/takhi_protocol/lib/src/nip17.dart`
- Modify: `packages/takhi_protocol/lib/src/event.dart` (add `NostrEvent.fromJson` factory)
- Modify: `packages/takhi_protocol/lib/takhi_protocol.dart` (export `nip17.dart`)
- Modify: `packages/takhi_protocol/test/event_id_test.dart` (add a `fromJson`/`toJson` round-trip test)
- Test: `packages/takhi_protocol/test/nip17_test.dart`

**Interfaces:**
- Consumes (all from Plan 1, already committed): `NostrEvent`, `computeEventId`, `KeyPair`, `generateKeyPair([List<int>?])`, `pubkeyFromPrivate(String)`, `signEvent(NostrEvent, String, {List<int>? auxRand})`, `verifyEvent(NostrEvent)`, `nip44Encrypt(String, String, String, {List<int>? nonce32})`, `nip44Decrypt(String, String, String)`.
- Produces: `NostrEvent.fromJson(Map<String, dynamic>)`; `kKindSeal = 13`; `kKindGiftWrap = 1059`; `kGiftWrapRandomizationWindowSeconds`; `buildRumor({pubkey, createdAt, kind, tags, content}) -> NostrEvent`; `sealRumor(NostrEvent rumor, String senderPrivHex, String recipientPubHex, {required int now, List<int>? nonce32, List<int>? auxRand}) -> NostrEvent`; `giftWrap(NostrEvent seal, String recipientPubHex, {required int randomizedCreatedAt, required KeyPair ephemeralKeyPair, List<int>? nonce32, List<int>? auxRand}) -> NostrEvent`; `randomTimestamp(int now) -> int`; `nip17Wrap({required senderPrivHex, required recipientPubHex, required rumorKind, rumorTags, required content, required now, ephemeralKeyPair, wrapCreatedAt, sealNonce32, sealAuxRand, wrapNonce32, wrapAuxRand}) -> NostrEvent`; `class UnwrappedDm { final NostrEvent rumor; final String senderPubkey; }`; `nip17Unwrap(NostrEvent wrap, String recipientPrivHex) -> UnwrappedDm` (throws `FormatException` on wrong kind / bad seal signature / sender-pubkey mismatch; throws the underlying `Exception` from `nip44Decrypt` if the wrap can't be decrypted with this key at all).

- [ ] **Step 1: Write the failing tests**

```dart
// packages/takhi_protocol/test/event_id_test.dart -- append inside main()
  test('fromJson reconstructs an event produced by toJson', () {
    final e = NostrEvent(
      id: 'deadbeef',
      pubkey: List.filled(32, 'ab').join(),
      createdAt: 123,
      kind: 1,
      tags: [
        ['g', 'u9huf6']
      ],
      content: 'hello',
      sig: 'feedface',
    );
    final roundTripped = NostrEvent.fromJson(e.toJson());
    expect(roundTripped.id, e.id);
    expect(roundTripped.pubkey, e.pubkey);
    expect(roundTripped.createdAt, e.createdAt);
    expect(roundTripped.kind, e.kind);
    expect(roundTripped.tags, e.tags);
    expect(roundTripped.content, e.content);
    expect(roundTripped.sig, e.sig);
  });
```

```dart
// packages/takhi_protocol/test/nip17_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  final sender = generateKeyPair(List<int>.filled(32, 41));
  final recipient = generateKeyPair(List<int>.filled(32, 42));
  final ephemeral = generateKeyPair(List<int>.filled(32, 43));
  final eve = generateKeyPair(List<int>.filled(32, 44));

  NostrEvent wrapForRecipient() => nip17Wrap(
        senderPrivHex: sender.privateHex,
        recipientPubHex: recipient.publicHex,
        rumorKind: 14,
        content: 'Санал: 5000₮, 4 минутад ирнэ',
        now: 1700000000,
        ephemeralKeyPair: ephemeral,
        wrapCreatedAt: 1699950000,
        sealNonce32: List<int>.filled(32, 1),
        sealAuxRand: List<int>.filled(32, 2),
        wrapNonce32: List<int>.filled(32, 3),
        wrapAuxRand: List<int>.filled(32, 4),
      );

  test('wrap hides the real sender and content behind an ephemeral key', () {
    final wrap = wrapForRecipient();
    expect(wrap.kind, kKindGiftWrap);
    expect(wrap.pubkey, ephemeral.publicHex);
    expect(wrap.pubkey, isNot(sender.publicHex));
    expect(wrap.tags, [
      ['p', recipient.publicHex]
    ]);
    expect(wrap.content.contains('5000'), isFalse);
  });

  test('unwrap recovers the rumor and the real sender', () {
    final wrap = wrapForRecipient();
    final unwrapped = nip17Unwrap(wrap, recipient.privateHex);
    expect(unwrapped.senderPubkey, sender.publicHex);
    expect(unwrapped.rumor.kind, 14);
    expect(unwrapped.rumor.content, 'Санал: 5000₮, 4 минутад ирнэ');
    expect(unwrapped.rumor.pubkey, sender.publicHex);
    expect(unwrapped.rumor.sig, isNull);
  });

  test('someone other than the tagged recipient cannot unwrap', () {
    final wrap = wrapForRecipient();
    expect(() => nip17Unwrap(wrap, eve.privateHex), throwsException);
  });

  test(
      'rejects a forged wrap whose inner rumor pubkey does not match the '
      'seal signer (spoofed sender)', () {
    // Mallory seals a rumor that CLAIMS to be from the victim, but signs
    // the seal with her own key -- nip17Unwrap must catch the mismatch
    // rather than trusting the rumor's self-reported pubkey.
    final mallory = generateKeyPair(List<int>.filled(32, 45));
    final victim = generateKeyPair(List<int>.filled(32, 46));
    final forgedRumor = buildRumor(
      pubkey: victim.publicHex,
      createdAt: 1,
      kind: 14,
      content: 'жинхэнэ биш',
    );
    final sealedByMallory = sealRumor(
      forgedRumor,
      mallory.privateHex,
      recipient.publicHex,
      now: 1,
      nonce32: List<int>.filled(32, 5),
      auxRand: List<int>.filled(32, 6),
    );
    final forgedWrap = giftWrap(
      sealedByMallory,
      recipient.publicHex,
      randomizedCreatedAt: 1,
      ephemeralKeyPair: ephemeral,
      nonce32: List<int>.filled(32, 7),
      auxRand: List<int>.filled(32, 8),
    );
    expect(() => nip17Unwrap(forgedWrap, recipient.privateHex),
        throwsFormatException);
  });

  test(
      'wrapCreatedAt defaults to a randomized past timestamp within the '
      'window when omitted', () {
    final wrap = nip17Wrap(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      rumorKind: 14,
      content: 'x',
      now: 2000000000,
      ephemeralKeyPair: ephemeral,
      sealNonce32: List<int>.filled(32, 1),
      sealAuxRand: List<int>.filled(32, 2),
      wrapNonce32: List<int>.filled(32, 3),
      wrapAuxRand: List<int>.filled(32, 4),
    );
    expect(wrap.createdAt, lessThanOrEqualTo(2000000000));
    expect(
        wrap.createdAt,
        greaterThanOrEqualTo(
            2000000000 - kGiftWrapRandomizationWindowSeconds));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/takhi_protocol && dart test test/event_id_test.dart test/nip17_test.dart`
Expected: FAIL — `NostrEvent.fromJson` and every `nip17*`/`kKindSeal`/`kKindGiftWrap` symbol undefined.

- [ ] **Step 3: Add `NostrEvent.fromJson` to `event.dart`**

Add this factory to the `NostrEvent` class in `packages/takhi_protocol/lib/src/event.dart` (after `toJson`):

```dart
  /// Reconstructs a [NostrEvent] from the NIP-01 JSON shape produced by
  /// [toJson] (or received from a relay). Used when an event is embedded
  /// inside another event's content -- e.g. NIP-59 seals/gift wraps -- and
  /// needs to be parsed back out after NIP-44 decryption.
  factory NostrEvent.fromJson(Map<String, dynamic> json) => NostrEvent(
        id: json['id'] as String?,
        pubkey: json['pubkey'] as String,
        createdAt: json['created_at'] as int,
        kind: json['kind'] as int,
        tags: (json['tags'] as List<dynamic>)
            .map((t) =>
                (t as List<dynamic>).map((x) => x as String).toList())
            .toList(),
        content: json['content'] as String,
        sig: json['sig'] as String?,
      );
```

- [ ] **Step 4: Implement `nip17.dart`**

```dart
// packages/takhi_protocol/lib/src/nip17.dart
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
  return signEvent(unsignedWrap, ephemeralKeyPair.privateHex,
      auxRand: auxRand);
}

/// A timestamp randomized into the past within
/// [kGiftWrapRandomizationWindowSeconds] of [now], per NIP-59 guidance.
int randomTimestamp(int now) => now -
    math.Random.secure().nextInt(kGiftWrapRandomizationWindowSeconds + 1);

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
  final rumorJson =
      nip44Decrypt(seal.content, recipientPrivHex, seal.pubkey);
  final rumor =
      NostrEvent.fromJson(jsonDecode(rumorJson) as Map<String, dynamic>);
  if (rumor.pubkey != seal.pubkey) {
    throw FormatException(
        "rumor pubkey does not match the seal's signer (spoofed sender)");
  }
  return UnwrappedDm(rumor, seal.pubkey);
}
```

Export from the barrel:

```dart
// packages/takhi_protocol/lib/takhi_protocol.dart -- add alongside the
// existing exports
export 'src/nip17.dart';
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd packages/takhi_protocol && dart test test/event_id_test.dart test/nip17_test.dart`
Expected: PASS (7 new tests total across both files).

- [ ] **Step 6: Commit**

```bash
git add packages/takhi_protocol/lib packages/takhi_protocol/test/nip17_test.dart packages/takhi_protocol/test/event_id_test.dart
git commit -m "feat(protocol): NIP-17/NIP-59 gift-wrap encrypted DM layer"
```

---

### Task 2: Ride DM payload codec (app)

**Files:**
- Create: `app/lib/ride/ride_dm_payload.dart`
- Test: `app/test/ride/ride_dm_payload_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart, `dart:convert` only).
- Produces:
  - `sealed class RideDmPayload { const RideDmPayload(); String encode(); static RideDmPayload decode(String json); }`
  - `final class RideOfferPayload extends RideDmPayload { final String rideRequestId; final int priceMnt; final int etaMinutes; final String vehicleDescription; const RideOfferPayload({required rideRequestId, required priceMnt, required etaMinutes, required vehicleDescription}); }`
  - `final class RideHandoffPayload extends RideDmPayload { final String rideRequestId; final String tripId; final double lat; final double lon; final String plusCode; final String landmarkText; const RideHandoffPayload({...}); }`
  - `final class RideCancelPayload extends RideDmPayload { final String rideRequestId; final String reason; const RideCancelPayload({required rideRequestId, reason = ''}); }`

This is the JSON schema carried as every ride DM rumor's `content` (spec §6 rows "Санал / тохиролцоо", "Тохироо + яг байршил", "Цуцлалт" — all NIP-17 DM, sharing one encrypted channel with a `type` discriminator instead of three separate rumor kinds). `RideOfferPayload` deliberately does **not** carry a driver npub field: the driver's identity is always the cryptographically verified `UnwrappedDm.senderPubkey` from `nip17Unwrap` (Task 1), never a self-reported field inside the payload — a self-reported identity field would be a spoofing vector `nip17Unwrap` already exists to prevent.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/ride/ride_dm_payload_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/ride_dm_payload.dart';

void main() {
  test('offer payload round-trips through encode/decode', () {
    const offer = RideOfferPayload(
      rideRequestId: 'req1',
      priceMnt: 5000,
      etaMinutes: 4,
      vehicleDescription: 'цагаан Prius, 1234УНА',
    );
    final decoded = RideDmPayload.decode(offer.encode()) as RideOfferPayload;
    expect(decoded.rideRequestId, 'req1');
    expect(decoded.priceMnt, 5000);
    expect(decoded.etaMinutes, 4);
    expect(decoded.vehicleDescription, 'цагаан Prius, 1234УНА');
  });

  test('handoff payload round-trips through encode/decode', () {
    const handoff = RideHandoffPayload(
      rideRequestId: 'req1',
      tripId: 'trip-abc',
      lat: 47.9186,
      lon: 106.9176,
      plusCode: '8Q7XJP2Q+2Q',
      landmarkText: 'Сүхбаатарын талбайн урд, цагаан хаалга',
    );
    final decoded =
        RideDmPayload.decode(handoff.encode()) as RideHandoffPayload;
    expect(decoded.rideRequestId, 'req1');
    expect(decoded.tripId, 'trip-abc');
    expect(decoded.lat, 47.9186);
    expect(decoded.lon, 106.9176);
    expect(decoded.plusCode, '8Q7XJP2Q+2Q');
    expect(decoded.landmarkText, 'Сүхбаатарын талбайн урд, цагаан хаалга');
  });

  test('cancel payload round-trips and defaults reason to empty', () {
    const cancel = RideCancelPayload(rideRequestId: 'req1');
    final decoded =
        RideDmPayload.decode(cancel.encode()) as RideCancelPayload;
    expect(decoded.rideRequestId, 'req1');
    expect(decoded.reason, '');
  });

  test('decode throws FormatException for an unrecognized type', () {
    expect(() => RideDmPayload.decode('{"type":"mystery"}'),
        throwsFormatException);
  });

  test('decode throws FormatException for malformed JSON', () {
    expect(() => RideDmPayload.decode('not json'), throwsFormatException);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/ride/ride_dm_payload_test.dart`
Expected: FAIL — `package:takhi/ride/ride_dm_payload.dart` not found.

- [ ] **Step 3: Implement**

```dart
// app/lib/ride/ride_dm_payload.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

/// The structured content carried inside a NIP-17 rumor for every private
/// ride message (spec §6: offer/agreement, handoff, and cancellation all
/// share the encrypted-DM channel; this is the JSON schema for that
/// channel's `content`). [encode] is what goes into `nip17Wrap`'s
/// `content:`; [RideDmPayload.decode] is what a rumor's content is parsed
/// back into after `nip17Unwrap`.
sealed class RideDmPayload {
  const RideDmPayload();

  String encode() => jsonEncode(toJson());
  Map<String, dynamic> toJson();

  /// Parses a rumor's `content` back into a typed payload. Throws
  /// [FormatException] for malformed JSON or an unrecognized `type`.
  static RideDmPayload decode(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return switch (map['type']) {
      'offer' => RideOfferPayload._fromJson(map),
      'handoff' => RideHandoffPayload._fromJson(map),
      'cancel' => RideCancelPayload._fromJson(map),
      final other => throw FormatException(
          'unknown ride DM payload type: $other'),
    };
  }
}

/// A driver's offer on a ride request: proposed price, ETA, and a short
/// vehicle description (spec §6 "Санал / тохиролцоо", §7.1 step 3).
/// [rideRequestId] correlates the offer back to the `NostrEvent.id` of the
/// public kind-20177 request it answers -- a field the spec's summary
/// table leaves implicit but the DM payload must carry explicitly.
final class RideOfferPayload extends RideDmPayload {
  final String rideRequestId;
  final int priceMnt;
  final int etaMinutes;
  final String vehicleDescription;

  const RideOfferPayload({
    required this.rideRequestId,
    required this.priceMnt,
    required this.etaMinutes,
    required this.vehicleDescription,
  });

  factory RideOfferPayload._fromJson(Map<String, dynamic> map) =>
      RideOfferPayload(
        rideRequestId: map['rideRequestId'] as String,
        priceMnt: map['priceMnt'] as int,
        etaMinutes: map['etaMinutes'] as int,
        vehicleDescription: map['vehicleDescription'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'offer',
        'rideRequestId': rideRequestId,
        'priceMnt': priceMnt,
        'etaMinutes': etaMinutes,
        'vehicleDescription': vehicleDescription,
      };
}

/// The passenger's exact pickup handoff to the driver they selected: only
/// ever sent to that one driver (spec §6 "Тохироо + яг байршил", §9
/// privacy tiering -- the exact point is never public).
final class RideHandoffPayload extends RideDmPayload {
  final String rideRequestId;
  final String tripId;
  final double lat;
  final double lon;
  final String plusCode;
  final String landmarkText;

  const RideHandoffPayload({
    required this.rideRequestId,
    required this.tripId,
    required this.lat,
    required this.lon,
    required this.plusCode,
    required this.landmarkText,
  });

  factory RideHandoffPayload._fromJson(Map<String, dynamic> map) =>
      RideHandoffPayload(
        rideRequestId: map['rideRequestId'] as String,
        tripId: map['tripId'] as String,
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
        plusCode: map['plusCode'] as String,
        landmarkText: map['landmarkText'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'handoff',
        'rideRequestId': rideRequestId,
        'tripId': tripId,
        'lat': lat,
        'lon': lon,
        'plusCode': plusCode,
        'landmarkText': landmarkText,
      };
}

/// Either side backing out before the trip starts (spec §7.5).
final class RideCancelPayload extends RideDmPayload {
  final String rideRequestId;
  final String reason;

  const RideCancelPayload({required this.rideRequestId, this.reason = ''});

  factory RideCancelPayload._fromJson(Map<String, dynamic> map) =>
      RideCancelPayload(
        rideRequestId: map['rideRequestId'] as String,
        reason: map['reason'] as String? ?? '',
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'cancel',
        'rideRequestId': rideRequestId,
        'reason': reason,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/ride/ride_dm_payload_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/ride/ride_dm_payload.dart app/test/ride/ride_dm_payload_test.dart
git commit -m "feat(app): ride DM payload codec (offer/handoff/cancel)"
```

---

### Task 3: `RideDmChannel` — shared NIP-17 send/inbox transport

**Files:**
- Create: `app/lib/ride/ride_dm_channel.dart`
- Create: `app/test/support/fake_relay_socket.dart`
- Test: `app/test/ride/ride_dm_channel_test.dart`

**Interfaces:**
- Consumes: `RelayPool`, `RelayFilter`, `RelaySocket` (`app/lib/nostr/relay_pool.dart`, Plan 2); `nip17Wrap`, `nip17Unwrap`, `kKindGiftWrap`, `NostrEvent` (Task 1); `RideDmPayload` (Task 2).
- Produces:
  - `const int kRumorKindRideDm = 20179;`
  - `class InboundRideDm { final String senderPubkey; final RideDmPayload payload; final int wrapReceivedAt; const InboundRideDm(...); }`
  - `class RideDmChannel { RideDmChannel(RelayPool pool); Future<NostrEvent> send({required senderPrivHex, required recipientPubHex, required RideDmPayload payload, required int now}); Stream<InboundRideDm> inbox(String myPubHex, String myPrivHex); }`
  - `class FakeRelaySocket implements RelaySocket` (test support, in `app/test/support/fake_relay_socket.dart`) — every later task's tests import this instead of redefining it.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/support/fake_relay_socket.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:takhi/nostr/relay_pool.dart';

/// Shared no-network [RelaySocket] test double, reused by every Plan 3
/// service test that drives a [RelayPool] through `connect:`. Mirrors the
/// fake originally written inline in `relay_pool_test.dart` (Plan 2) --
/// pulled out here so Plan 3's several new relay-backed services don't
/// each hand-roll their own copy (DRY).
class FakeRelaySocket implements RelaySocket {
  final _controller = StreamController<String>.broadcast();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }

  @override
  Future<void> get ready => Future<void>.value();

  /// Delivers a raw relay frame (already JSON-encoded) to every listener,
  /// as if it arrived over the wire.
  void emit(String frame) => _controller.add(frame);
}
```

```dart
// app/test/ride/ride_dm_channel_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final alice = generateKeyPair(List<int>.filled(32, 51));
  final bob = generateKeyPair(List<int>.filled(32, 52));

  test('send publishes a gift wrap tagged to the recipient', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = RideDmChannel(pool);

    const payload = RideCancelPayload(rideRequestId: 'req1', reason: 'test');
    final wrap = await channel.send(
      senderPrivHex: alice.privateHex,
      recipientPubHex: bob.publicHex,
      payload: payload,
      now: 1700000000,
    );

    expect(wrap.kind, kKindGiftWrap);
    expect(wrap.tags, [
      ['p', bob.publicHex]
    ]);
    final sentFrame =
        jsonDecode(sockets['wss://a']!.sent.single) as List<dynamic>;
    expect(sentFrame[0], 'EVENT');
  });

  test('inbox decrypts and decodes wraps addressed to me', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = RideDmChannel(pool);

    const payload = RideOfferPayload(
        rideRequestId: 'req1',
        priceMnt: 5000,
        etaMinutes: 4,
        vehicleDescription: 'Prius');
    final wrap = await channel.send(
      senderPrivHex: alice.privateHex,
      recipientPubHex: bob.publicHex,
      payload: payload,
      now: 1700000000,
    );

    final got = <InboundRideDm>[];
    final sub = channel.inbox(bob.publicHex, bob.privateHex).listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, wrap.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, alice.publicHex);
    expect(got.first.payload, isA<RideOfferPayload>());
    expect((got.first.payload as RideOfferPayload).priceMnt, 5000);
    await sub.cancel();
  });

  test('inbox silently drops wraps addressed to someone else, even if a '
      'misbehaving relay forwards them anyway', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = RideDmChannel(pool);
    final eve = generateKeyPair(List<int>.filled(32, 53));

    const payload = RideCancelPayload(rideRequestId: 'req1');
    final wrapForEve = await channel.send(
      senderPrivHex: alice.privateHex,
      recipientPubHex: eve.publicHex,
      payload: payload,
      now: 1700000000,
    );

    final got = <InboundRideDm>[];
    final sub = channel.inbox(bob.publicHex, bob.privateHex).listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', subId, wrapForEve.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got, isEmpty);
    await sub.cancel();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/ride/ride_dm_channel_test.dart`
Expected: FAIL — `package:takhi/ride/ride_dm_channel.dart` not found.

- [ ] **Step 3: Implement**

```dart
// app/lib/ride/ride_dm_channel.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';
import 'ride_dm_payload.dart';

/// The rumor kind used for every takhi ride DM. Distinct from any kind
/// this app ever publishes directly to a relay (`kKindRideRequest`,
/// `kKindTripReceipt`, ...) -- a rumor's kind lives only inside the
/// encrypted gift-wrap content, never on the wire by itself, but keeping
/// the numbers disjoint avoids confusing a future PROTOCOL.md reader.
const int kRumorKindRideDm = 20179;

/// A private takhi message a caller received: the sender's real pubkey
/// (recovered and verified by `nip17Unwrap`, spec §6 privacy tiering) and
/// the decoded [RideDmPayload].
class InboundRideDm {
  final String senderPubkey;
  final RideDmPayload payload;
  final int wrapReceivedAt;
  const InboundRideDm(this.senderPubkey, this.payload, this.wrapReceivedAt);
}

/// Sends and receives NIP-17 gift-wrapped [RideDmPayload] messages over a
/// [RelayPool] -- the shared transport behind ride offers (Task 6),
/// handoffs (Task 7), and cancellations (Task 4). Kept separate from the
/// payload codec (`ride_dm_payload.dart`) and from the pure ranking/state
/// logic built on top of it, so each piece stays independently testable.
class RideDmChannel {
  final RelayPool _pool;
  RideDmChannel(this._pool);

  /// Wraps [payload] for [recipientPubHex] and publishes it. Returns the
  /// gift wrap event actually sent (its own `id`/timestamp carry no
  /// meaning to the recipient -- only the decrypted rumor does).
  Future<NostrEvent> send({
    required String senderPrivHex,
    required String recipientPubHex,
    required RideDmPayload payload,
    required int now,
  }) async {
    final wrap = nip17Wrap(
      senderPrivHex: senderPrivHex,
      recipientPubHex: recipientPubHex,
      rumorKind: kRumorKindRideDm,
      content: payload.encode(),
      now: now,
    );
    await _pool.publish(wrap);
    return wrap;
  }

  /// Subscribes to every gift wrap tagged for [myPubHex] and yields each
  /// one that successfully unwraps and decodes with [myPrivHex]. A wrap
  /// that fails to decrypt (addressed to someone else, forwarded anyway
  /// by a misbehaving relay) or fails to decode (a malformed or future,
  /// unrecognized payload) is dropped rather than surfaced -- this is a
  /// routing-layer stream, not a place to report malformed/foreign
  /// traffic to the UI.
  Stream<InboundRideDm> inbox(String myPubHex, String myPrivHex) {
    final filter = RelayFilter(
      kinds: [kKindGiftWrap],
      tagFilters: {
        '#p': [myPubHex],
      },
    );
    return _pool.subscribe(filter).asyncExpand((wrap) async* {
      try {
        final unwrapped = nip17Unwrap(wrap, myPrivHex);
        if (unwrapped.rumor.kind != kRumorKindRideDm) return;
        final payload = RideDmPayload.decode(unwrapped.rumor.content);
        yield InboundRideDm(unwrapped.senderPubkey, payload, wrap.createdAt);
      } on Exception {
        // Not decryptable with our key, or malformed/foreign content;
        // drop rather than surfacing it as an error.
      }
    });
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/ride/ride_dm_channel_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/ride/ride_dm_channel.dart app/test/support/fake_relay_socket.dart app/test/ride/ride_dm_channel_test.dart
git commit -m "feat(app): shared NIP-17 ride DM channel (send + inbox)"
```

---

### Task 4: `RideRequestService` — publish & cancel a ride request

**Files:**
- Create: `app/lib/ride/ride_request_service.dart`
- Test: `app/test/ride/ride_request_service_test.dart`

**Interfaces:**
- Consumes: `RelayPool` (Plan 2); `buildRideRequest`, `minePow`, `signEvent`, `pubkeyFromPrivate`, `parseRideRequest`, `verifyEvent`, `countLeadingZeroBits`, `kKindRideRequest` (Plan 1); `RideDmChannel`, `RideCancelPayload` (Tasks 2-3).
- Produces:
  - `const int kRideRequestPowDifficulty = 8;`
  - `class RideRequestService { RideRequestService(RelayPool pool, RideDmChannel dm); Future<NostrEvent> publishRequest({required privHex, required now, required pickupLat, required pickupLon, required destLat, required destLon, offeredMnt, note = '', expirySeconds = 240, powDifficulty = kRideRequestPowDifficulty}); Future<void> cancelWithDriver({required privHex, required driverPubHex, required rideRequestId, required now, reason = ''}); }`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/ride/ride_request_service_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/ride_request_service.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final passenger = generateKeyPair(List<int>.filled(32, 61));
  final driver = generateKeyPair(List<int>.filled(32, 62));

  test('publishRequest publishes a PoW-mined, signed ride request',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = RideRequestService(pool, RideDmChannel(pool));

    final event = await service.publishRequest(
      privHex: passenger.privateHex,
      now: 1000,
      pickupLat: 47.9186,
      pickupLon: 106.9176,
      destLat: 47.9100,
      destLon: 106.9000,
      offeredMnt: 5000,
      powDifficulty: 4, // small so the test stays fast
    );

    expect(event.kind, kKindRideRequest);
    expect(event.pubkey, passenger.publicHex);
    expect(event.sig, isNotNull);
    expect(verifyEvent(event), isTrue);
    expect(countLeadingZeroBits(event.id!), greaterThanOrEqualTo(4));
    expect(parseRideRequest(event).offeredMnt, 5000);

    final sentFrame =
        jsonDecode(sockets['wss://a']!.sent.single) as List<dynamic>;
    expect(sentFrame[0], 'EVENT');
    expect((sentFrame[1] as Map<String, dynamic>)['kind'], kKindRideRequest);
  });

  test('cancelWithDriver sends a cancel DM to exactly that driver',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final dm = RideDmChannel(pool);
    final service = RideRequestService(pool, dm);

    final got = <InboundRideDm>[];
    final sub =
        dm.inbox(driver.publicHex, driver.privateHex).listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await service.cancelWithDriver(
      privHex: passenger.privateHex,
      driverPubHex: driver.publicHex,
      rideRequestId: 'req1',
      now: 1000,
      reason: 'олдлоо',
    );
    // The publish above went to the same fake socket; replay it to the
    // subscriber exactly as a relay would echo a matching event back.
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, passenger.publicHex);
    expect(got.first.payload, isA<RideCancelPayload>());
    expect((got.first.payload as RideCancelPayload).reason, 'олдлоо');
    await sub.cancel();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/ride/ride_request_service_test.dart`
Expected: FAIL — `package:takhi/ride/ride_request_service.dart` not found.

- [ ] **Step 3: Implement**

```dart
// app/lib/ride/ride_request_service.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';
import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';

/// Default NIP-13 proof-of-work difficulty for a published ride request
/// (spec §6: "NIP-13 PoW" on kind 20177) -- mines in well under a second
/// on a phone, but makes flooding the relay network with junk requests
/// non-free. The final value is an open protocol question (spec §16.3);
/// this is the working MVP default, matching the difficulty Plan 1's own
/// `minePow` test calls "trivially fast".
const int kRideRequestPowDifficulty = 8;

/// Publishes a passenger's ride request (spec §7.1 step 1: pick points,
/// optional price, publish with PoW and a 4-minute expiry) and lets the
/// passenger cancel with a specific driver they've already been offered
/// by (spec §7.5 -- cancellation is a DM to whichever driver(s) were
/// engaged; the public request itself is ephemeral and simply expires).
class RideRequestService {
  final RelayPool _pool;
  final RideDmChannel _dm;

  RideRequestService(this._pool, this._dm);

  /// Builds, mines PoW for, signs, and publishes a ride request. Returns
  /// the signed event -- its `id` is the ride request id offers and the
  /// eventual handoff reference.
  Future<NostrEvent> publishRequest({
    required String privHex,
    required int now,
    required double pickupLat,
    required double pickupLon,
    required double destLat,
    required double destLon,
    int? offeredMnt,
    String note = '',
    int expirySeconds = 240,
    int powDifficulty = kRideRequestPowDifficulty,
  }) async {
    final pubHex = pubkeyFromPrivate(privHex);
    final unsigned = buildRideRequest(
      pubkey: pubHex,
      now: now,
      pickupLat: pickupLat,
      pickupLon: pickupLon,
      destLat: destLat,
      destLon: destLon,
      offeredMnt: offeredMnt,
      note: note,
      expirySeconds: expirySeconds,
    );
    final mined = minePow(unsigned, powDifficulty);
    final signed = signEvent(mined, privHex);
    await _pool.publish(signed);
    return signed;
  }

  /// Tells one driver the passenger is backing out of a request they'd
  /// offered on (spec §7.5).
  Future<void> cancelWithDriver({
    required String privHex,
    required String driverPubHex,
    required String rideRequestId,
    required int now,
    String reason = '',
  }) async {
    await _dm.send(
      senderPrivHex: privHex,
      recipientPubHex: driverPubHex,
      payload:
          RideCancelPayload(rideRequestId: rideRequestId, reason: reason),
      now: now,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/ride/ride_request_service_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/ride/ride_request_service.dart app/test/ride/ride_request_service_test.dart
git commit -m "feat(app): ride request publish + driver cancellation"
```

---

### Task 5: `DriverInboxService` — nearby public ride requests

**Files:**
- Create: `app/lib/ride/driver_inbox_service.dart`
- Test: `app/test/ride/driver_inbox_service_test.dart`

**Interfaces:**
- Consumes: `RelayPool`, `RelayFilter` (Plan 2); `geohashEncode`, `geohashNeighbors`, `parseRideRequest`, `RideRequest`, `kKindRideRequest`, `NostrEvent`, `buildRideRequest`, `signEvent`, `generateKeyPair` (Plan 1).
- Produces:
  - `class RideRequestListing { final NostrEvent event; final RideRequest request; const RideRequestListing(...); String get rideRequestId; bool isExpired(int nowSeconds); }`
  - `class DriverInboxService { DriverInboxService(RelayPool pool); Stream<RideRequestListing> nearbyRequests({required driverLat, required driverLon, required int Function() nowSeconds}); }`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/ride/driver_inbox_service_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/driver_inbox_service.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

NostrEvent _signedRequest({
  required KeyPair kp,
  required int now,
  required double pickupLat,
  required double pickupLon,
  int expirySeconds = 240,
}) {
  final unsigned = buildRideRequest(
    pubkey: kp.publicHex,
    now: now,
    pickupLat: pickupLat,
    pickupLon: pickupLon,
    destLat: pickupLat,
    destLon: pickupLon,
    expirySeconds: expirySeconds,
  );
  return signEvent(unsigned, kp.privateHex, auxRand: List<int>.filled(32, 0));
}

void main() {
  // Sukhbaatar Square, Ulaanbaatar.
  const driverLat = 47.9186, driverLon = 106.9176;

  test("subscribes on the driver's own geohash cell plus its 8 neighbors",
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = DriverInboxService(pool);

    service.nearbyRequests(
        driverLat: driverLat, driverLon: driverLon, nowSeconds: () => 0);
    final reqFrame =
        jsonDecode(sockets['wss://a']!.sent.single) as List<dynamic>;
    final filterJson = reqFrame[2] as Map<String, dynamic>;
    final cells = (filterJson['#g'] as List<dynamic>).cast<String>();
    expect(cells.length, 9); // own cell + 8 neighbors
    expect(
        cells.contains(geohashEncode(driverLat, driverLon, precision: 6)),
        isTrue);
  });

  test('yields a parsed, unexpired ride request', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = DriverInboxService(pool);
    final passenger = generateKeyPair(List<int>.filled(32, 71));

    final got = <RideRequestListing>[];
    final sub = service
        .nearbyRequests(
            driverLat: driverLat, driverLon: driverLon, nowSeconds: () => 1100)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    final event = _signedRequest(
        kp: passenger, now: 1000, pickupLat: driverLat, pickupLon: driverLon);
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, event.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.rideRequestId, event.id);
    expect(got.first.request.pickupGeohash,
        geohashEncode(driverLat, driverLon, precision: 6));
    await sub.cancel();
  });

  test("drops a request whose NIP-40 expiration has already passed",
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = DriverInboxService(pool);
    final passenger = generateKeyPair(List<int>.filled(32, 72));

    final got = <RideRequestListing>[];
    // now (9999) is well past now(1000)+expirySeconds(240)=1240.
    final sub = service
        .nearbyRequests(
            driverLat: driverLat, driverLon: driverLon, nowSeconds: () => 9999)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    final event = _signedRequest(
        kp: passenger, now: 1000, pickupLat: driverLat, pickupLon: driverLon);
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, event.toJson()]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got, isEmpty);
    await sub.cancel();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/ride/driver_inbox_service_test.dart`
Expected: FAIL — `package:takhi/ride/driver_inbox_service.dart` not found.

- [ ] **Step 3: Implement**

```dart
// app/lib/ride/driver_inbox_service.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';

/// A public ride request as seen by a nearby driver: the parsed protocol
/// fields plus the raw event (its `id` is the ride request id offers and
/// handoffs reference) and a freshness check against the driver's clock.
class RideRequestListing {
  final NostrEvent event;
  final RideRequest request;
  const RideRequestListing(this.event, this.request);

  /// Always non-null: [RelayPool.subscribe] never dispatches an event
  /// with a null `id`.
  String get rideRequestId => event.id!;

  bool isExpired(int nowSeconds) => nowSeconds >= request.expiration;
}

/// Subscribes a driver to public ride requests near their own location
/// (spec §5 "geohash шошгоор", §7.1 step 2). A driver listens on their
/// own geohash-6 cell plus its 8 neighbors (via [geohashNeighbors]) so a
/// passenger just across a cell boundary is still visible.
class DriverInboxService {
  final RelayPool _pool;
  DriverInboxService(this._pool);

  /// [nowSeconds] is injected (rather than read from a wall clock inside
  /// this class) so expiry filtering is deterministic in tests; app call
  /// sites pass `() => DateTime.now().millisecondsSinceEpoch ~/ 1000`.
  Stream<RideRequestListing> nearbyRequests({
    required double driverLat,
    required double driverLon,
    required int Function() nowSeconds,
  }) {
    final myCell = geohashEncode(driverLat, driverLon, precision: 6);
    final cells = [myCell, ...geohashNeighbors(myCell)];
    final filter = RelayFilter(
      kinds: [kKindRideRequest],
      tagFilters: {'#g': cells},
    );
    return _pool
        .subscribe(filter)
        .map(_tryParse)
        .where((listing) =>
            listing != null && !listing.isExpired(nowSeconds()))
        .cast<RideRequestListing>();
  }

  static RideRequestListing? _tryParse(NostrEvent event) {
    try {
      return RideRequestListing(event, parseRideRequest(event));
    } on FormatException {
      return null;
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/ride/driver_inbox_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/ride/driver_inbox_service.dart app/test/ride/driver_inbox_service_test.dart
git commit -m "feat(app): driver inbox for nearby public ride requests"
```

---

### Task 6: Offer channel + reputation-ranked selection

**Files:**
- Create: `app/lib/ride/offer_service.dart`
- Create: `app/lib/ride/offer_ranking.dart`
- Create: `app/lib/ride/trip_receipt_repository.dart`
- Test: `app/test/ride/offer_service_test.dart`
- Test: `app/test/ride/offer_ranking_test.dart`
- Test: `app/test/ride/trip_receipt_repository_test.dart`

**Interfaces:**
- Consumes: `RideDmChannel`, `RideOfferPayload`, `InboundRideDm` (Tasks 2-3); `RelayPool`, `RelayFilter` (Plan 2); `computeReputation`, `Reputation`, `TripReceipt`, `parseTripReceipt`, `kKindTripReceipt` (Plan 1).
- Produces:
  - `class RideOffer { final String driverPubkey; final RideOfferPayload payload; final int receivedAt; const RideOffer(...); }`
  - `class OfferService { OfferService(RideDmChannel dm); Future<void> sendOffer({required driverPrivHex, required passengerPubHex, required RideOfferPayload offer, required now}); Stream<RideOffer> receiveOffers(String passengerPubHex, String passengerPrivHex); }`
  - `class RankedRideOffer { final RideOffer offer; final Reputation reputation; const RankedRideOffer(...); }`
  - `List<RankedRideOffer> rankRideOffers(List<RideOffer> offers, {required List<TripReceipt> Function(String driverPubkey) receiptsFor, Set<String> viewerTrusted = const {}})`
  - `class TripReceiptRepository { TripReceiptRepository(RelayPool pool); Future<List<TripReceipt>> receiptsAbout(String subjectPubkey, {Duration timeout = const Duration(seconds: 3)}); }`

- [ ] **Step 1: Write the failing test for the pure ranking function**

```dart
// app/test/ride/offer_ranking_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/offer_ranking.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

TripReceipt _receipt(String author, String about, String trip) =>
    TripReceipt(
      tripId: trip,
      counterpartyPubkey: about,
      role: 'passenger',
      ratingStars: 5,
      distanceMeters: 1,
      durationSeconds: 1,
      priceMnt: 1,
      comment: '',
      authorPubkey: author,
      createdAt: 0,
    );

RideOffer _offer(String driverPubkey, int priceMnt) => RideOffer(
      driverPubkey,
      RideOfferPayload(
        rideRequestId: 'req1',
        priceMnt: priceMnt,
        etaMinutes: 5,
        vehicleDescription: 'x',
      ),
      1000,
    );

void main() {
  test('ranks a driver with paired trip history above one with none', () {
    final trusted = _offer('D1', 5000);
    final stranger = _offer('D2', 4000);
    final receipts = [
      _receipt('R1', 'D1', 't1'),
      _receipt('D1', 'R1', 't1'),
    ];
    final ranked = rankRideOffers(
      [stranger, trusted],
      receiptsFor: (pubkey) => receipts
          .where((r) =>
              r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey)
          .toList(),
    );
    expect(ranked.first.offer.driverPubkey, 'D1');
    expect(ranked.first.reputation.pairedTripCount, 1);
    expect(ranked.last.offer.driverPubkey, 'D2');
    expect(ranked.last.reputation.pairedTripCount, 0);
  });

  test('viewer-trusted counterparties push a driver higher', () {
    final a = _offer('DA', 5000);
    final b = _offer('DB', 5000);
    final receiptsA = [_receipt('X', 'DA', 't1'), _receipt('DA', 'X', 't1')];
    final receiptsB = [_receipt('Y', 'DB', 't1'), _receipt('DB', 'Y', 't1')];
    final all = [...receiptsA, ...receiptsB];
    final ranked = rankRideOffers(
      [a, b],
      receiptsFor: (pubkey) => all
          .where((r) =>
              r.authorPubkey == pubkey || r.counterpartyPubkey == pubkey)
          .toList(),
      viewerTrusted: {'X'},
    );
    expect(ranked.first.offer.driverPubkey, 'DA');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/ride/offer_ranking_test.dart`
Expected: FAIL — `package:takhi/ride/offer_ranking.dart` (and `offer_service.dart`) not found.

- [ ] **Step 3: Implement `offer_service.dart` and `offer_ranking.dart`**

```dart
// app/lib/ride/offer_service.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';

/// A driver's offer as the passenger sees it: who sent it (the verified
/// sender from `RideDmChannel.inbox`, never a self-reported field) plus
/// the decoded fields.
class RideOffer {
  final String driverPubkey;
  final RideOfferPayload payload;
  final int receivedAt;
  const RideOffer(this.driverPubkey, this.payload, this.receivedAt);
}

/// Sends a driver's offer to a passenger (spec §7.1 step 3) and lets a
/// passenger collect the stream of offers addressed to them. Reputation-
/// ranking the collected offers is [rankRideOffers] (`offer_ranking.dart`)
/// -- kept separate so it stays pure and relay-free for testing.
class OfferService {
  final RideDmChannel _dm;
  OfferService(this._dm);

  Future<void> sendOffer({
    required String driverPrivHex,
    required String passengerPubHex,
    required RideOfferPayload offer,
    required int now,
  }) async {
    await _dm.send(
      senderPrivHex: driverPrivHex,
      recipientPubHex: passengerPubHex,
      payload: offer,
      now: now,
    );
  }

  /// Every incoming offer addressed to the passenger, across all of
  /// their active ride requests -- callers filter by
  /// `RideOffer.payload.rideRequestId` for the request they're currently
  /// showing offers for.
  Stream<RideOffer> receiveOffers(
      String passengerPubHex, String passengerPrivHex) {
    return _dm
        .inbox(passengerPubHex, passengerPrivHex)
        .where((dm) => dm.payload is RideOfferPayload)
        .map((dm) => RideOffer(
              dm.senderPubkey,
              dm.payload as RideOfferPayload,
              dm.wrapReceivedAt,
            ));
  }
}
```

```dart
// app/lib/ride/offer_ranking.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import 'offer_service.dart';

/// One offer combined with the reputation of the driver who sent it,
/// sorted by [Reputation.trustWeight] (spec §7.1 step 3: "нэр хүнд + үнэ +
/// ETA-гаар сонгоно" -- reputation is the primary sort key; price/ETA are
/// shown alongside for the passenger to weigh themselves).
class RankedRideOffer {
  final RideOffer offer;
  final Reputation reputation;
  const RankedRideOffer(this.offer, this.reputation);
}

/// Ranks [offers] by each driver's [computeReputation], highest
/// `trustWeight` first. [receiptsFor] looks up the trip receipts already
/// known about a driver pubkey (from [TripReceiptRepository], injected so
/// this function stays pure and independently testable). [viewerTrusted]
/// is the passenger's own web-of-trust set (spec §9).
List<RankedRideOffer> rankRideOffers(
  List<RideOffer> offers, {
  required List<TripReceipt> Function(String driverPubkey) receiptsFor,
  Set<String> viewerTrusted = const {},
}) {
  final ranked = offers
      .map((offer) => RankedRideOffer(
            offer,
            computeReputation(
              subjectPubkey: offer.driverPubkey,
              allReceipts: receiptsFor(offer.driverPubkey),
              viewerTrusted: viewerTrusted,
            ),
          ))
      .toList();
  ranked.sort(
      (a, b) => b.reputation.trustWeight.compareTo(a.reputation.trustWeight));
  return ranked;
}
```

- [ ] **Step 4: Run test to verify it passes, commit**

Run: `cd app && flutter test test/ride/offer_ranking_test.dart`
Expected: PASS (2 tests).

```bash
git add app/lib/ride/offer_service.dart app/lib/ride/offer_ranking.dart app/test/ride/offer_ranking_test.dart
git commit -m "feat(app): offer send/receive service + reputation ranking"
```

- [ ] **Step 5: Write the failing test for `OfferService`'s network glue**

```dart
// app/test/ride/offer_service_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final driver = generateKeyPair(List<int>.filled(32, 101));
  final passenger = generateKeyPair(List<int>.filled(32, 102));

  test('sendOffer delivers a decoded RideOffer to the passenger inbox',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final dm = RideDmChannel(pool);
    final service = OfferService(dm);

    final got = <RideOffer>[];
    final sub = service
        .receiveOffers(passenger.publicHex, passenger.privateHex)
        .listen(got.add);
    final channelForSetup = RideDmChannel(pool);
    // The inbox subscription above already sent its REQ; find its subId.
    final subId = sockets['wss://a']!.sent.first;
    await service.sendOffer(
      driverPrivHex: driver.privateHex,
      passengerPubHex: passenger.publicHex,
      offer: const RideOfferPayload(
        rideRequestId: 'req1',
        priceMnt: 7000,
        etaMinutes: 6,
        vehicleDescription: 'ногоон Sonata',
      ),
      now: 1000,
    );
    // Replay the just-published wrap back through the inbox subscription,
    // exactly as a relay echoes a matching event to a live subscriber.
    // ignore: unused_local_variable
    channelForSetup;
    expect(subId.contains('"REQ"'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // Nothing arrives yet -- the fake relay doesn't echo publishes back
    // to subscribers on its own; the passenger-side test below drives
    // that explicitly via `emit`.
    expect(got, isEmpty);
    await sub.cancel();
  });
}
```

> The above illustrates the REQ/publish split but is not itself a strong test — replace it with the version below, which explicitly emits the published frame back to the subscriber (the same pattern Task 4's `cancelWithDriver` test and Task 3's `ride_dm_channel_test.dart` already use). Use this test file instead:

```dart
// app/test/ride/offer_service_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final driver = generateKeyPair(List<int>.filled(32, 101));
  final passenger = generateKeyPair(List<int>.filled(32, 102));

  test('sendOffer delivers a decoded RideOffer to the passenger inbox',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = OfferService(RideDmChannel(pool));

    final got = <RideOffer>[];
    final sub = service
        .receiveOffers(passenger.publicHex, passenger.privateHex)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await service.sendOffer(
      driverPrivHex: driver.privateHex,
      passengerPubHex: passenger.publicHex,
      offer: const RideOfferPayload(
        rideRequestId: 'req1',
        priceMnt: 7000,
        etaMinutes: 6,
        vehicleDescription: 'ногоон Sonata',
      ),
      now: 1000,
    );
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.driverPubkey, driver.publicHex);
    expect(got.first.payload.priceMnt, 7000);
    expect(got.first.payload.vehicleDescription, 'ногоон Sonata');
    await sub.cancel();
  });

  test('receiveOffers ignores non-offer ride DMs on the same channel',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final dm = RideDmChannel(pool);
    final service = OfferService(dm);

    final got = <RideOffer>[];
    final sub = service
        .receiveOffers(passenger.publicHex, passenger.privateHex)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await dm.send(
      senderPrivHex: driver.privateHex,
      recipientPubHex: passenger.publicHex,
      payload: const RideCancelPayload(rideRequestId: 'req1'),
      now: 1000,
    );
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got, isEmpty);
    await sub.cancel();
  });
}
```

- [ ] **Step 6: Run test to verify it fails, then passes**

Run: `cd app && flutter test test/ride/offer_service_test.dart`
Expected: first FAIL (before `offer_service.dart` existed it would already exist from Step 3 — re-run to confirm both new tests PASS once the file above replaces the illustrative first draft). Final expected: PASS (2 tests).

```bash
git add app/test/ride/offer_service_test.dart
git commit -m "test(app): OfferService network-glue coverage over RideDmChannel"
```

- [ ] **Step 7: Write the failing test for `TripReceiptRepository`**

```dart
// app/test/ride/trip_receipt_repository_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/trip_receipt_repository.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  test('collects parsed receipts emitted before the timeout', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final future = repo.receiptsAbout('D1',
        timeout: const Duration(milliseconds: 20));
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    final kp = generateKeyPair(List<int>.filled(32, 81));
    final unsigned = buildTripReceipt(
      pubkey: kp.publicHex,
      now: 1,
      tripId: 't1',
      counterpartyPubkey: 'D1',
      role: 'passenger',
      ratingStars: 5,
      distanceMeters: 1,
      durationSeconds: 1,
      priceMnt: 1,
    );
    final signed =
        signEvent(unsigned, kp.privateHex, auxRand: List<int>.filled(32, 0));
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, signed.toJson()]));

    final receipts = await future;
    expect(receipts.length, 1);
    expect(receipts.first.counterpartyPubkey, 'D1');
  });

  test('skips events that fail to parse as a trip receipt', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final future = repo.receiptsAbout('D1',
        timeout: const Duration(milliseconds: 20));
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;
    final kp = generateKeyPair(List<int>.filled(32, 82));
    final wrongKind = signEvent(
        NostrEvent(
            pubkey: kp.publicHex,
            createdAt: 1,
            kind: 1,
            tags: [],
            content: 'x'),
        kp.privateHex,
        auxRand: List<int>.filled(32, 0));
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', subId, wrongKind.toJson()]));

    final receipts = await future;
    expect(receipts, isEmpty);
  });
}
```

- [ ] **Step 8: Run test to verify it fails**

Run: `cd app && flutter test test/ride/trip_receipt_repository_test.dart`
Expected: FAIL — `package:takhi/ride/trip_receipt_repository.dart` not found.

- [ ] **Step 9: Implement**

```dart
// app/lib/ride/trip_receipt_repository.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';

/// Fetches the trip receipts already published about a pubkey (kind
/// 30177, spec §9), so [rankRideOffers] can weigh a driver's history.
/// Deliberately a snapshot fetch, not a long-lived subscription: it
/// collects whatever a relay has stored for [timeout], then closes.
class TripReceiptRepository {
  final RelayPool _pool;
  TripReceiptRepository(this._pool);

  Future<List<TripReceipt>> receiptsAbout(
    String subjectPubkey, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final filter = RelayFilter(
      kinds: [kKindTripReceipt],
      tagFilters: {
        '#p': [subjectPubkey],
      },
    );
    final receipts = <TripReceipt>[];
    final sub = _pool.subscribe(filter).listen((event) {
      try {
        receipts.add(parseTripReceipt(event));
      } on FormatException {
        // A malformed/foreign kind-30177 event; skip it rather than fail
        // the whole fetch.
      }
    });
    await Future<void>.delayed(timeout);
    await sub.cancel();
    return receipts;
  }
}
```

- [ ] **Step 10: Run test to verify it passes**

Run: `cd app && flutter test test/ride/trip_receipt_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 11: Commit**

```bash
git add app/lib/ride/trip_receipt_repository.dart app/test/ride/trip_receipt_repository_test.dart
git commit -m "feat(app): trip receipt lookup for reputation ranking"
```

---

### Task 7: `HandoffService` — exact-location handoff + trip id

**Files:**
- Create: `app/lib/ride/trip_id.dart`
- Create: `app/lib/ride/handoff_service.dart`
- Test: `app/test/ride/trip_id_test.dart`
- Test: `app/test/ride/handoff_service_test.dart`

**Interfaces:**
- Consumes: `plusCodeEncode` (Plan 1); `RideDmChannel`, `RideHandoffPayload` (Tasks 2-3).
- Produces:
  - `String generateTripId([List<int>? randomBytes16])` — 32-hex-char id from 16 random bytes.
  - `class ReceivedHandoff { final String senderPubkey; final RideHandoffPayload payload; const ReceivedHandoff(...); }`
  - `class HandoffService { HandoffService(RideDmChannel dm); Future<String> sendHandoff({required passengerPrivHex, required driverPubHex, required rideRequestId, required lat, required lon, required landmarkText, required now, tripId}); Stream<ReceivedHandoff> receiveHandoffs(String myPubHex, String myPrivHex); }`

- [ ] **Step 1: Write the failing test for `generateTripId`**

```dart
// app/test/ride/trip_id_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/trip_id.dart';

void main() {
  test('generates a 32-hex-char id from 16 bytes', () {
    final id = generateTripId(List<int>.filled(16, 7));
    expect(id.length, 32);
  });

  test('two calls without fixed bytes produce different ids', () {
    expect(generateTripId(), isNot(generateTripId()));
  });

  test('rejects a seed that is not exactly 16 bytes', () {
    expect(() => generateTripId(List<int>.filled(8, 1)), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/ride/trip_id_test.dart`
Expected: FAIL — `package:takhi/ride/trip_id.dart` not found.

- [ ] **Step 3: Implement `trip_id.dart`**

```dart
// app/lib/ride/trip_id.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:convert/convert.dart';

/// Generates a fresh trip id: 16 random bytes, hex-encoded. The passenger
/// mints this at handoff time (spec §6 "Тохироо + яг байршил", §9) and it
/// becomes the `d` tag both sides' eventual trip receipts (kind 30177,
/// Plan 4) share.
///
/// Pass [randomBytes16] for deterministic output in tests; otherwise
/// secure randomness is used, mirroring `generateKeyPair`'s pattern in
/// `takhi_protocol`.
String generateTripId([List<int>? randomBytes16]) {
  final bytes = randomBytes16 ?? _secureRandom16();
  if (bytes.length != 16) {
    throw ArgumentError('trip id seed must be 16 bytes');
  }
  return hex.encode(bytes);
}

List<int> _secureRandom16() {
  final r = math.Random.secure();
  return List<int>.generate(16, (_) => r.nextInt(256));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/ride/trip_id_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing test for `HandoffService`**

```dart
// app/test/ride/handoff_service_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/handoff_service.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final passenger = generateKeyPair(List<int>.filled(32, 91));
  final driver = generateKeyPair(List<int>.filled(32, 92));

  test(
      'sendHandoff mints a trip id and delivers exact location to the '
      'driver', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final dm = RideDmChannel(pool);
    final service = HandoffService(dm);

    final got = <ReceivedHandoff>[];
    final sub = service
        .receiveHandoffs(driver.publicHex, driver.privateHex)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    final tripId = await service.sendHandoff(
      passengerPrivHex: passenger.privateHex,
      driverPubHex: driver.publicHex,
      rideRequestId: 'req1',
      lat: 47.9186,
      lon: 106.9176,
      landmarkText: 'Улаан хаалганы урд',
      now: 1000,
    );

    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(tripId.length, 32);
    expect(got.length, 1);
    expect(got.first.senderPubkey, passenger.publicHex);
    expect(got.first.payload.rideRequestId, 'req1');
    expect(got.first.payload.tripId, tripId);
    expect(got.first.payload.landmarkText, 'Улаан хаалганы урд');
    expect(got.first.payload.plusCode, plusCodeEncode(47.9186, 106.9176));
    await sub.cancel();
  });

  test('a caller-supplied tripId is used verbatim instead of minting one',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = HandoffService(RideDmChannel(pool));

    final tripId = await service.sendHandoff(
      passengerPrivHex: passenger.privateHex,
      driverPubHex: driver.publicHex,
      rideRequestId: 'req1',
      lat: 1,
      lon: 1,
      landmarkText: 'x',
      now: 1000,
      tripId: 'fixed-trip-id',
    );
    expect(tripId, 'fixed-trip-id');
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd app && flutter test test/ride/handoff_service_test.dart`
Expected: FAIL — `package:takhi/ride/handoff_service.dart` not found.

- [ ] **Step 7: Implement `handoff_service.dart`**

```dart
// app/lib/ride/handoff_service.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';
import 'trip_id.dart';

/// A handoff the local side received -- for a driver, this is the
/// passenger's exact pickup point once selected (spec §6/§7.1 step 4).
class ReceivedHandoff {
  final String senderPubkey;
  final RideHandoffPayload payload;
  const ReceivedHandoff(this.senderPubkey, this.payload);
}

/// Sends the passenger's exact pickup location to the one driver they
/// selected (spec §7.1 step 4) and lets either side listen for it. The
/// passenger mints [generateTripId] here -- this is the only place a trip
/// id is created; every later trip receipt (Plan 4) reuses it as the `d`
/// tag.
class HandoffService {
  final RideDmChannel _dm;
  HandoffService(this._dm);

  /// Sends the handoff and returns the trip id that was minted for it
  /// (or the caller-supplied [tripId], used verbatim if given).
  Future<String> sendHandoff({
    required String passengerPrivHex,
    required String driverPubHex,
    required String rideRequestId,
    required double lat,
    required double lon,
    required String landmarkText,
    required int now,
    String? tripId,
  }) async {
    final id = tripId ?? generateTripId();
    final payload = RideHandoffPayload(
      rideRequestId: rideRequestId,
      tripId: id,
      lat: lat,
      lon: lon,
      plusCode: plusCodeEncode(lat, lon),
      landmarkText: landmarkText,
    );
    await _dm.send(
      senderPrivHex: passengerPrivHex,
      recipientPubHex: driverPubHex,
      payload: payload,
      now: now,
    );
    return id;
  }

  /// Every handoff addressed to the local identity -- for a driver, this
  /// fires once a passenger selects them.
  Stream<ReceivedHandoff> receiveHandoffs(String myPubHex, String myPrivHex) {
    return RideDmChannel(_poolOf(_dm))
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is RideHandoffPayload)
        .map((dm) => ReceivedHandoff(
              dm.senderPubkey,
              dm.payload as RideHandoffPayload,
            ));
  }

  // `RideDmChannel` doesn't expose its pool, and re-wrapping it here would
  // require one; instead `receiveHandoffs` is implemented directly over
  // `_dm.inbox` below. This placeholder is intentionally removed in the
  // real implementation -- see the corrected version immediately below.
  dynamic _poolOf(dynamic dm) => throw UnimplementedError();
}
```

> The `_poolOf` indirection above is wrong — `RideDmChannel` already exposes exactly the `inbox`/`send` surface this service needs, so `receiveHandoffs` should call `_dm.inbox(...)` directly, the same way `OfferService.receiveOffers` (Task 6) does. Replace the class body with the corrected version:

```dart
// app/lib/ride/handoff_service.dart -- final version
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';
import 'trip_id.dart';

/// A handoff the local side received -- for a driver, this is the
/// passenger's exact pickup point once selected (spec §6/§7.1 step 4).
class ReceivedHandoff {
  final String senderPubkey;
  final RideHandoffPayload payload;
  const ReceivedHandoff(this.senderPubkey, this.payload);
}

/// Sends the passenger's exact pickup location to the one driver they
/// selected (spec §7.1 step 4) and lets either side listen for it. The
/// passenger mints [generateTripId] here -- this is the only place a trip
/// id is created; every later trip receipt (Plan 4) reuses it as the `d`
/// tag.
class HandoffService {
  final RideDmChannel _dm;
  HandoffService(this._dm);

  /// Sends the handoff and returns the trip id that was minted for it
  /// (or the caller-supplied [tripId], used verbatim if given).
  Future<String> sendHandoff({
    required String passengerPrivHex,
    required String driverPubHex,
    required String rideRequestId,
    required double lat,
    required double lon,
    required String landmarkText,
    required int now,
    String? tripId,
  }) async {
    final id = tripId ?? generateTripId();
    final payload = RideHandoffPayload(
      rideRequestId: rideRequestId,
      tripId: id,
      lat: lat,
      lon: lon,
      plusCode: plusCodeEncode(lat, lon),
      landmarkText: landmarkText,
    );
    await _dm.send(
      senderPrivHex: passengerPrivHex,
      recipientPubHex: driverPubHex,
      payload: payload,
      now: now,
    );
    return id;
  }

  /// Every handoff addressed to the local identity -- for a driver, this
  /// fires once a passenger selects them.
  Stream<ReceivedHandoff> receiveHandoffs(String myPubHex, String myPrivHex) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is RideHandoffPayload)
        .map((dm) => ReceivedHandoff(
              dm.senderPubkey,
              dm.payload as RideHandoffPayload,
            ));
  }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd app && flutter test test/ride/handoff_service_test.dart test/ride/trip_id_test.dart`
Expected: PASS (5 tests total).

- [ ] **Step 9: Commit**

```bash
git add app/lib/ride/trip_id.dart app/lib/ride/handoff_service.dart app/test/ride/trip_id_test.dart app/test/ride/handoff_service_test.dart
git commit -m "feat(app): trip id minting + exact-location handoff"
```

---

### Task 8: Map — `flutter_map`/OSM, location picker, nearby-request layer

**Files:**
- Modify: `app/pubspec.yaml` (add `flutter_map`, `latlong2`)
- Modify: `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb` (add `landmarkHint`)
- Create: `app/lib/map/ride_map.dart`
- Create: `app/lib/map/location_picker.dart`
- Create: `app/lib/map/nearby_requests_layer.dart`
- Test: `app/test/map/location_picker_test.dart`
- Test: `app/test/map/nearby_requests_layer_test.dart`

**Interfaces:**
- Consumes: `plusCodeEncode` (Plan 1); `geohashDecodeCenter` (Plan 1); `RideRequestListing` (Task 5); `TakhiColors` (Plan 2); `AppLocalizations` (Plan 2, extended here).
- Produces:
  - `class RideMap extends StatelessWidget { const RideMap({required LatLng initialCenter, double initialZoom = 15, MapController? controller, ValueChanged<LatLng>? onCenterChanged, List<Widget> layers = const []}); }`
  - `class PickedLocation { final double lat; final double lon; final String landmarkText; const PickedLocation({required lat, required lon, landmarkText = ''}); String get plusCode; }`
  - `class LocationPickerField extends StatefulWidget { const LocationPickerField({required LatLng initialCenter, required ValueChanged<PickedLocation> onChanged}); }`
  - `class NearbyRequestsLayer extends StatelessWidget { const NearbyRequestsLayer({required List<RideRequestListing> listings, required ValueChanged<RideRequestListing> onTap}); }`

**Approach:** `RideMap` is the bare OSM-tiled map every ride screen builds on — it takes no default center of its own (spec §11 "кодонд УБ hardcode 0": the widget itself carries no city hardcode; the concrete Ulaanbaatar default lives at the Task 9 screen call sites, as a documented placeholder for a future city-config seam). `LocationPickerField` uses the standard "pan the map under a fixed center pin" pattern (rather than a draggable pin) — every pan and every landmark-text keystroke calls `onChanged` with a fresh `PickedLocation`, so callers always have a current value without a separate "confirm" step. `NearbyRequestsLayer` can only ever plot a request's geohash-6 cell **center** (via `geohashDecodeCenter`) because `RideRequestListing` (Task 5) never carries anything more precise — the privacy tiering from spec §6/§9 (public = geohash-6 only) is enforced structurally by the type, not by a rule this widget has to remember to follow.

- [ ] **Step 1: Add dependencies and the `landmarkHint` ARB key**

```yaml
# app/pubspec.yaml -- add under dependencies:
  flutter_map: ^8.1.1
  latlong2: ^0.9.1
```

Run `cd app && flutter pub add flutter_map latlong2` and confirm the resolved versions; `flutter_map`'s v6 API rewrite renamed several parameters (`center`→`initialCenter`, etc.) — if the resolved major differs from `^8`, check `MapOptions`/`TileLayer`/`MarkerLayer`/`Marker`/`RichAttributionWidget` constructor signatures against the installed version before Step 3.

```json
// app/lib/l10n/app_mn.arb -- add
  "landmarkHint": "Тэмдэглэл (жишээ: цагаан хаалга)",
```

```json
// app/lib/l10n/app_en.arb -- add
  "landmarkHint": "Landmark note (e.g. white gate)",
```

- [ ] **Step 2: Write the failing test for `LocationPickerField`**

```dart
// app/test/map/location_picker_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/location_picker.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  testWidgets(
      'typing a landmark reports a PickedLocation with a matching Plus '
      'Code', (tester) async {
    PickedLocation? last;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('mn'),
      home: LocationPickerField(
        initialCenter: const ll.LatLng(47.9186, 106.9176),
        onChanged: (p) => last = p,
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Улаан хаалганы урд');
    await tester.pump();

    expect(last, isNotNull);
    expect(last!.landmarkText, 'Улаан хаалганы урд');
    expect(last!.lat, 47.9186);
    expect(last!.lon, 106.9176);
    expect(last!.plusCode, plusCodeEncode(47.9186, 106.9176));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/map/location_picker_test.dart`
Expected: FAIL — `package:takhi/map/location_picker.dart` (and `ride_map.dart`) not found.

- [ ] **Step 4: Implement `ride_map.dart` and `location_picker.dart`**

```dart
// app/lib/map/ride_map.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

/// The bare OSM-tiled map every ride screen builds on (spec §12 `map/`,
/// §5: "OSM pin + Plus Code + чөлөөт текст"; open tiles, no paid/closed
/// geocoding API). Takes no city-specific default -- callers always pass
/// [initialCenter] -- so this widget carries no hardcoded city (spec §11
/// "кодонд УБ hardcode 0"); the concrete Ulaanbaatar default lives at the
/// ride-screen call site (Task 9) until a real city-config seam exists.
class RideMap extends StatelessWidget {
  final ll.LatLng initialCenter;
  final double initialZoom;
  final MapController? controller;
  final ValueChanged<ll.LatLng>? onCenterChanged;
  final List<Widget> layers;

  const RideMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15,
    this.controller,
    this.onCenterChanged,
    this.layers = const [],
  });

  @override
  Widget build(BuildContext context) => FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: initialZoom,
          onPositionChanged: (position, hasGesture) {
            if (!hasGesture) return;
            final center = position.center;
            onCenterChanged?.call(center);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'mn.takhi.takhi',
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
            ],
          ),
          ...layers,
        ],
      );
}
```

```dart
// app/lib/map/location_picker.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import 'ride_map.dart';

/// A point the rider picked: exact coordinates, the Plus Code derived
/// from them (spec §5 geocoding decision), and an optional free-text
/// landmark description they typed themselves.
class PickedLocation {
  final double lat;
  final double lon;
  final String landmarkText;
  const PickedLocation({
    required this.lat,
    required this.lon,
    this.landmarkText = '',
  });

  String get plusCode => plusCodeEncode(lat, lon);
}

/// Center-pin map picker + landmark text field (spec §5/§12): the rider
/// pans the map under a fixed center pin rather than dragging the pin
/// itself -- the standard, thumb-friendly picking pattern for a
/// full-width map. Every pan and keystroke calls [onChanged] with the
/// current [PickedLocation], so callers always have a live value rather
/// than only on an explicit "confirm".
class LocationPickerField extends StatefulWidget {
  final ll.LatLng initialCenter;
  final ValueChanged<PickedLocation> onChanged;

  const LocationPickerField({
    super.key,
    required this.initialCenter,
    required this.onChanged,
  });

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  late ll.LatLng _center = widget.initialCenter;
  String _landmarkText = '';

  void _emit() => widget.onChanged(PickedLocation(
        lat: _center.latitude,
        lon: _center.longitude,
        landmarkText: _landmarkText,
      ));

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RideMap(
                  initialCenter: _center,
                  onCenterChanged: (c) => setState(() {
                    _center = c;
                    _emit();
                  }),
                ),
                const IgnorePointer(
                  child: Icon(Icons.location_pin,
                      color: TakhiColors.gold, size: 40),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: (text) => setState(() {
              _landmarkText = text;
              _emit();
            }),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: AppLocalizations.of(context)!.landmarkHint,
            ),
          ),
        ],
      );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/map/location_picker_test.dart`
Expected: PASS (1 test).

- [ ] **Step 6: Write the failing test for `NearbyRequestsLayer`**

```dart
// app/test/map/nearby_requests_layer_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/map/nearby_requests_layer.dart';
import 'package:takhi/ride/driver_inbox_service.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  testWidgets('renders one marker per listing and reports taps',
      (tester) async {
    final kp = generateKeyPair(List<int>.filled(32, 95));
    final unsigned = buildRideRequest(
      pubkey: kp.publicHex,
      now: 1000,
      pickupLat: 47.9186,
      pickupLon: 106.9176,
      destLat: 47.91,
      destLon: 106.90,
    );
    final event =
        signEvent(unsigned, kp.privateHex, auxRand: List<int>.filled(32, 0));
    final listing = RideRequestListing(event, parseRideRequest(event));

    RideRequestListing? tapped;
    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        options:
            const MapOptions(initialCenter: ll.LatLng(47.9186, 106.9176)),
        children: [
          NearbyRequestsLayer(
              listings: [listing], onTap: (l) => tapped = l),
        ],
      ),
    ));

    expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_pin_circle));
    expect(tapped, listing);
  });
}
```

- [ ] **Step 7: Run test to verify it fails**

Run: `cd app && flutter test test/map/nearby_requests_layer_test.dart`
Expected: FAIL — `package:takhi/map/nearby_requests_layer.dart` not found.

- [ ] **Step 8: Implement `nearby_requests_layer.dart`**

```dart
// app/lib/map/nearby_requests_layer.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../ride/driver_inbox_service.dart';
import '../theme/takhi_theme.dart';

/// Draws each nearby ride request a driver is subscribed to at its
/// geohash-6 cell CENTER, never at a passenger's exact coordinates --
/// `DriverInboxService` never receives exact coordinates in the first
/// place (spec §6/§9 privacy tiering: public = geohash-6 only, the exact
/// point is DM-only after selection), so there is nothing more precise
/// this layer could plot even by mistake.
class NearbyRequestsLayer extends StatelessWidget {
  final List<RideRequestListing> listings;
  final ValueChanged<RideRequestListing> onTap;

  const NearbyRequestsLayer({
    super.key,
    required this.listings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => MarkerLayer(
        markers: listings.map((listing) {
          final center = geohashDecodeCenter(listing.request.pickupGeohash);
          return Marker(
            point: ll.LatLng(center.lat, center.lon),
            width: 36,
            height: 36,
            child: GestureDetector(
              onTap: () => onTap(listing),
              child: const Icon(Icons.person_pin_circle,
                  color: TakhiColors.steppe, size: 36),
            ),
          );
        }).toList(),
      );
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `cd app && flutter test test/map/nearby_requests_layer_test.dart`
Expected: PASS (1 test).

- [ ] **Step 10: Regenerate ARB, run `flutter analyze`, commit**

```bash
cd app && flutter gen-l10n && flutter analyze
git add app/pubspec.yaml app/lib/l10n/app_mn.arb app/lib/l10n/app_en.arb app/lib/map app/test/map
git commit -m "feat(app): OSM map, location picker, nearby-request marker layer"
```

---

### Task 9: Ride screens — passenger & driver flows wired end-to-end

**Files:**
- Create: `app/lib/ride/ride_providers.dart`
- Create: `app/lib/ride/passenger_ride_page.dart`
- Create: `app/lib/ride/driver_inbox_page.dart`
- Modify: `app/lib/router.dart` (routes `/ride/passenger`, `/ride/driver`; `HomePage` CTA button)
- Modify: `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb` (screen copy)
- Test: `app/test/ride/passenger_ride_page_test.dart`
- Test: `app/test/router_redirect_test.dart` (extend with the new routes — read the existing file first; add cases, don't remove any)

**Interfaces:**
- Consumes: every service from Tasks 3-7 (`RideDmChannel`, `RideRequestService`, `DriverInboxService`, `OfferService`, `TripReceiptRepository`, `HandoffService`); `RideMap`, `LocationPickerField`, `PickedLocation`, `NearbyRequestsLayer` (Task 8); `relayPoolProvider` (Plan 2); `currentIdentityProvider`, `Identity` (Plan 2); `TakhiColors`, `PrimaryButton`, `AppLocalizations` (Plan 2).
- Produces: `ride_providers.dart`'s six `Provider`s; `PassengerRidePage`, `DriverInboxPage` widgets; two new routes on `routerProvider`'s `GoRouter`; a CTA button on `HomePage`.

**Approach:** Both pages are single `ConsumerStatefulWidget`s driving an internal step/state machine — `PassengerRidePage` steps through pickup → destination → price → offers → done; `DriverInboxPage` shows a map of nearby requests until an offer is sent, then (if selected) switches to the received handoff. This mirrors the existing `OnboardingPage`'s pattern (Plan 2 Task 5: one page, `setState`-driven steps, no separate router hop per step) rather than introducing a five-route sub-flow. Every string is ARB-driven; every service call goes through the `ride_providers.dart` `Provider`s so tests can override them with a fake-socket-backed `RelayPool` exactly as `home_page_test.dart` (Plan 2) already does.

- [ ] **Step 1: Add the screen-copy ARB keys**

```json
// app/lib/l10n/app_mn.arb -- add
  "nextStep": "Үргэлжлүүл",
  "publishRide": "Нийтлэх",
  "priceLabel": "Санал үнэ (₮, заавал биш)",
  "offersWaitingTitle": "Ирж буй саналууд",
  "offerSummary": "{price}₮ · {eta} мин",
  "@offerSummary": {
    "placeholders": {
      "price": {"type": "int"},
      "eta": {"type": "int"}
    }
  },
  "sendOfferAction": "Санал илгээх",
  "offerPriceFieldLabel": "Үнэ (₮)",
  "offerEtaFieldLabel": "Хүрэх хугацаа (мин)",
  "offerVehicleFieldLabel": "Машины мэдээлэл",
  "driverOnTheWay": "{vehicle} ирж байна",
  "@driverOnTheWay": {
    "placeholders": {
      "vehicle": {"type": "String"}
    }
  },
  "handoffReceivedTitle": "Зорчигчийн яг байршил",
  "startAsPassengerAction": "Дуудлага өгөх",
  "startAsDriverAction": "Дуудлага сонсох",
```

```json
// app/lib/l10n/app_en.arb -- add
  "nextStep": "Continue",
  "publishRide": "Publish",
  "priceLabel": "Offered price (₮, optional)",
  "offersWaitingTitle": "Incoming offers",
  "offerSummary": "{price}₮ · {eta} min",
  "sendOfferAction": "Send offer",
  "offerPriceFieldLabel": "Price (₮)",
  "offerEtaFieldLabel": "ETA (minutes)",
  "offerVehicleFieldLabel": "Vehicle info",
  "driverOnTheWay": "{vehicle} is on the way",
  "handoffReceivedTitle": "Passenger's exact location",
  "startAsPassengerAction": "Request a ride",
  "startAsDriverAction": "Listen for calls",
```

Run `cd app && flutter gen-l10n` after adding these so `AppLocalizations` exposes `l.nextStep`, `l.offerSummary(price, eta)`, `l.driverOnTheWay(vehicle)`, etc. before Step 2.

- [ ] **Step 2: Create `ride_providers.dart`**

```dart
// app/lib/ride/ride_providers.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nostr/relay_pool_provider.dart';
import 'driver_inbox_service.dart';
import 'handoff_service.dart';
import 'offer_service.dart';
import 'ride_dm_channel.dart';
import 'ride_request_service.dart';
import 'trip_receipt_repository.dart';

final rideDmChannelProvider = Provider<RideDmChannel>(
  (ref) => RideDmChannel(ref.watch(relayPoolProvider)),
);

final rideRequestServiceProvider = Provider<RideRequestService>(
  (ref) => RideRequestService(
    ref.watch(relayPoolProvider),
    ref.watch(rideDmChannelProvider),
  ),
);

final driverInboxServiceProvider = Provider<DriverInboxService>(
  (ref) => DriverInboxService(ref.watch(relayPoolProvider)),
);

final offerServiceProvider = Provider<OfferService>(
  (ref) => OfferService(ref.watch(rideDmChannelProvider)),
);

final handoffServiceProvider = Provider<HandoffService>(
  (ref) => HandoffService(ref.watch(rideDmChannelProvider)),
);

final tripReceiptRepositoryProvider = Provider<TripReceiptRepository>(
  (ref) => TripReceiptRepository(ref.watch(relayPoolProvider)),
);
```

- [ ] **Step 3: Write the failing widget test for `PassengerRidePage`**

```dart
// app/test/ride/passenger_ride_page_test.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/passenger_ride_page.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  testWidgets(
      'pickup -> destination -> price -> publish -> ranked offer -> '
      'selecting sends a handoff', (tester) async {
    final store = InMemoryKeyStore();
    final identity = await IdentityService(store).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 111));

    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a'],
        connect: (u) => sockets[u] = FakeRelaySocket());

    await tester.pumpWidget(ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(store),
        relayPoolProvider.overrideWithValue(pool),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const PassengerRidePage(),
      ),
    ));
    await pool.connectAll();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Үргэлжлүүл').first); // pickup -> destination
    await tester.pump();
    await tester.tap(find.text('Үргэлжлүүл').first); // destination -> price
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.tap(find.text('Нийтлэх')); // price -> publish
    await tester.pumpAndSettle();

    final rideRequestFrame = jsonDecode(sockets['wss://a']!.sent
        .firstWhere((s) => s.contains('"kind":20177'))) as List<dynamic>;
    final rideRequestId =
        (rideRequestFrame[1] as Map<String, dynamic>)['id'] as String;

    final offerWrap = nip17Wrap(
      senderPrivHex: driver.privateHex,
      recipientPubHex: identity.pubHex,
      rumorKind: kRumorKindRideDm,
      content: RideOfferPayload(
        rideRequestId: rideRequestId,
        priceMnt: 6000,
        etaMinutes: 3,
        vehicleDescription: 'цагаан Prius',
      ).encode(),
      now: 1000,
    );
    final inboxSubId = (jsonDecode(sockets['wss://a']!.sent
        .firstWhere((s) => s.contains('"kinds":[1059]')))
            as List<dynamic>)[1] as String;
    sockets['wss://a']!
        .emit(jsonEncode(['EVENT', inboxSubId, offerWrap.toJson()]));
    await tester.pumpAndSettle();

    expect(find.textContaining('6000'), findsOneWidget);

    await tester.tap(find.textContaining('6000'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Prius'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd app && flutter test test/ride/passenger_ride_page_test.dart`
Expected: FAIL — `package:takhi/ride/passenger_ride_page.dart` not found.

- [ ] **Step 5: Implement `passenger_ride_page.dart`**

```dart
// app/lib/ride/passenger_ride_page.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/location_picker.dart';
import '../theme/takhi_theme.dart';
import '../widgets/primary_button.dart';
import 'offer_ranking.dart';
import 'offer_service.dart';
import 'ride_providers.dart';

/// Ulaanbaatar's Sukhbaatar Square -- the map's starting center until a
/// city-config seam exists (spec §11; see `RideMap`'s doc comment, Task 8).
const _defaultCityCenter = ll.LatLng(47.9186, 106.9176);

enum _PassengerStep { pickup, destination, price, offers, done }

/// The passenger's full "call a ride" flow (spec §7.1): pick pickup, pick
/// destination, optionally name a price, publish, watch reputation-ranked
/// offers arrive live, select one. Ends once the exact-location handoff
/// is sent -- the trip itself (in-progress tracking, fare settlement) is
/// Plan 4.
class PassengerRidePage extends ConsumerStatefulWidget {
  const PassengerRidePage({super.key});

  @override
  ConsumerState<PassengerRidePage> createState() => _PassengerRidePageState();
}

class _PassengerRidePageState extends ConsumerState<PassengerRidePage> {
  _PassengerStep _step = _PassengerStep.pickup;
  PickedLocation _pickup = const PickedLocation(
      lat: _defaultCityCenter.latitude, lon: _defaultCityCenter.longitude);
  PickedLocation _destination = const PickedLocation(
      lat: _defaultCityCenter.latitude, lon: _defaultCityCenter.longitude);
  final _priceController = TextEditingController();
  String? _rideRequestId;
  final List<RideOffer> _offers = [];
  final Map<String, List<TripReceipt>> _receiptsCache = {};
  RankedRideOffer? _selected;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (identity == null) return;
    final priceMnt = int.tryParse(_priceController.text);
    final event = await ref.read(rideRequestServiceProvider).publishRequest(
          privHex: identity.privHex,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          pickupLat: _pickup.lat,
          pickupLon: _pickup.lon,
          destLat: _destination.lat,
          destLon: _destination.lon,
          offeredMnt: priceMnt,
        );
    if (!mounted) return;
    setState(() {
      _rideRequestId = event.id;
      _step = _PassengerStep.offers;
    });
    ref
        .read(offerServiceProvider)
        .receiveOffers(identity.pubHex, identity.privHex)
        .listen((offer) async {
      if (offer.payload.rideRequestId != _rideRequestId) return;
      if (!mounted) return;
      setState(() => _offers.add(offer));
      if (!_receiptsCache.containsKey(offer.driverPubkey)) {
        final receipts = await ref
            .read(tripReceiptRepositoryProvider)
            .receiptsAbout(offer.driverPubkey);
        if (!mounted) return;
        setState(() => _receiptsCache[offer.driverPubkey] = receipts);
      }
    });
  }

  Future<void> _select(RankedRideOffer ranked) async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (identity == null || _rideRequestId == null) return;
    await ref.read(handoffServiceProvider).sendHandoff(
          passengerPrivHex: identity.privHex,
          driverPubHex: ranked.offer.driverPubkey,
          rideRequestId: _rideRequestId!,
          lat: _pickup.lat,
          lon: _pickup.lon,
          landmarkText: _pickup.landmarkText,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
    if (!mounted) return;
    setState(() {
      _selected = ranked;
      _step = _PassengerStep.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l.appName)),
      body: SafeArea(
        child: switch (_step) {
          _PassengerStep.pickup => _LocationStep(
              initialCenter: _defaultCityCenter,
              onChanged: (p) => _pickup = p,
              onNext: () =>
                  setState(() => _step = _PassengerStep.destination),
            ),
          _PassengerStep.destination => _LocationStep(
              initialCenter: _defaultCityCenter,
              onChanged: (p) => _destination = p,
              onNext: () => setState(() => _step = _PassengerStep.price),
            ),
          _PassengerStep.price =>
            _PriceStep(controller: _priceController, onPublish: _publish),
          _PassengerStep.offers => _OffersStep(
              offers: _offers,
              receiptsFor: (pk) => _receiptsCache[pk] ?? const [],
              onSelect: _select,
            ),
          _PassengerStep.done => _DoneStep(selected: _selected),
        },
      ),
    );
  }
}

class _LocationStep extends StatelessWidget {
  final ll.LatLng initialCenter;
  final ValueChanged<PickedLocation> onChanged;
  final VoidCallback onNext;

  const _LocationStep({
    required this.initialCenter,
    required this.onChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LocationPickerField(
              initialCenter: initialCenter, onChanged: onChanged),
          const SizedBox(height: 16),
          PrimaryButton(label: l.nextStep, onPressed: onNext),
        ],
      ),
    );
  }
}

class _PriceStep extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onPublish;
  const _PriceStep({required this.controller, required this.onPublish});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l.priceLabel,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l.publishRide, onPressed: onPublish),
        ],
      ),
    );
  }
}

class _OffersStep extends StatelessWidget {
  final List<RideOffer> offers;
  final List<TripReceipt> Function(String driverPubkey) receiptsFor;
  final ValueChanged<RankedRideOffer> onSelect;
  const _OffersStep({
    required this.offers,
    required this.receiptsFor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ranked = rankRideOffers(offers, receiptsFor: receiptsFor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l.offersWaitingTitle,
              style: const TextStyle(
                  color: TakhiColors.gold, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: ranked.length,
            itemBuilder: (context, i) {
              final r = ranked[i];
              return ListTile(
                title: Text(l.offerSummary(
                    r.offer.payload.priceMnt, r.offer.payload.etaMinutes)),
                subtitle: Text(r.offer.payload.vehicleDescription),
                onTap: () => onSelect(r),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  final RankedRideOffer? selected;
  const _DoneStep({required this.selected});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final vehicle = selected?.offer.payload.vehicleDescription;
    return Center(
      child: Text(
        vehicle == null ? '' : l.driverOnTheWay(vehicle),
        style: const TextStyle(color: TakhiColors.gold, fontSize: 18),
      ),
    );
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd app && flutter test test/ride/passenger_ride_page_test.dart`
Expected: PASS (1 test).

- [ ] **Step 7: Implement `driver_inbox_page.dart` (no dedicated widget test in this task — covered by the service-level tests in Tasks 5-7; a follow-up UI test is a reasonable next addition, see Self-Review)**

```dart
// app/lib/ride/driver_inbox_page.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/nearby_requests_layer.dart';
import '../map/ride_map.dart';
import '../widgets/primary_button.dart';
import 'driver_inbox_service.dart';
import 'handoff_service.dart';
import 'ride_dm_payload.dart';
import 'ride_providers.dart';

const _defaultCityCenter = ll.LatLng(47.9186, 106.9176);

/// The driver's "listen for nearby calls" flow (spec §7.1 steps 2-4): see
/// requests within a 9-cell geohash neighborhood on a map, tap one to
/// send an offer, then wait -- if the passenger picks this driver, their
/// exact pickup point arrives here as a handoff.
///
/// Simplification: this MVP screen tracks at most one active engagement
/// -- the first handoff it receives is shown as "awarded", regardless of
/// how many concurrent offers were sent. A driver dashboard tracking
/// several simultaneous pending offers is a reasonable follow-up, not
/// required for Plan 3 (see Self-Review).
class DriverInboxPage extends ConsumerStatefulWidget {
  const DriverInboxPage({super.key});

  @override
  ConsumerState<DriverInboxPage> createState() => _DriverInboxPageState();
}

class _DriverInboxPageState extends ConsumerState<DriverInboxPage> {
  ll.LatLng _myLocation = _defaultCityCenter;
  final List<RideRequestListing> _listings = [];
  ReceivedHandoff? _awardedHandoff;

  @override
  void initState() {
    super.initState();
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (identity == null) return;
    ref
        .read(driverInboxServiceProvider)
        .nearbyRequests(
          driverLat: _myLocation.latitude,
          driverLon: _myLocation.longitude,
          nowSeconds: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
        )
        .listen((listing) {
      if (!mounted) return;
      setState(() => _listings.add(listing));
    });
    ref
        .read(handoffServiceProvider)
        .receiveHandoffs(identity.pubHex, identity.privHex)
        .listen((handoff) {
      if (!mounted) return;
      setState(() => _awardedHandoff = handoff);
    });
  }

  Future<void> _sendOffer(RideRequestListing listing) async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (identity == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _OfferDialog(
        onSubmit: (priceMnt, etaMinutes, vehicle) async {
          await ref.read(offerServiceProvider).sendOffer(
                driverPrivHex: identity.privHex,
                passengerPubHex: listing.event.pubkey,
                offer: RideOfferPayload(
                  rideRequestId: listing.rideRequestId,
                  priceMnt: priceMnt,
                  etaMinutes: etaMinutes,
                  vehicleDescription: vehicle,
                ),
                now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              );
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_awardedHandoff != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.appName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.handoffReceivedTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(_awardedHandoff!.payload.plusCode),
                Text(_awardedHandoff!.payload.landmarkText,
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.appName)),
      body: RideMap(
        initialCenter: _myLocation,
        onCenterChanged: (c) => setState(() => _myLocation = c),
        layers: [
          NearbyRequestsLayer(listings: _listings, onTap: _sendOffer),
        ],
      ),
    );
  }
}

class _OfferDialog extends StatefulWidget {
  final Future<void> Function(int priceMnt, int etaMinutes, String vehicle)
      onSubmit;
  const _OfferDialog({required this.onSubmit});

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  final _price = TextEditingController();
  final _eta = TextEditingController();
  final _vehicle = TextEditingController();

  @override
  void dispose() {
    _price.dispose();
    _eta.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.offerPriceFieldLabel),
          ),
          TextField(
            controller: _eta,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.offerEtaFieldLabel),
          ),
          TextField(
            controller: _vehicle,
            decoration:
                InputDecoration(labelText: l.offerVehicleFieldLabel),
          ),
        ],
      ),
      actions: [
        PrimaryButton(
          label: l.sendOfferAction,
          onPressed: () => widget.onSubmit(
            int.tryParse(_price.text) ?? 0,
            int.tryParse(_eta.text) ?? 0,
            _vehicle.text,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 8: Wire the routes and Home CTA into `router.dart`**

Add these imports at the top of `app/lib/router.dart`, alongside the existing ones:

```dart
import 'ride/driver_inbox_page.dart';
import 'ride/passenger_ride_page.dart';
import 'widgets/primary_button.dart';
```

Add two routes to the `routes:` list inside `routerProvider`'s `GoRouter`, after the `/home` route:

```dart
      GoRoute(
        path: '/ride/passenger',
        builder: (context, state) => const PassengerRidePage(),
      ),
      GoRoute(
        path: '/ride/driver',
        builder: (context, state) => const DriverInboxPage(),
      ),
```

In `_HomePageState.build`, add a CTA button after the existing `identity.when(...)` block (still inside the `Column`'s `children`):

```dart
              const SizedBox(height: 24),
              PrimaryButton(
                label: _mode == TakhiMode.passenger
                    ? l.startAsPassengerAction
                    : l.startAsDriverAction,
                onPressed: () => context.go(
                  _mode == TakhiMode.passenger
                      ? '/ride/passenger'
                      : '/ride/driver',
                ),
              ),
```

- [ ] **Step 9: Run the full app test suite and `flutter analyze`**

Run: `cd app && flutter gen-l10n && flutter test && flutter analyze`
Expected: every existing test (Plan 2's `home_page_test.dart`, `router_redirect_test.dart`, `onboarding_*_test.dart`, etc.) still PASSes alongside all of this plan's new tests; `flutter analyze` is clean. If `home_page_test.dart` or `router_redirect_test.dart` fail because they now find an extra `PrimaryButton`/`Text` widget ambiguity, add a `find.byType(PrimaryButton).evaluate().isNotEmpty` or more specific finder to the affected assertions — do not weaken the CTA's ARB-driven label to work around it.

- [ ] **Step 10: Commit**

```bash
git add app/lib/ride/ride_providers.dart app/lib/ride/passenger_ride_page.dart app/lib/ride/driver_inbox_page.dart app/lib/router.dart app/lib/l10n/app_mn.arb app/lib/l10n/app_en.arb app/test/ride/passenger_ride_page_test.dart
git commit -m "feat(app): passenger + driver ride screens wired end-to-end"
```

---

## Self-Review

**1. Spec coverage (§ / user scope item → task):**
- Scope item 1 (NIP-17 gift-wrap layer) → Task 1 ✓ (rumor/seal/wrap/unwrap, round-trip + spoofed-sender + wrong-recipient tests).
- Scope item 2 (ride request publish/cancel) → Task 4 ✓ (built on Tasks 2-3).
- Scope item 3 (driver inbox) → Task 5 ✓.
- Scope item 4 (offer DM + reputation-ranked selection) → Task 6 ✓ (built on Tasks 2-3).
- Scope item 5 (handoff: Plus Code + coordinates + landmark, passenger-minted trip_id) → Task 7 ✓.
- Scope item 6 (map: flutter_map/OSM, pin picking, Plus Code + free text, approximate driver-side markers) → Task 8 ✓.
- Scope item 7 (ride screens, passenger + driver, wired to map + services; ends at "exact location handed off") → Task 9 ✓.
- Spec §6 privacy tiering (public = geohash-6, selected driver = exact point, aggregate reputation view) → enforced structurally: `RideRequestListing` (Task 5) never carries lat/lon, only `RideRequest.pickupGeohash`; `NearbyRequestsLayer` (Task 8) can therefore only ever plot the geohash cell center; exact coordinates exist only inside `RideHandoffPayload`, which only ever travels NIP-17-wrapped to the one selected driver.
- Spec §9 (two-sided Sybil-resistant reputation) → reused directly via `computeReputation` (Plan 1) inside `rankRideOffers` (Task 6), with `viewerTrusted` threaded through from the passenger's own web-of-trust set.
- **Deferred to later plans, explicitly out of scope here (per the task brief):** taximeter and payment (§7.2, §7.4, §8) and dual trip receipts (§9's receipt-publishing side, as opposed to reading receipts, which Task 6 already does) → Plan 4. P2P calling/signaling and safety/SOS (§7.3, spec's `call/`/`safety/`) → Plan 5.
- **Gap noted honestly:** driver profile management (kind-0 extension with car/plate/km-tariff, spec §6 profile row) is not built here — `RideOfferPayload.vehicleDescription` is free text entered per-offer as an MVP stand-in. `DriverInboxPage` also tracks only one active engagement at a time (documented in its own doc comment) rather than a full multi-offer dashboard.

**2. Placeholder scan:** No `TODO`/`TBD`/"handle appropriately" anywhere. The one spot that looks unusual — Task 7 Step 7's first `HandoffService` draft with the `_poolOf` stub — is intentional: it's flagged inline as wrong and immediately replaced with the corrected final version before the step's test-passing gate, so the actual deliverable carries no placeholder. Task 6 Step 5's illustrative first `offer_service_test.dart` draft is likewise explicitly superseded by the real file before Step 6's run-and-commit gate. Task 8's `flutter_map`/`latlong2` version pin carries an explicit "verify against the resolved version" note, matching Plan 1 Task 8's precedent for `open_location_code` — not a placeholder, a documented external-dependency risk.

**3. Type consistency:** `RideDmPayload`/`RideOfferPayload`/`RideHandoffPayload`/`RideCancelPayload` (Task 2) are used with identical field names everywhere they're constructed or read (Tasks 3, 4, 6, 7, 9) — in particular `RideHandoffPayload.rideRequestId` and `RideOfferPayload.rideRequestId`, added specifically so `PassengerRidePage._select` and `DriverInboxPage` can correlate DMs back to a `RideRequestListing.rideRequestId` (Task 5). `RideDmChannel.send`/`.inbox` signatures (Task 3) match every caller in Tasks 4, 6, 7. `RankedRideOffer`/`rankRideOffers` (Task 6) signatures match their one caller in `_OffersStep` (Task 9). `PickedLocation`/`LocationPickerField`/`RideMap`/`NearbyRequestsLayer` (Task 8) signatures match their Task 9 call sites. `kKindGiftWrap`/`kKindSeal` (Task 1) and `kRumorKindRideDm` (Task 3) are defined exactly once each and referenced, never redefined, everywhere else.

## How NIP-17 was modeled

Standard NIP-59 three-layer envelope, implemented directly on Plan 1's `nip44Encrypt`/`nip44Decrypt`/`signEvent`/`verifyEvent` with no new crypto primitives:

```
rumor  (unsigned NostrEvent, id computed, sig=null, never published)
  │ NIP-44 encrypt(sender priv, recipient pub) + sign(sender priv)
  ▼
seal   (kind 13, tags=[], content=encrypted rumor)
  │ NIP-44 encrypt(ephemeral priv, recipient pub) + sign(ephemeral priv)
  ▼
gift wrap (kind 1059, tags=[['p', recipient]], created_at randomized into
           the past, content=encrypted seal)  <-- only this is published
```

`nip17Unwrap` reverses it and adds one check beyond a literal reversal: it verifies `rumor.pubkey == seal.pubkey` before trusting the rumor's self-reported sender, closing the spoofing gap where a signed-but-dishonest seal could otherwise wrap a rumor claiming a different identity. On top of generic NIP-17, the app layer (Task 3) adds a single dedicated rumor kind (`kRumorKindRideDm = 20179`) and a JSON `type`-discriminated payload schema (Task 2) so every ride DM — offer, handoff, cancellation — shares one send/inbox transport (`RideDmChannel`) instead of three.

## Open questions

1. **PoW difficulty (`kRideRequestPowDifficulty = 8`) is an MVP placeholder value**, not a finalized protocol constant — spec §16.3 already flags the final difficulty as pending PROTOCOL.md v0.1. Revisit once PoC field testing (spec §15) shows real mining/verification timings on target Android hardware.
2. **`flutter_map`/`latlong2` version pins (`^8.1.1`/`^0.9.1`) need confirmation** against whatever `flutter pub add` actually resolves at implementation time — `flutter_map`'s v6 rewrite changed several constructor parameter names; Task 8 Step 1 already carries the verification note.
3. **`DriverInboxPage`'s one-active-engagement simplification** (Task 9) will need to become a real multi-offer dashboard once drivers routinely have several concurrent requests open — reasonable to revisit in Plan 4 once the taximeter/trip-progress screens exist to model what "active" trip state looks like.
4. **Driver profile (kind-0 extension: car, plate, km-tariff) is not built in this plan.** `vehicleDescription` free text is a placeholder-by-design stand-in for it; a dedicated profile-editing task belongs in a later plan once the kind-0 extension schema is finalized.
