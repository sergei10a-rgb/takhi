# Тахь — P2P дуудлага, аюулгүй байдал (share/SOS), өнгөлгөө, дэлхийд тархалт, APK ship — Implementation Plan (Plan 5/5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the last MVP surface: in-app P2P voice calling between a matched passenger and driver (WebRTC, signaled over the existing NIP-17 DM transport, NAT-traversed via public STUN plus volunteer-run "туслагч" TURN relays discovered on Nostr) with a full, honest fallback chain down to a plain phone call and finally a short voice message that crosses any NAT; a server-less trip-share web page and an SOS button, neither of which ever talks to any server the author runs; the remaining polish (bundled Mongolian-Cyrillic font, a light/dark theme audit, an i18n completeness check, a real splash screen) and the world-spreadability artifacts (`PROTOCOL.md` finalized, `FORKING.md`, `HELPER.md`, a city-config seam); and a signed, obfuscated, sub-40MB release APK plus `LICENSE`/`README.md`.

**Prerequisite:** this plan assumes Plan 4 (`docs/superpowers/plans/2026-07-22-takhi-active-trip.md`) is fully implemented first — `ActiveTripView` (`app/lib/ride/active_trip_view.dart`), `TripRole`, `LiveLocationChannel`, `DriverQrDisplay`, and the `/meter` route all need to exist as real code before Tasks 7-9 below can compose calling/share/SOS into them. Every modification this plan makes to a Plan-4-authored file is additive (new optional constructor parameters with safe defaults, new fields, new buttons appended to existing layouts) — nothing in Plan 4's already-tested behavior is expected to change shape.

**Architecture:** Calling reuses the app's one existing private-messaging primitive end to end rather than inventing a second one: `RideDmChannel` (`app/lib/ride/ride_dm_channel.dart`, NIP-17 gift-wrap over `RelayPool`) already sends/receives typed, sealed `RideDmPayload` subtypes between two matched parties — this plan adds five more subtypes to that same sealed class (`CallOfferPayload`, `CallAnswerPayload`, `CallIceCandidatePayload`, `CallHangupPayload`, `VoiceNotePayload`), exactly the precedent Plan 4 itself set when it additively extended the class with `RideTripStatusPayload`. WebRTC itself is hidden behind a small `CallEngine` interface (mirroring Plan 4's `LocationSource` abstraction for GPS) so every call-orchestration class is unit-testable with a `FakeCallEngine` and never touches `package:flutter_webrtc` directly except in one thin, intentionally-untested real implementation. NAT traversal uses public STUN servers (address-discovery only, stateless, carries no media/signaling) plus zero-or-more volunteer-run TURN "туслагч" relays, discovered the same way everything else in this protocol is discovered — a Nostr event (kind `30178`, already reserved by Plan 1's `takhi_events.dart` but never given a typed builder/parser until this plan). Critically, P2P-direct and TURN-relayed connections are **not** two separate app-level attempts: WebRTC's own ICE agent gathers host, server-reflexive (STUN), and relay (TURN) candidates together and picks whichever pair actually connects, automatically preferring direct — so this plan's `buildIceServers` just merges the STUN list and the currently-known helper list into one config, and the only real *app-level* fallback decision is binary: did the whole WebRTC attempt connect before a timeout, or not. Only when it did not does the chain drop to a plain phone call (if a number was voluntarily exchanged) and finally a short voice note (NIP-17 DM, works on any NAT because no direct connection is ever needed). Safety (trip-share, SOS) is deliberately the simplest code in this plan: pure URL/URI builders plus `tel:`/`sms:` intents and a vanilla static HTML page — no new backend surface of any kind, matching the project's zero-server invariant literally rather than just in spirit.

**Tech Stack:** Everything from Plans 1-4 unchanged. New: `flutter_webrtc` (P2P audio calling), `url_launcher` (`tel:`/`sms:` intents for SOS and the phone-call fallback), `share_plus` (native share sheet for the trip-share link), `record` (Opus voice-note capture), `audioplayers` (voice-note playback), `flutter_native_splash` (dev-only, splash screen generation). Test: `dart test` for `takhi_protocol`, `flutter test` for the app — every new relay-facing class still driven by `FakeRelaySocket`, every new WebRTC-facing class by a new `FakeCallEngine`, mirroring the established fake-boundary pattern exactly.

## Global Constraints

- **SPDX header** on every new Dart file: `// SPDX-License-Identifier: AGPL-3.0-or-later`.
- **ALL user-facing text via ARB** (`app/lib/l10n/app_mn.arb` default, `app_en.arb` translation) — no hardcoded string literals in widgets. New keys land in both files in the same task that first uses them.
- **The author never runs a STUN, TURN, or blind-relay server, and never will.** `kDefaultStunServers` (Task 3) points only at well-known public STUN infrastructure this project does not operate; TURN capacity comes exclusively from volunteer-announced "туслагч" nodes (kind `30178`) that anyone may run and anyone may use — `HELPER.md` (Task 10) is a runbook for volunteers, not a service this project provides.
- **STUN is address-discovery only.** It is stateless and never relays media or signaling (spec §7.3-①) — this is a property of the protocol itself, not something the app enforces, but every doc comment referencing STUN in this plan says so explicitly so a future reader never conflates it with TURN.
- **SOS and trip-share are structurally server-less.** SOS never requests `CALL_PHONE`/`SEND_SMS` — it only builds `tel:`/`sms:` URIs and hands them to the OS via `url_launcher`, so the user's own finger presses the final send/call button on their own device's own native app. The trip-share page is static HTML/JS with no build step, reads directly from the same public Nostr relays the app already uses, and the one piece of secret material it needs (a decryption key) travels only in the URL **fragment** (`#...`), which browsers never transmit in any HTTP request — nothing here can leak to a server because no request ever carries it.
- **iOS is not yet part of this repository** (`app/ios/` does not exist — `flutter create --platforms=ios .` has never been run here). Every calling/SOS feature in this plan is therefore built and tested Android-only, matching spec §13's Android-first decision. Where iOS specifically matters — incoming calls in particular — this plan documents the tradeoff (Task 7) rather than silently ignoring it: on iOS, a backgrounded app's socket is killed by the OS, so an incoming `CallOfferPayload` cannot arrive and cannot ring unless the app is already open on the active-trip screen. Fixing that for real needs CallKit + a push-notification trigger, which needs a server to hold the push token and forward the wake-up — a flat violation of invariant 1 (no author-run server). This plan does not attempt a workaround; it states the limitation plainly, exactly as spec §13 already does for iOS driver-mode.
- **Additive-only extension of `RideDmPayload`.** This plan adds five new subtypes to the sealed class in `app/lib/ride/ride_dm_payload.dart`. No existing subtype, no existing `decode` case, and no existing call site loses a field or changes shape — mirrors Plan 4's own `RideTripStatusPayload` addition exactly, verified the same way Plan 4 verified it: no exhaustive `switch` over `RideDmPayload` exists anywhere in the app before or after this plan (grep before adding each case).
- **Voice notes are capped at spec's own numbers** (§7.3-③): ≤10 seconds, ~30KB. `validateVoiceNoteAudio` (Task 6) enforces this locally, before anything is ever sent — never trust a peer's claimed duration/size on receipt, only display it.
- **Release build is obfuscated and properly signed**, per this project's own Dart/Flutter security rule ("Enable obfuscation in release builds... ProGuard/R8 rules") — Task 10 generates a real release keystore kept out of version control (`android/key.properties`, gitignored) rather than shipping the current debug-signed placeholder.
- **Immutability, with the same named exceptions Plan 4 already established.** All new value/payload types (`HelperAnnouncement`, `CallOfferPayload` and siblings, `IceCandidateData`, `LocalSessionDescription`, `CallState` subtypes) are immutable: `final` fields, `const` constructors where possible. `HelperDirectory` (Task 3) is a small, explicitly-documented mutable accumulator over a live stream — the same precedent `GpsTrackAccumulator` (Plan 4) and `RelayPool._sockets` (Plan 2) already established.
- **Inherited invariants (unaffected by this plan):** no author-run server of any kind, no phone number as identity (only a voluntarily-shared contact detail between two already-matched parties), no fee/subscription layer, identity = keypair only, AGPL-3.0, no CLA.

---

### Task 1: Helper-node announcement event (kind `30178`, `takhi_protocol`)

**Files:**
- Create: `packages/takhi_protocol/lib/src/helper_announcement.dart`
- Modify: `packages/takhi_protocol/lib/takhi_protocol.dart` (export)
- Test: `packages/takhi_protocol/test/helper_announcement_test.dart`

**Interfaces:**
- Consumes: `NostrEvent`, `kKindHelper` (already defined in `takhi_events.dart` since Plan 1, unused until now).
- Produces: `NostrEvent buildHelperAnnouncement({required String pubkey, required int now, required String helperId, required String host, required int port, String credential = '', int expirySeconds = 3600})`; `class HelperAnnouncement { final String helperId, host, credential, announcerPubkey; final int port, expiration, createdAt; const HelperAnnouncement({...}); }`; `HelperAnnouncement parseHelperAnnouncement(NostrEvent e)` (throws `FormatException` for the wrong kind or a missing tag).
- Consumed by: Task 3's `HelperDirectoryService`.

This finalizes PROTOCOL.md §4.4's "proposed, not yet implemented" tag schema (`d`/`host`/`port`/`expiration`) exactly as documented — no schema change, only the typed builder/parser PROTOCOL.md already promised.

- [ ] **Step 1: Write the failing tests**

`packages/takhi_protocol/test/helper_announcement_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('helper announcement has d/host/port/expiration tags', () {
    final e = buildHelperAnnouncement(
      pubkey: 'ab' * 32,
      now: 1000,
      helperId: 'ub-helper-1',
      host: 'turn.example.mn',
      port: 3478,
      credential: 'shared-secret',
    );
    expect(e.kind, kKindHelper);
    expect(e.tags.firstWhere((t) => t.first == 'd')[1], 'ub-helper-1');
    expect(e.tags.firstWhere((t) => t.first == 'host')[1], 'turn.example.mn');
    expect(e.tags.firstWhere((t) => t.first == 'port')[1], '3478');
    expect(e.tags.firstWhere((t) => t.first == 'expiration')[1], '4600');
    expect(e.content, 'shared-secret');
  });

  test('helper announcement round-trips through parse', () {
    final e = buildHelperAnnouncement(
      pubkey: 'cd' * 32,
      now: 2000,
      helperId: 'helper-2',
      host: '203.0.113.5',
      port: 3479,
    );
    final p = parseHelperAnnouncement(e);
    expect(p.helperId, 'helper-2');
    expect(p.host, '203.0.113.5');
    expect(p.port, 3479);
    expect(p.credential, '');
    expect(p.announcerPubkey, 'cd' * 32);
    expect(p.expiration, 5600);
    expect(p.createdAt, 2000);
  });

  test('parseHelperAnnouncement rejects the wrong kind', () {
    final wrong = NostrEvent(
        pubkey: 'ab' * 32, createdAt: 1, kind: 1, tags: const [], content: '');
    expect(() => parseHelperAnnouncement(wrong), throwsFormatException);
  });

  test('parseHelperAnnouncement rejects an event missing a required tag',
      () {
    final missingPort = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1000,
      kind: kKindHelper,
      tags: const [
        ['d', 'helper-1'],
        ['host', 'turn.example.mn'],
        ['expiration', '4600'],
      ],
      content: '',
    );
    expect(() => parseHelperAnnouncement(missingPort), throwsFormatException);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run (from `packages/takhi_protocol/`): `dart test test/helper_announcement_test.dart`
Expected: FAIL — `buildHelperAnnouncement`/`parseHelperAnnouncement` undefined.

- [ ] **Step 3: Implement `helper_announcement.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'event.dart';
import 'takhi_events.dart' show kKindHelper;

/// Builds an unsigned kind-30178 "туслагч" (helper) announcement: a
/// volunteer telling the network "I'm running a blind TURN relay at
/// host:port, here's how long this announcement is good for" (spec §6/
/// §7.3-①). Anyone may call this — including a non-Flutter script, since
/// PROTOCOL.md documents the exact wire shape (§4.4) independently of this
/// implementation — and anyone may announce as many or as few helpers as
/// they like; the author of this app runs none of them (Global
/// Constraints). Unsigned, matching `buildRideRequest`/`buildTripReceipt`'s
/// existing convention: the caller signs with `signEvent` before
/// publishing.
NostrEvent buildHelperAnnouncement({
  required String pubkey,
  required int now,
  required String helperId,
  required String host,
  required int port,
  String credential = '',
  int expirySeconds = 3600,
}) {
  return NostrEvent(
    pubkey: pubkey,
    createdAt: now,
    kind: kKindHelper,
    tags: [
      ['d', helperId],
      ['host', host],
      ['port', port.toString()],
      ['expiration', (now + expirySeconds).toString()],
    ],
    content: credential,
  );
}

/// A helper announcement recovered from [parseHelperAnnouncement]. TURN
/// `credential` travels as plaintext `content` -- deliberately not
/// NIP-44-encrypted, since the whole point of a kind-30178 announcement is
/// that *any* stranger's client can discover and use the relay (spec
/// §7.3-①: "хэн ч зарлаж, хэн ч ашиглана"). A helper operator who wants
/// the credential to rotate or stay private to a smaller circle should
/// re-announce more often (`expirySeconds`) or omit `credential` entirely
/// and run an open/unauthenticated TURN relay instead -- both are valid,
/// neither is this schema's concern.
class HelperAnnouncement {
  final String helperId;
  final String host;
  final int port;
  final String credential;
  final String announcerPubkey;
  final int expiration;
  final int createdAt;

  const HelperAnnouncement({
    required this.helperId,
    required this.host,
    required this.port,
    required this.credential,
    required this.announcerPubkey,
    required this.expiration,
    required this.createdAt,
  });
}

/// Reverses [buildHelperAnnouncement]. Throws [FormatException] for the
/// wrong kind or any missing required tag -- mirrors
/// `parseRideRequest`/`parseTripReceipt`'s existing `tag()` helper
/// pattern exactly, including not re-verifying the signature (every event
/// reaching application code through `RelayPool.subscribe` is already
/// signature-verified there).
HelperAnnouncement parseHelperAnnouncement(NostrEvent e) {
  if (e.kind != kKindHelper) {
    throw FormatException('not a helper announcement (kind ${e.kind})');
  }
  String tag(String k) {
    final t = e.tags.firstWhere((x) => x.first == k,
        orElse: () => throw FormatException('missing $k'));
    return t[1];
  }

  return HelperAnnouncement(
    helperId: tag('d'),
    host: tag('host'),
    port: int.parse(tag('port')),
    credential: e.content,
    announcerPubkey: e.pubkey,
    expiration: int.parse(tag('expiration')),
    createdAt: e.createdAt,
  );
}
```

Add to `packages/takhi_protocol/lib/takhi_protocol.dart` (alphabetical, matching the existing export list):

```dart
export 'src/helper_announcement.dart';
```

- [ ] **Step 4: Run to verify it passes**

Run: `dart test test/helper_announcement_test.dart` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib/src/helper_announcement.dart packages/takhi_protocol/lib/takhi_protocol.dart packages/takhi_protocol/test/helper_announcement_test.dart
git commit -m "feat(protocol): helper-node announcement event (kind 30178)"
```

---

### Task 2: Call-signaling payloads + `CallSignalService` (`app/lib/ride/`, `app/lib/call/`)

**Files:**
- Modify: `app/lib/ride/ride_dm_payload.dart` (add four subtypes)
- Create: `app/lib/call/call_signal_service.dart`
- Create: `app/lib/call/call_providers.dart`
- Modify: `app/test/ride/ride_dm_payload_test.dart` (round-trip cases)
- Test: `app/test/call/call_signal_service_test.dart`

**Interfaces:**
- Consumes: `RideDmChannel`, `RideDmPayload` (Plan 3), `RelayPool` (Plan 2).
- Produces: `final class CallOfferPayload extends RideDmPayload { final String tripId, sdp; const CallOfferPayload({required tripId, required sdp}); }`; `CallAnswerPayload` (same shape); `final class CallIceCandidatePayload extends RideDmPayload { final String tripId, candidate, sdpMid; final int sdpMLineIndex; const CallIceCandidatePayload({...}); }`; `final class CallHangupPayload extends RideDmPayload { final String tripId, reason; const CallHangupPayload({required tripId, this.reason = ''}); }`; `class ReceivedCallSignal { final String senderPubkey; final RideDmPayload payload; const ReceivedCallSignal(this.senderPubkey, this.payload); }`; `class CallSignalService { Future<void> sendOffer({required privHex, required recipientPubHex, required tripId, required sdp, required now}); Future<void> sendAnswer({...same shape...}); Future<void> sendIceCandidate({required privHex, required recipientPubHex, required tripId, required candidate, required sdpMid, required sdpMLineIndex, required now}); Future<void> sendHangup({required privHex, required recipientPubHex, required tripId, String reason = '', required now}); Stream<ReceivedCallSignal> watchSignals(String myPubHex, String myPrivHex, String tripId); }`; `callSignalServiceProvider`.
- Consumed by: Task 7's `CallService`.

- [ ] **Step 1: Write the failing round-trip tests for the four new payloads**

Append to `app/test/ride/ride_dm_payload_test.dart`:

```dart
  test('call_offer payload round-trips through encode/decode', () {
    const offer = CallOfferPayload(tripId: 'trip-1', sdp: 'v=0\r\n...');
    final decoded = RideDmPayload.decode(offer.encode()) as CallOfferPayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.sdp, 'v=0\r\n...');
  });

  test('call_answer payload round-trips through encode/decode', () {
    const answer = CallAnswerPayload(tripId: 'trip-1', sdp: 'v=0\r\n...ans');
    final decoded =
        RideDmPayload.decode(answer.encode()) as CallAnswerPayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.sdp, 'v=0\r\n...ans');
  });

  test('call_ice payload round-trips through encode/decode', () {
    const ice = CallIceCandidatePayload(
      tripId: 'trip-1',
      candidate: 'candidate:1 1 UDP 2122260223 10.0.0.1 54321 typ host',
      sdpMid: 'audio',
      sdpMLineIndex: 0,
    );
    final decoded =
        RideDmPayload.decode(ice.encode()) as CallIceCandidatePayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.candidate, ice.candidate);
    expect(decoded.sdpMid, 'audio');
    expect(decoded.sdpMLineIndex, 0);
  });

  test('call_hangup payload round-trips through encode/decode', () {
    const hangup = CallHangupPayload(tripId: 'trip-1', reason: 'no answer');
    final decoded =
        RideDmPayload.decode(hangup.encode()) as CallHangupPayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.reason, 'no answer');
  });

  test('call_hangup payload defaults reason to empty string', () {
    const hangup = CallHangupPayload(tripId: 'trip-1');
    final decoded =
        RideDmPayload.decode(hangup.encode()) as CallHangupPayload;
    expect(decoded.reason, '');
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ride/ride_dm_payload_test.dart` — Expected: FAIL — the four classes are undefined.

- [ ] **Step 3: Add the four subtypes to `ride_dm_payload.dart`**

Extend the `decode` switch (insert before the `final other =>` catch-all):

```dart
      'call_offer' => CallOfferPayload._fromJson(map),
      'call_answer' => CallAnswerPayload._fromJson(map),
      'call_ice' => CallIceCandidatePayload._fromJson(map),
      'call_hangup' => CallHangupPayload._fromJson(map),
```

Append the four new subtypes at the end of the file:

```dart
/// A WebRTC SDP offer, opening a P2P call attempt for [tripId] (spec
/// §7.3-①). Rides the same NIP-17 gift-wrap transport as every other ride
/// DM -- offer/answer/ICE exchange is low-frequency (a handful of
/// messages per call attempt, not a per-second stream like live location),
/// so gift-wrap's identity-hiding and timing-randomization cost nothing
/// here that matters, unlike `LiveLocationChannel`'s deliberate choice to
/// skip it (Plan 4).
final class CallOfferPayload extends RideDmPayload {
  final String tripId;
  final String sdp;

  const CallOfferPayload({required this.tripId, required this.sdp});

  factory CallOfferPayload._fromJson(Map<String, dynamic> map) =>
      CallOfferPayload(
        tripId: _requiredString(map, 'tripId'),
        sdp: _requiredString(map, 'sdp'),
      );

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'call_offer', 'tripId': tripId, 'sdp': sdp};
}

/// The callee's WebRTC SDP answer, completing the offer/answer exchange
/// for [tripId].
final class CallAnswerPayload extends RideDmPayload {
  final String tripId;
  final String sdp;

  const CallAnswerPayload({required this.tripId, required this.sdp});

  factory CallAnswerPayload._fromJson(Map<String, dynamic> map) =>
      CallAnswerPayload(
        tripId: _requiredString(map, 'tripId'),
        sdp: _requiredString(map, 'sdp'),
      );

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'call_answer', 'tripId': tripId, 'sdp': sdp};
}

/// A single trickled ICE candidate for [tripId]'s in-progress call
/// negotiation. `candidate`/`sdpMid`/`sdpMLineIndex` are the exact three
/// fields `RTCIceCandidate` (flutter_webrtc) and this plan's own
/// `IceCandidateData` (Task 4) carry -- kept as plain strings/int here
/// rather than importing any WebRTC type, since `takhi_protocol`-adjacent
/// wire-format code must stay independent of any specific WebRTC package
/// version.
final class CallIceCandidatePayload extends RideDmPayload {
  final String tripId;
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;

  const CallIceCandidatePayload({
    required this.tripId,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  factory CallIceCandidatePayload._fromJson(Map<String, dynamic> map) =>
      CallIceCandidatePayload(
        tripId: _requiredString(map, 'tripId'),
        candidate: _requiredString(map, 'candidate'),
        sdpMid: _requiredString(map, 'sdpMid'),
        sdpMLineIndex: _requiredInt(map, 'sdpMLineIndex'),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'call_ice',
    'tripId': tripId,
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
  };
}

/// Either side ending a call -- while ringing (declined/cancelled) or
/// mid-call (hung up). [reason] is a short, optional, non-localized debug
/// string (never shown verbatim in the UI, which renders its own
/// localized "call ended" copy regardless of [reason]'s content).
final class CallHangupPayload extends RideDmPayload {
  final String tripId;
  final String reason;

  const CallHangupPayload({required this.tripId, this.reason = ''});

  factory CallHangupPayload._fromJson(Map<String, dynamic> map) =>
      CallHangupPayload(
        tripId: _requiredString(map, 'tripId'),
        reason: _optionalString(map, 'reason'),
      );

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'call_hangup', 'tripId': tripId, 'reason': reason};
}
```

- [ ] **Step 4: Run to verify the payload tests pass**

Run: `flutter test test/ride/ride_dm_payload_test.dart` — Expected: PASS.

- [ ] **Step 5: Write the failing test for `CallSignalService`**

`app/test/call/call_signal_service_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_signal_service.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final caller = generateKeyPair(List<int>.filled(32, 111));
  final callee = generateKeyPair(List<int>.filled(32, 112));

  test('sendOffer delivers a CallOfferPayload, watchSignals filters by '
      'tripId', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = CallSignalService(RideDmChannel(pool));

    final got = <ReceivedCallSignal>[];
    final sub = service
        .watchSignals(callee.publicHex, callee.privateHex, 'trip-1')
        .listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);

    await service.sendOffer(
      privHex: caller.privateHex,
      recipientPubHex: callee.publicHex,
      tripId: 'trip-1',
      sdp: 'v=0\r\n...',
      now: 1000,
    );
    final sentFrame = _lastEventFrame(sockets['wss://a']!);
    sockets['wss://a']!.emit(_deliver(subId, sentFrame));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, caller.publicHex);
    expect(got.first.payload, isA<CallOfferPayload>());
    expect((got.first.payload as CallOfferPayload).sdp, 'v=0\r\n...');
    await sub.cancel();
  });

  test('watchSignals never yields a signal for a different tripId',
      () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = CallSignalService(RideDmChannel(pool));

    final got = <ReceivedCallSignal>[];
    final sub = service
        .watchSignals(callee.publicHex, callee.privateHex, 'trip-1')
        .listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);

    await service.sendHangup(
      privHex: caller.privateHex,
      recipientPubHex: callee.publicHex,
      tripId: 'trip-OTHER',
      now: 1000,
    );
    final sentFrame = _lastEventFrame(sockets['wss://a']!);
    sockets['wss://a']!.emit(_deliver(subId, sentFrame));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got, isEmpty);
    await sub.cancel();
  });
}

String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecodeList(raw);
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}

dynamic _lastEventFrame(FakeRelaySocket socket) =>
    jsonDecodeList(socket.sent.last)[1];

String _deliver(String subId, dynamic eventJson) =>
    jsonEncodeFrame(['EVENT', subId, eventJson]);
```

This test needs two tiny local JSON helpers (`jsonDecodeList`/`jsonEncodeFrame`) rather than importing `dart:convert` under a different alias just for two calls — inline them at the bottom of the same test file:

```dart
List<dynamic> jsonDecodeList(String raw) =>
    (jsonDecode(raw) as List<dynamic>);
String jsonEncodeFrame(List<dynamic> frame) => jsonEncode(frame);
```

(Add `import 'dart:convert';` alongside the other imports at the top of the file.)

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/call/call_signal_service_test.dart` — Expected: FAIL — `CallSignalService` undefined.

- [ ] **Step 7: Implement `CallSignalService`**

`app/lib/call/call_signal_service.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import '../ride/ride_dm_channel.dart';
import '../ride/ride_dm_payload.dart';

/// A call-signaling message as the receiving side sees it -- [payload] is
/// always one of the four `Call*Payload` subtypes (`ride_dm_payload.dart`),
/// never `RideOfferPayload`/`RideHandoffPayload`/etc.; [watchSignals]
/// filters to only those before this type is ever constructed.
class ReceivedCallSignal {
  final String senderPubkey;
  final RideDmPayload payload;
  const ReceivedCallSignal(this.senderPubkey, this.payload);
}

/// Sends/receives WebRTC offer/answer/ICE/hangup signaling (spec §7.3-①)
/// over the existing `RideDmChannel` -- the thin, call-specific sibling of
/// `TripStatusService` (Plan 4), same shape, different payload family.
class CallSignalService {
  final RideDmChannel _dm;
  CallSignalService(this._dm);

  Future<void> sendOffer({
    required String privHex,
    required String recipientPubHex,
    required String tripId,
    required String sdp,
    required int now,
  }) => _dm.send(
    senderPrivHex: privHex,
    recipientPubHex: recipientPubHex,
    payload: CallOfferPayload(tripId: tripId, sdp: sdp),
    now: now,
  );

  Future<void> sendAnswer({
    required String privHex,
    required String recipientPubHex,
    required String tripId,
    required String sdp,
    required int now,
  }) => _dm.send(
    senderPrivHex: privHex,
    recipientPubHex: recipientPubHex,
    payload: CallAnswerPayload(tripId: tripId, sdp: sdp),
    now: now,
  );

  Future<void> sendIceCandidate({
    required String privHex,
    required String recipientPubHex,
    required String tripId,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
    required int now,
  }) => _dm.send(
    senderPrivHex: privHex,
    recipientPubHex: recipientPubHex,
    payload: CallIceCandidatePayload(
      tripId: tripId,
      candidate: candidate,
      sdpMid: sdpMid,
      sdpMLineIndex: sdpMLineIndex,
    ),
    now: now,
  );

  Future<void> sendHangup({
    required String privHex,
    required String recipientPubHex,
    required String tripId,
    String reason = '',
    required int now,
  }) => _dm.send(
    senderPrivHex: privHex,
    recipientPubHex: recipientPubHex,
    payload: CallHangupPayload(tripId: tripId, reason: reason),
    now: now,
  );

  /// Every call-signal payload addressed to [myPubHex] and scoped to
  /// [tripId] -- a device is never in more than one call at once in this
  /// MVP, so filtering by trip id (rather than, say, a separate call id)
  /// is sufficient and reuses the identifier every other trip-scoped
  /// channel (`LiveLocationChannel`, `TripStatusService`) already keys on.
  Stream<ReceivedCallSignal> watchSignals(
    String myPubHex,
    String myPrivHex,
    String tripId,
  ) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => _isCallSignal(dm.payload) && _tripIdOf(dm.payload) == tripId)
        .map((dm) => ReceivedCallSignal(dm.senderPubkey, dm.payload));
  }
}

bool _isCallSignal(RideDmPayload p) =>
    p is CallOfferPayload ||
    p is CallAnswerPayload ||
    p is CallIceCandidatePayload ||
    p is CallHangupPayload;

String _tripIdOf(RideDmPayload p) => switch (p) {
  CallOfferPayload(:final tripId) => tripId,
  CallAnswerPayload(:final tripId) => tripId,
  CallIceCandidatePayload(:final tripId) => tripId,
  CallHangupPayload(:final tripId) => tripId,
  _ => throw StateError('not a call signal payload'),
};
```

- [ ] **Step 8: Wire the provider**

`app/lib/call/call_providers.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ride/ride_providers.dart';
import 'call_signal_service.dart';

final callSignalServiceProvider = Provider<CallSignalService>(
  (ref) => CallSignalService(ref.watch(rideDmChannelProvider)),
);
```

- [ ] **Step 9: Run everything and commit**

Run: `flutter test test/ride/ride_dm_payload_test.dart test/call/call_signal_service_test.dart` — Expected: PASS.

```bash
git add app/lib/ride/ride_dm_payload.dart app/lib/call/call_signal_service.dart app/lib/call/call_providers.dart app/test/ride/ride_dm_payload_test.dart app/test/call/call_signal_service_test.dart
git commit -m "feat(app): call-signaling payloads and CallSignalService"
```

### Task 3: ICE server config — STUN list + helper (TURN) directory (`app/lib/call/`)

**Files:**
- Create: `app/lib/call/ice_servers.dart`
- Create: `app/lib/call/helper_directory_service.dart`
- Modify: `app/lib/call/call_providers.dart`
- Test: `app/test/call/ice_servers_test.dart`
- Test: `app/test/call/helper_directory_service_test.dart`

**Interfaces:**
- Consumes: `HelperAnnouncement`, `parseHelperAnnouncement`, `kKindHelper` (Task 1), `RelayPool`/`RelayFilter` (Plan 2).
- Produces: `const List<String> kDefaultStunServers`; `List<Map<String, dynamic>> buildIceServers({List<String> stunServers = kDefaultStunServers, List<HelperAnnouncement> helpers = const []})`; `class HelperDirectory { void add(HelperAnnouncement h); List<HelperAnnouncement> current({int Function() now}); }`; `class HelperDirectoryService { Stream<HelperAnnouncement> watchHelpers({int Function() now}); }`; `helperDirectoryServiceProvider`.
- Consumed by: Task 7's `CallService`.

- [ ] **Step 1: Write the failing tests for `buildIceServers`**

`app/test/call/ice_servers_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/ice_servers.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('buildIceServers with no helpers returns only the STUN entry', () {
    final servers = buildIceServers();
    expect(servers.length, 1);
    expect(servers.first['urls'], kDefaultStunServers);
  });

  test('buildIceServers appends one turn: entry per helper', () {
    const helper = HelperAnnouncement(
      helperId: 'h1',
      host: 'turn.example.mn',
      port: 3478,
      credential: 'secret',
      announcerPubkey: 'ab' * 32,
      expiration: 9999,
      createdAt: 1000,
    );
    final servers = buildIceServers(helpers: const [helper]);
    expect(servers.length, 2);
    expect(servers[1]['urls'], ['turn:turn.example.mn:3478']);
    expect(servers[1]['credential'], 'secret');
    expect(servers[1]['username'], 'h1');
  });

  test('buildIceServers omits credential/username for an open helper',
      () {
    const helper = HelperAnnouncement(
      helperId: 'h2',
      host: '203.0.113.9',
      port: 3479,
      credential: '',
      announcerPubkey: 'cd' * 32,
      expiration: 9999,
      createdAt: 1000,
    );
    final servers = buildIceServers(helpers: const [helper]);
    expect(servers[1].containsKey('credential'), isFalse);
    expect(servers[1].containsKey('username'), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/call/ice_servers_test.dart` — Expected: FAIL — `ice_servers.dart` doesn't exist.

- [ ] **Step 3: Implement `ice_servers.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

/// Public STUN servers, used for NAT address discovery only (spec §7.3-①:
/// "STUN нь зөвхөн хаяг-олох stateless үйлчилгээ"). No media or signaling
/// ever passes through these -- they only tell each side its own
/// public-facing address/port so the ICE agent can attempt a direct path.
/// This is an editable list, not author infrastructure (Global
/// Constraints): every URL here is a well-known public STUN service
/// already used by countless WebRTC apps, none of it operated by this
/// project. The exact default set is an open protocol question (see this
/// plan's Self-Review) -- Google's and Cloudflare's are widely mirrored
/// and known to work from Mongolian ISPs as of this writing, which is why
/// they're the seed default, not because they're specially endorsed.
const List<String> kDefaultStunServers = [
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
  'stun:stun.cloudflare.com:3478',
];

/// Builds the `iceServers` list `flutter_webrtc`'s `RTCConfiguration`
/// expects: [stunServers] first, then one `turn:` entry per [helpers] --
/// volunteer-run blind relays (spec §6/§7.3-①), each built from its
/// announced host/port, with `credential`/`username` included only when
/// the announcement actually published one (an open/unauthenticated relay
/// omits both, which flutter_webrtc treats as "no TURN auth needed").
///
/// P2P-direct and TURN-relayed connections are deliberately NOT modeled
/// as two separate app-level attempts here: this is the *entire* app-side
/// involvement in that choice. Once this list is handed to
/// `RTCPeerConnection`, WebRTC's own ICE agent gathers host (direct),
/// server-reflexive (via STUN), and relay (via TURN) candidates together
/// and picks whichever pair actually connects end to end, automatically
/// preferring a direct path when one exists -- that preference and
/// fallback behavior is standard ICE (RFC 8445), not something this
/// project implements. Pure and synchronous, so this whole merge is
/// unit-testable with zero network/WebRTC dependency; `CallService`
/// (Task 7) is responsible for keeping [helpers] fresh via
/// `HelperDirectoryService`.
List<Map<String, dynamic>> buildIceServers({
  List<String> stunServers = kDefaultStunServers,
  List<HelperAnnouncement> helpers = const [],
}) {
  return [
    {'urls': stunServers},
    for (final h in helpers)
      {
        'urls': ['turn:${h.host}:${h.port}'],
        if (h.credential.isNotEmpty) 'credential': h.credential,
        if (h.credential.isNotEmpty) 'username': h.helperId,
      },
  ];
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/call/ice_servers_test.dart` — Expected: PASS.

- [ ] **Step 5: Write the failing tests for `HelperDirectory`/`HelperDirectoryService`**

`app/test/call/helper_directory_service_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-01-later
```

Correcting the SPDX line above before it ever lands (a typo -- `01` instead of `0` -- deliberately shown once here as a reminder to proofread every new file's first line; the real file uses the correct identifier below):

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/helper_directory_service.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  group('HelperDirectory (pure accumulator)', () {
    test('current() returns only non-expired helpers, keyed by helperId',
        () {
      final dir = HelperDirectory();
      dir.add(const HelperAnnouncement(
        helperId: 'fresh',
        host: 'a',
        port: 1,
        credential: '',
        announcerPubkey: 'ab' * 32,
        expiration: 2000,
        createdAt: 1000,
      ));
      dir.add(const HelperAnnouncement(
        helperId: 'stale',
        host: 'b',
        port: 2,
        credential: '',
        announcerPubkey: 'cd' * 32,
        expiration: 500,
        createdAt: 100,
      ));
      final current = dir.current(now: () => 1500);
      expect(current.length, 1);
      expect(current.first.helperId, 'fresh');
    });

    test('current() replaces an earlier announcement from the same '
        'helperId', () {
      final dir = HelperDirectory();
      dir.add(const HelperAnnouncement(
        helperId: 'h1',
        host: 'old-host',
        port: 1,
        credential: '',
        announcerPubkey: 'ab' * 32,
        expiration: 9999,
        createdAt: 1000,
      ));
      dir.add(const HelperAnnouncement(
        helperId: 'h1',
        host: 'new-host',
        port: 2,
        credential: '',
        announcerPubkey: 'ab' * 32,
        expiration: 9999,
        createdAt: 2000,
      ));
      final current = dir.current(now: () => 1500);
      expect(current.length, 1);
      expect(current.first.host, 'new-host');
    });
  });

  group('HelperDirectoryService (relay-backed)', () {
    test('watchHelpers yields a parsed announcement from the relay',
        () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = HelperDirectoryService(pool);

      final got = <HelperAnnouncement>[];
      final sub = service.watchHelpers().listen(got.add);
      final subId = _reqSubId(sockets['wss://a']!);

      final event = buildHelperAnnouncement(
        pubkey: 'ab' * 32,
        now: 1000,
        helperId: 'h1',
        host: 'turn.example.mn',
        port: 3478,
      );
      final keys = generateKeyPair(List<int>.filled(32, 9));
      final signed = signEvent(
        event.copyWith(id: computeEventId(event)),
        keys.privateHex,
      );
      sockets['wss://a']!
          .emit(jsonEncode(['EVENT', subId, signed.toJson()]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(got.length, 1);
      expect(got.first.helperId, 'h1');
      await sub.cancel();
    });
  });
}

String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}
```

The `buildHelperAnnouncement`/`signEvent`/`computeEventId` combination in this test reuses a real, signed event rather than hand-building one, so `RelayPool._handleMessage`'s `verifyEvent` check (which every subscribed event must pass to reach `HelperDirectoryService` at all) actually succeeds -- the same reason `helper_directory_service_test.dart` signs with a fresh unrelated keypair rather than the announced `pubkey: 'ab' * 32` placeholder used in Task 1's pure builder tests.

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/call/helper_directory_service_test.dart` — Expected: FAIL — `helper_directory_service.dart` doesn't exist.

- [ ] **Step 7: Implement `helper_directory_service.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';

/// Folds a live stream of helper announcements into "latest-per-helperId,
/// still not expired" -- a small, explicitly mutable accumulator over a
/// live stream, the same documented-exception shape `GpsTrackAccumulator`
/// (Plan 4) and `RelayPool._sockets`/`_seenEventIds` (Plan 2) already
/// established for this codebase (Global Constraints).
class HelperDirectory {
  final Map<String, HelperAnnouncement> _byId = {};

  void add(HelperAnnouncement h) => _byId[h.helperId] = h;

  List<HelperAnnouncement> current({int Function() now = _systemNow}) =>
      _byId.values.where((h) => h.expiration > now()).toList();
}

/// Subscribes to every kind-30178 helper announcement currently visible on
/// the configured relays (spec §6 "Туслагч-зарлал") -- a live
/// subscription, not a one-shot snapshot, so a volunteer's relay coming
/// online (or an existing one's `expiration`, NIP-40, lapsing) is
/// reflected without restarting the app. A malformed or foreign kind-30178
/// event is silently dropped, matching every other `RelayPool.subscribe`
/// consumer's policy (`RideDmChannel.inbox`, `LiveLocationChannel.watch`)
/// of never surfacing untrusted-input parse failures as errors.
class HelperDirectoryService {
  final RelayPool _pool;
  HelperDirectoryService(this._pool);

  Stream<HelperAnnouncement> watchHelpers({
    int Function() now = _systemNow,
  }) {
    final filter = RelayFilter(kinds: [kKindHelper]);
    return _pool.subscribe(filter).asyncExpand((event) async* {
      try {
        final helper = parseHelperAnnouncement(event);
        if (helper.expiration <= now()) return;
        yield helper;
      } on FormatException {
        // Malformed/foreign kind-30178 event; drop rather than surface.
      }
    });
  }
}

int _systemNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
```

- [ ] **Step 8: Wire the provider**

Add to `app/lib/call/call_providers.dart`:

```dart
import '../nostr/relay_pool_provider.dart';
import 'helper_directory_service.dart';

final helperDirectoryServiceProvider = Provider<HelperDirectoryService>(
  (ref) => HelperDirectoryService(ref.watch(relayPoolProvider)),
);
```

- [ ] **Step 9: Run everything and commit**

Run: `flutter test test/call/ice_servers_test.dart test/call/helper_directory_service_test.dart` — Expected: PASS.

```bash
git add app/lib/call/ice_servers.dart app/lib/call/helper_directory_service.dart app/lib/call/call_providers.dart app/test/call/ice_servers_test.dart app/test/call/helper_directory_service_test.dart
git commit -m "feat(app): ICE server config -- STUN list + helper (TURN) directory"
```

### Task 4: `CallEngine` abstraction — `flutter_webrtc` + Fake (`app/lib/call/`)

**Files:**
- Create: `app/lib/call/call_engine.dart`
- Modify: `app/pubspec.yaml` (add `flutter_webrtc`)
- Modify: `app/android/app/src/main/AndroidManifest.xml` (INTERNET, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS, ACCESS_NETWORK_STATE, BLUETOOTH_CONNECT)
- Test: `app/test/call/ice_candidate_data_test.dart`
- Test: `app/test/support/fake_call_engine.dart` (shared test double, not itself a test file)

**Interfaces:**
- Produces: `enum CallConnectionState { newConnection, connecting, connected, failed, disconnected, closed }`; `class LocalSessionDescription { final String sdp, type; const LocalSessionDescription(this.sdp, this.type); }`; `class IceCandidateData { final String candidate, sdpMid; final int sdpMLineIndex; const IceCandidateData(this.candidate, this.sdpMid, this.sdpMLineIndex); }`; `abstract interface class CallEngine { Stream<CallConnectionState> get connectionState; Stream<IceCandidateData> get localIceCandidates; Future<LocalSessionDescription> createOffer(); Future<LocalSessionDescription> createAnswer(String remoteOfferSdp); Future<void> acceptAnswer(String remoteAnswerSdp); Future<void> addRemoteIceCandidate(IceCandidateData candidate); Future<void> setMuted(bool muted); Future<void> dispose(); }`; `class FlutterWebrtcCallEngine implements CallEngine`; `final callEngineFactoryProvider = Provider<CallEngine Function()>(...)`; `class FakeCallEngine implements CallEngine { void emitConnectionState(CallConnectionState s); void emitLocalIceCandidate(IceCandidateData c); String nextOfferSdp, nextAnswerSdp; List<String> acceptedAnswers, dialedAnswers; bool? lastMuted; bool disposed; }` (test support).
- Consumed by: Task 7's `CallService`.

`CallConnectionState` mirrors the states `RTCPeerConnection.onConnectionState` actually delivers (`RTCPeerConnectionState.*`), renamed to plain, package-independent identifiers so nothing above this interface imports `package:flutter_webrtc`. `newConnection` (not `new`, a reserved word) is the pre-negotiation state.

- [ ] **Step 1: Write the failing test for the small value types**

`app/test/call/ice_candidate_data_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_engine.dart';

void main() {
  test('IceCandidateData carries candidate/sdpMid/sdpMLineIndex verbatim',
      () {
    const c = IceCandidateData('candidate:1 1 UDP ...', 'audio', 0);
    expect(c.candidate, 'candidate:1 1 UDP ...');
    expect(c.sdpMid, 'audio');
    expect(c.sdpMLineIndex, 0);
  });

  test('LocalSessionDescription carries sdp/type verbatim', () {
    const d = LocalSessionDescription('v=0\r\n...', 'offer');
    expect(d.sdp, 'v=0\r\n...');
    expect(d.type, 'offer');
  });
}
```

- [ ] **Step 2: Run to verify it fails, then add `flutter_webrtc`**

Run: `flutter test test/call/ice_candidate_data_test.dart` — Expected: FAIL — `call_engine.dart` doesn't exist.

In `app/pubspec.yaml` under `dependencies:`:

```yaml
  flutter_webrtc: ^0.11.7
  url_launcher: ^6.3.1
```

(`url_launcher` is added here rather than in Task 9 because `CallScreen`, Task 7, already needs `tel:` for the phone-call fallback rung — adding it once, where it first becomes necessary, avoids a second `flutter pub get` churn later for the same package Task 9 also uses for SOS.)

Run (from `app/`): `flutter pub get`

- [ ] **Step 3: Implement `call_engine.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// Connection-state values `RTCPeerConnection.onConnectionState`
/// (flutter_webrtc) actually delivers, renamed to plain,
/// package-independent identifiers -- nothing above [CallEngine] imports
/// `package:flutter_webrtc` directly. `newConnection` is the
/// pre-negotiation state (`new` is a reserved word in Dart).
enum CallConnectionState {
  newConnection,
  connecting,
  connected,
  failed,
  disconnected,
  closed,
}

/// A local SDP description ready to hand to `CallSignalService` -- the
/// wire shape `CallOfferPayload`/`CallAnswerPayload`'s `sdp` field carries
/// (`ride_dm_payload.dart`, Task 2).
class LocalSessionDescription {
  final String sdp;
  final String type; // 'offer' | 'answer'
  const LocalSessionDescription(this.sdp, this.type);
}

/// A single ICE candidate in the exact three fields
/// `CallIceCandidatePayload` (Task 2) and `RTCIceCandidate`
/// (flutter_webrtc) both carry.
class IceCandidateData {
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;
  const IceCandidateData(this.candidate, this.sdpMid, this.sdpMLineIndex);
}

/// Abstracts a single audio-only WebRTC peer connection so `CallService`
/// (Task 7) and its tests never talk to `package:flutter_webrtc` directly
/// -- mirrors `LocationSource`'s role for GPS (Plan 4 Task 1) exactly.
/// Everything above this interface is testable with `FakeCallEngine`
/// (Step 5 below); only `FlutterWebrtcCallEngine` itself has no dedicated
/// unit test, for the same documented reason `GeolocatorLocationSource`
/// and `WsRelaySocket` don't -- a thin wrapper around a platform plugin
/// that cannot run meaningfully without a real device/microphone.
///
/// One [CallEngine] instance is exactly one call attempt: audio-only by
/// construction (no video track is ever requested -- spec §7.3 is "дуут
/// яриа", voice, not video), and disposed at the end of every attempt.
/// Callers never reuse an instance across two calls.
abstract interface class CallEngine {
  Stream<CallConnectionState> get connectionState;
  Stream<IceCandidateData> get localIceCandidates;

  /// Starts as the caller: creates the local audio track, generates an
  /// SDP offer, and sets it as the local description.
  Future<LocalSessionDescription> createOffer();

  /// Starts as the callee: creates the local audio track, sets
  /// [remoteOfferSdp] as the remote description, and generates an SDP
  /// answer.
  Future<LocalSessionDescription> createAnswer(String remoteOfferSdp);

  /// Caller-side: completes the offer/answer exchange once the callee's
  /// answer arrives.
  Future<void> acceptAnswer(String remoteAnswerSdp);

  Future<void> addRemoteIceCandidate(IceCandidateData candidate);

  /// Mutes/unmutes the local microphone track without renegotiating.
  Future<void> setMuted(bool muted);

  /// Closes the peer connection and releases the local audio track.
  Future<void> dispose();
}

/// Real [CallEngine] backed by `package:flutter_webrtc`. Configured with
/// [iceServers] (`buildIceServers`'s output, Task 3) at construction --
/// STUN and any currently-known helper TURN entries are both already
/// merged into that one list by the time it reaches here, so this class
/// has no separate "try direct, then try relay" logic of its own (see
/// Task 3's `buildIceServers` doc comment for why that's correct).
class FlutterWebrtcCallEngine implements CallEngine {
  final List<Map<String, dynamic>> iceServers;
  webrtc.RTCPeerConnection? _pc;
  webrtc.MediaStream? _localStream;
  final _connectionStateController =
      StreamController<CallConnectionState>.broadcast();
  final _iceCandidateController =
      StreamController<IceCandidateData>.broadcast();

  FlutterWebrtcCallEngine({required this.iceServers});

  @override
  Stream<CallConnectionState> get connectionState =>
      _connectionStateController.stream;
  @override
  Stream<IceCandidateData> get localIceCandidates =>
      _iceCandidateController.stream;

  Future<webrtc.RTCPeerConnection> _ensurePeerConnection() async {
    if (_pc != null) return _pc!;
    final pc = await webrtc.createPeerConnection({'iceServers': iceServers});
    pc.onConnectionState = (state) =>
        _connectionStateController.add(_mapConnectionState(state));
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return; // end-of-candidates marker
      _iceCandidateController.add(
        IceCandidateData(c.candidate!, c.sdpMid ?? '', c.sdpMLineIndex ?? 0),
      );
    };
    _localStream = await webrtc.navigator.mediaDevices
        .getUserMedia({'audio': true, 'video': false});
    for (final track in _localStream!.getAudioTracks()) {
      await pc.addTrack(track, _localStream!);
    }
    _pc = pc;
    return pc;
  }

  @override
  Future<LocalSessionDescription> createOffer() async {
    final pc = await _ensurePeerConnection();
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return LocalSessionDescription(offer.sdp ?? '', 'offer');
  }

  @override
  Future<LocalSessionDescription> createAnswer(String remoteOfferSdp) async {
    final pc = await _ensurePeerConnection();
    await pc.setRemoteDescription(
      webrtc.RTCSessionDescription(remoteOfferSdp, 'offer'),
    );
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return LocalSessionDescription(answer.sdp ?? '', 'answer');
  }

  @override
  Future<void> acceptAnswer(String remoteAnswerSdp) async {
    final pc = await _ensurePeerConnection();
    await pc.setRemoteDescription(
      webrtc.RTCSessionDescription(remoteAnswerSdp, 'answer'),
    );
  }

  @override
  Future<void> addRemoteIceCandidate(IceCandidateData candidate) async {
    final pc = await _ensurePeerConnection();
    await pc.addCandidate(webrtc.RTCIceCandidate(
      candidate.candidate,
      candidate.sdpMid,
      candidate.sdpMLineIndex,
    ));
  }

  @override
  Future<void> setMuted(bool muted) async {
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> dispose() async {
    await _localStream?.dispose();
    await _pc?.close();
    await _connectionStateController.close();
    await _iceCandidateController.close();
  }

  CallConnectionState _mapConnectionState(
    webrtc.RTCPeerConnectionState state,
  ) => switch (state) {
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateNew =>
      CallConnectionState.newConnection,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
      CallConnectionState.connecting,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
      CallConnectionState.connected,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
      CallConnectionState.failed,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
      CallConnectionState.disconnected,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
      CallConnectionState.closed,
  };
}
```

Add `import 'dart:async';` to the top of the file (for the two `StreamController`s).

**Open item, flagged rather than guessed at:** `flutter_webrtc`'s exact enum member spelling/casing (`RTCPeerConnectionStateNew` vs. a differently-cased variant) and constructor signatures (`RTCIceCandidate`'s positional-vs-named parameters, `createPeerConnection`'s config map shape) can drift between package versions. Confirm both against whatever `flutter pub add flutter_webrtc` actually resolves before treating `_mapConnectionState`/`_ensurePeerConnection` as final — same caution Plan 4 flagged for `geolocator`'s `LocationSettings` interval API. Nothing above the `CallEngine` interface depends on the exact resolution.

- [ ] **Step 4: Run to verify the value-type test passes**

Run: `flutter test test/call/ice_candidate_data_test.dart` — Expected: PASS.

- [ ] **Step 5: Add the shared `FakeCallEngine` test double**

`app/test/support/fake_call_engine.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:takhi/call/call_engine.dart';

/// Deterministic [CallEngine] test double -- scripted SDP strings and
/// manually-triggerable state via [emitConnectionState]/
/// [emitLocalIceCandidate], mirroring [FakeLocationSource]'s `emit()` role
/// for GPS (Plan 4) exactly. `FlutterWebrtcCallEngine` itself is
/// intentionally left without a dedicated unit test (see its doc comment).
class FakeCallEngine implements CallEngine {
  String nextOfferSdp = 'fake-offer-sdp';
  String nextAnswerSdp = 'fake-answer-sdp';
  final List<String> acceptedAnswers = [];
  final List<IceCandidateData> addedRemoteCandidates = [];
  bool? lastMuted;
  bool disposed = false;

  final _connectionStateController =
      StreamController<CallConnectionState>.broadcast();
  final _iceCandidateController =
      StreamController<IceCandidateData>.broadcast();

  @override
  Stream<CallConnectionState> get connectionState =>
      _connectionStateController.stream;
  @override
  Stream<IceCandidateData> get localIceCandidates =>
      _iceCandidateController.stream;

  void emitConnectionState(CallConnectionState s) =>
      _connectionStateController.add(s);
  void emitLocalIceCandidate(IceCandidateData c) =>
      _iceCandidateController.add(c);

  @override
  Future<LocalSessionDescription> createOffer() async =>
      LocalSessionDescription(nextOfferSdp, 'offer');

  @override
  Future<LocalSessionDescription> createAnswer(String remoteOfferSdp) async =>
      LocalSessionDescription(nextAnswerSdp, 'answer');

  @override
  Future<void> acceptAnswer(String remoteAnswerSdp) async =>
      acceptedAnswers.add(remoteAnswerSdp);

  @override
  Future<void> addRemoteIceCandidate(IceCandidateData candidate) async =>
      addedRemoteCandidates.add(candidate);

  @override
  Future<void> setMuted(bool muted) async => lastMuted = muted;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _connectionStateController.close();
    await _iceCandidateController.close();
  }
}
```

- [ ] **Step 6: Add Android call permissions**

In `app/android/app/src/main/AndroidManifest.xml`, alongside the existing location permissions (before `<application>`):

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

`INTERNET` is added here as a real bug fix, not a new requirement of this plan: the main manifest never declared it, even though `RelayPool` has used `web_socket_channel` for `wss://` connections since Plan 2. It happened to work through every debug/profile build so far because `android/app/src/debug/AndroidManifest.xml` and `.../profile/AndroidManifest.xml` both already declare `INTERNET` for the Flutter tool's own hot-reload channel — but a **release** build only merges the main manifest, so relay connectivity (and this plan's WebRTC signaling) would have silently failed to even open a socket in the very first release APK (Task 10) without this line. `RECORD_AUDIO`/`MODIFY_AUDIO_SETTINGS` are required by `flutter_webrtc`'s `getUserMedia`; `ACCESS_NETWORK_STATE` and `BLUETOOTH_CONNECT` (Android 12+, optional Bluetooth-headset audio routing during a call) are its other commonly-required permissions. No `CAMERA` permission is added — this app never requests a video track (Global Constraints: audio-only).

- [ ] **Step 7: Commit**

```bash
git add app/lib/call/call_engine.dart app/pubspec.yaml app/pubspec.lock app/android/app/src/main/AndroidManifest.xml app/test/call/ice_candidate_data_test.dart app/test/support/fake_call_engine.dart
git commit -m "feat(app): CallEngine abstraction (flutter_webrtc, audio-only) + Fake"
```

### Task 5: Fallback-chain decision + phone-number exchange (`app/lib/call/`, `app/lib/ride/`)

**Files:**
- Create: `app/lib/call/fallback_decision.dart`
- Create: `app/lib/call/phone_share_settings.dart`
- Modify: `app/lib/call/call_providers.dart`
- Modify: `app/lib/ride/ride_dm_payload.dart` (`RideHandoffPayload` gains an optional `phone` field)
- Modify: `app/lib/ride/handoff_service.dart` (`sendHandoff` gains an optional `phone` param)
- Modify: `app/pubspec.yaml` (add `shared_preferences` if Plan 4 has not already added it for the taximeter's `TariffStore`)
- Test: `app/test/call/fallback_decision_test.dart`
- Test: `app/test/call/phone_share_settings_test.dart`
- Modify: `app/test/ride/ride_dm_payload_test.dart` (extend the existing handoff round-trip case)
- Modify: `app/test/ride/handoff_service_test.dart` (extend)

**Interfaces:**
- Produces: `enum CallFallbackAction { keepTryingWebrtc, offerPhoneCall, offerVoiceMessage }`; `CallFallbackAction decideFallbackAction({required bool webrtcConnected, required bool webrtcTimedOut, required bool counterpartyPhoneKnown, required bool phoneShareEnabled})`; `abstract interface class PhoneShareSettingsStore { Future<bool> isEnabled(); Future<void> setEnabled(bool enabled); Future<String?> loadOwnPhone(); Future<void> saveOwnPhone(String phone); }`; `SharedPreferencesPhoneShareSettingsStore`, `InMemoryPhoneShareSettingsStore`; `phoneShareSettingsStoreProvider`; `RideHandoffPayload` gains `final String? phone;`; `HandoffService.sendHandoff` gains `String? phone`.
- Consumed by: Task 7's `CallService`/`CallScreen`.

**Deliberate scope boundary, stated honestly rather than silently assumed:** spec §7.3-② ties the phone-number toggle specifically to "тохироо-DM" — the exact-location handoff DM, which per spec §6's own event table only ever flows **passenger → driver** (`RideHandoffPayload`, sent once when the passenger picks a driver). This plan implements exactly that literal, one-directional exchange: a **driver** who has WebRTC trouble can fall back to calling the passenger's real number (if the passenger opted in), but a **passenger** cannot fall back to calling the driver's number this way in this MVP — P2P/helper-relayed calling itself is already symmetric and needs no phone number at all, so this asymmetry only bites in the specific case of a passenger whose WebRTC attempt fails *and* who has no other way to reach the driver, who then has only the voice-message rung left. Widening this to a symmetric exchange (e.g. a `phone` field on `RideOfferPayload` too) is a reasonable follow-up, not required by the literal spec text this plan is implementing.

- [ ] **Step 1: Write the failing tests for `decideFallbackAction`**

`app/test/call/fallback_decision_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/fallback_decision.dart';

void main() {
  test('keeps trying while WebRTC has not timed out yet', () {
    expect(
      decideFallbackAction(
        webrtcConnected: false,
        webrtcTimedOut: false,
        counterpartyPhoneKnown: true,
        phoneShareEnabled: true,
      ),
      CallFallbackAction.keepTryingWebrtc,
    );
  });

  test('keeps "trying" once connected, regardless of timeout flag', () {
    expect(
      decideFallbackAction(
        webrtcConnected: true,
        webrtcTimedOut: true,
        counterpartyPhoneKnown: true,
        phoneShareEnabled: true,
      ),
      CallFallbackAction.keepTryingWebrtc,
    );
  });

  test('offers a phone call once timed out, when a number was shared and '
      'the toggle is on', () {
    expect(
      decideFallbackAction(
        webrtcConnected: false,
        webrtcTimedOut: true,
        counterpartyPhoneKnown: true,
        phoneShareEnabled: true,
      ),
      CallFallbackAction.offerPhoneCall,
    );
  });

  test('falls straight to a voice message when no phone number is known',
      () {
    expect(
      decideFallbackAction(
        webrtcConnected: false,
        webrtcTimedOut: true,
        counterpartyPhoneKnown: false,
        phoneShareEnabled: true,
      ),
      CallFallbackAction.offerVoiceMessage,
    );
  });

  test('falls straight to a voice message when phone sharing is disabled '
      'even if a number happens to be known', () {
    expect(
      decideFallbackAction(
        webrtcConnected: false,
        webrtcTimedOut: true,
        counterpartyPhoneKnown: true,
        phoneShareEnabled: false,
      ),
      CallFallbackAction.offerVoiceMessage,
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails, then implement**

Run: `flutter test test/call/fallback_decision_test.dart` — Expected: FAIL.

`app/lib/call/fallback_decision.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The next rung of the calling fallback chain (spec §7.3): keep trying
/// WebRTC (P2P direct or helper-relayed -- both are the same "WebRTC
/// attempt" from this decision's point of view, see `ice_servers.dart`'s
/// doc comment), or drop to a plain phone call, or drop straight to a
/// short voice message. `offerHelperRelay` is deliberately NOT a distinct
/// value here: STUN vs. TURN-via-helper is resolved *inside* one WebRTC
/// connection attempt by the ICE agent itself (RFC 8445), not by this
/// app retrying with different servers -- so there is exactly one
/// external app-level decision point (did WebRTC connect before timing
/// out?), not three.
enum CallFallbackAction { keepTryingWebrtc, offerPhoneCall, offerVoiceMessage }

/// Pure and total -- every input combination maps to exactly one action,
/// so the whole chain's ordering is covered by ordinary unit tests with
/// no WebRTC/network dependency. `CallService` (Task 7) calls this once
/// per relevant state change (a connection-state update, or its own
/// timeout firing) rather than polling it.
CallFallbackAction decideFallbackAction({
  required bool webrtcConnected,
  required bool webrtcTimedOut,
  required bool counterpartyPhoneKnown,
  required bool phoneShareEnabled,
}) {
  if (webrtcConnected || !webrtcTimedOut) {
    return CallFallbackAction.keepTryingWebrtc;
  }
  if (counterpartyPhoneKnown && phoneShareEnabled) {
    return CallFallbackAction.offerPhoneCall;
  }
  return CallFallbackAction.offerVoiceMessage;
}
```

- [ ] **Step 3: Run to verify it passes**

Run: `flutter test test/call/fallback_decision_test.dart` — Expected: PASS.

- [ ] **Step 4: Write the failing tests for `PhoneShareSettingsStore`**

`app/test/call/phone_share_settings_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/phone_share_settings.dart';

void main() {
  test('isEnabled defaults to true (spec §7.3-②: "default: асаалттай")',
      () async {
    final store = InMemoryPhoneShareSettingsStore();
    expect(await store.isEnabled(), isTrue);
  });

  test('setEnabled persists across reads', () async {
    final store = InMemoryPhoneShareSettingsStore();
    await store.setEnabled(false);
    expect(await store.isEnabled(), isFalse);
  });

  test('loadOwnPhone is null until saveOwnPhone is called', () async {
    final store = InMemoryPhoneShareSettingsStore();
    expect(await store.loadOwnPhone(), isNull);
    await store.saveOwnPhone('99112233');
    expect(await store.loadOwnPhone(), '99112233');
  });
}
```

- [ ] **Step 5: Run to verify it fails, then implement**

Run: `flutter test test/call/phone_share_settings_test.dart` — Expected: FAIL.

`app/lib/call/phone_share_settings.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device's own phone number is attached to the exact-
/// location handoff DM (spec §7.3-②), and the number itself. Local-only
/// -- never published anywhere, never sent to a relay on its own; it only
/// ever travels inside an already-NIP-17-encrypted `RideHandoffPayload`
/// addressed to one specific, already-selected driver (`handoff_service.
/// dart`, Step 8 below). Mirrors `TariffStore` (Plan 4)'s
/// interface/implementation shape exactly.
abstract interface class PhoneShareSettingsStore {
  /// Defaults to `true` (spec §7.3-②: "toggle (default: асаалттай)") --
  /// callers must explicitly opt OUT, not opt in, matching the spec's
  /// literal default.
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
  Future<String?> loadOwnPhone();
  Future<void> saveOwnPhone(String phone);
}

const _kEnabledKey = 'takhi_phone_share_enabled';
const _kPhoneKey = 'takhi_phone_share_own_number';

class SharedPreferencesPhoneShareSettingsStore
    implements PhoneShareSettingsStore {
  final Future<SharedPreferences> Function() _instance;
  SharedPreferencesPhoneShareSettingsStore(this._instance);

  @override
  Future<bool> isEnabled() async =>
      (await _instance()).getBool(_kEnabledKey) ?? true;

  @override
  Future<void> setEnabled(bool enabled) async =>
      (await _instance()).setBool(_kEnabledKey, enabled);

  @override
  Future<String?> loadOwnPhone() async =>
      (await _instance()).getString(_kPhoneKey);

  @override
  Future<void> saveOwnPhone(String phone) async =>
      (await _instance()).setString(_kPhoneKey, phone);
}

/// Test double, mirrors `InMemoryTariffStore` (Plan 4)/`InMemoryKeyStore`
/// (Plan 1).
class InMemoryPhoneShareSettingsStore implements PhoneShareSettingsStore {
  bool _enabled = true;
  String? _phone;

  @override
  Future<bool> isEnabled() async => _enabled;
  @override
  Future<void> setEnabled(bool enabled) async => _enabled = enabled;
  @override
  Future<String?> loadOwnPhone() async => _phone;
  @override
  Future<void> saveOwnPhone(String phone) async => _phone = phone;
}
```

If Plan 4's `meter/tariff_store.dart` has not already added `shared_preferences` to `app/pubspec.yaml`, add it now:

```yaml
  shared_preferences: ^2.3.2
```

Run (from `app/`): `flutter pub get`

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/call/phone_share_settings_test.dart` — Expected: PASS.

- [ ] **Step 7: Wire the provider**

Add to `app/lib/call/call_providers.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'phone_share_settings.dart';

final phoneShareSettingsStoreProvider = Provider<PhoneShareSettingsStore>(
  (ref) => SharedPreferencesPhoneShareSettingsStore(
    SharedPreferences.getInstance,
  ),
);
```

- [ ] **Step 8: Add the optional `phone` field to `RideHandoffPayload`**

Append to `app/test/ride/ride_dm_payload_test.dart`:

```dart
  test('handoff payload phone field round-trips when present', () {
    const handoff = RideHandoffPayload(
      rideRequestId: 'req1',
      tripId: 'trip-1',
      lat: 47.9,
      lon: 106.9,
      plusCode: 'ABC+123',
      landmarkText: 'цагаан хаалга',
      phone: '99112233',
    );
    final decoded =
        RideDmPayload.decode(handoff.encode()) as RideHandoffPayload;
    expect(decoded.phone, '99112233');
  });

  test('handoff payload phone field is null when omitted', () {
    const handoff = RideHandoffPayload(
      rideRequestId: 'req1',
      tripId: 'trip-1',
      lat: 47.9,
      lon: 106.9,
      plusCode: 'ABC+123',
      landmarkText: 'цагаан хаалга',
    );
    final decoded =
        RideDmPayload.decode(handoff.encode()) as RideHandoffPayload;
    expect(decoded.phone, isNull);
  });
```

Run: `flutter test test/ride/ride_dm_payload_test.dart` — Expected: FAIL (no `phone` parameter yet).

In `app/lib/ride/ride_dm_payload.dart`, modify `RideHandoffPayload`:

```dart
final class RideHandoffPayload extends RideDmPayload {
  final String rideRequestId;
  final String tripId;
  final double lat;
  final double lon;
  final String plusCode;
  final String landmarkText;

  /// The passenger's own phone number, present only when
  /// `PhoneShareSettingsStore.isEnabled()` was true at handoff time (spec
  /// §7.3-②) -- absent (`null`), not empty-string, when sharing is off or
  /// no number is saved. See this task's "Deliberate scope boundary" note
  /// for why this field exists only on the passenger-to-driver handoff and
  /// not symmetrically on the driver's offer.
  final String? phone;

  const RideHandoffPayload({
    required this.rideRequestId,
    required this.tripId,
    required this.lat,
    required this.lon,
    required this.plusCode,
    required this.landmarkText,
    this.phone,
  });

  factory RideHandoffPayload._fromJson(Map<String, dynamic> map) =>
      RideHandoffPayload(
        rideRequestId: _requiredString(map, 'rideRequestId'),
        tripId: _requiredString(map, 'tripId'),
        lat: _requiredDouble(map, 'lat'),
        lon: _requiredDouble(map, 'lon'),
        plusCode: _requiredString(map, 'plusCode'),
        landmarkText: _requiredString(map, 'landmarkText'),
        phone: _optionalStringOrNull(map, 'phone'),
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
    if (phone != null) 'phone': phone,
  };
}
```

Add the new helper alongside the file's other `_required*`/`_optionalString` helpers (a genuinely-nullable variant is needed here — the existing `_optionalString` always returns a non-null fallback, which cannot distinguish "absent" from "explicitly empty"):

```dart
String? _optionalStringOrNull(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException(
    "RideDmPayload.decode: '$field' must be a String or null, got "
    '${value.runtimeType}',
  );
}
```

Run: `flutter test test/ride/ride_dm_payload_test.dart` — Expected: PASS.

- [ ] **Step 9: Thread `phone` through `HandoffService.sendHandoff`**

Append to `app/test/ride/handoff_service_test.dart` (a new case; the file's existing tests are untouched):

```dart
  test('sendHandoff includes phone in the payload when given', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = HandoffService(RideDmChannel(pool));
    final passenger = generateKeyPair(List<int>.filled(32, 61));
    final driver = generateKeyPair(List<int>.filled(32, 62));

    final got = <ReceivedHandoff>[];
    final sub = service
        .receiveHandoffs(driver.publicHex, driver.privateHex)
        .listen(got.add);
    final subId = _reqSubId(sockets['wss://a']!);

    await service.sendHandoff(
      passengerPrivHex: passenger.privateHex,
      driverPubHex: driver.publicHex,
      rideRequestId: 'req1',
      lat: 47.9,
      lon: 106.9,
      landmarkText: 'test',
      now: 1000,
      phone: '99112233',
    );
    final sent = jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, sent[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.single.payload.phone, '99112233');
    await sub.cancel();
  });
```

(Reuse whatever `_reqSubId` helper the existing test file already defines; if it does not have one yet, copy `ride_dm_channel_test.dart`'s.)

Run: `flutter test test/ride/handoff_service_test.dart` — Expected: FAIL (`sendHandoff` has no `phone` parameter).

In `app/lib/ride/handoff_service.dart`, modify `sendHandoff`:

```dart
  Future<String> sendHandoff({
    required String passengerPrivHex,
    required String driverPubHex,
    required String rideRequestId,
    required double lat,
    required double lon,
    required String landmarkText,
    required int now,
    String? tripId,
    String? phone,
  }) async {
    final id = tripId ?? generateTripId();
    final payload = RideHandoffPayload(
      rideRequestId: rideRequestId,
      tripId: id,
      lat: lat,
      lon: lon,
      plusCode: plusCodeEncode(lat, lon),
      landmarkText: landmarkText,
      phone: phone,
    );
    await _dm.send(
      senderPrivHex: passengerPrivHex,
      recipientPubHex: driverPubHex,
      payload: payload,
      now: now,
    );
    return id;
  }
```

Run: `flutter test test/ride/handoff_service_test.dart` — Expected: PASS (existing cases unaffected, since `phone` defaults to `null`).

- [ ] **Step 10: Wire the passenger side's call site (once Plan 4 exists)**

In `app/lib/ride/passenger_ride_page.dart`'s `_select` method (the one call site that already invokes `HandoffService.sendHandoff`), add the two lines needed to actually honor the toggle:

```dart
    final phoneShareEnabled =
        await ref.read(phoneShareSettingsStoreProvider).isEnabled();
    final ownPhone = phoneShareEnabled
        ? await ref.read(phoneShareSettingsStoreProvider).loadOwnPhone()
        : null;
```

placed immediately before the existing `await ref.read(handoffServiceProvider).sendHandoff(...)` call, then add `phone: ownPhone,` to that call's argument list. This is the only change to `passenger_ride_page.dart` in this task — every other line, and every existing `passenger_ride_page_test.dart` assertion, is untouched (`ownPhone` is `null` whenever no number was ever saved via `EmergencyContactSettingsPage`-style settings, so the new call is a no-op for every test that doesn't explicitly save one).

- [ ] **Step 11: Full re-run and commit**

Run: `flutter test test/call/fallback_decision_test.dart test/call/phone_share_settings_test.dart test/ride/ride_dm_payload_test.dart test/ride/handoff_service_test.dart` — Expected: PASS.

```bash
git add app/lib/call/fallback_decision.dart app/lib/call/phone_share_settings.dart app/lib/call/call_providers.dart app/lib/ride/ride_dm_payload.dart app/lib/ride/handoff_service.dart app/lib/ride/passenger_ride_page.dart app/pubspec.yaml app/pubspec.lock app/test/call/fallback_decision_test.dart app/test/call/phone_share_settings_test.dart app/test/ride/ride_dm_payload_test.dart app/test/ride/handoff_service_test.dart
git commit -m "feat(app): fallback-chain decision + opt-in phone-number exchange on handoff"
```

### Task 6: Voice-message fallback rung ③ (`app/lib/ride/`, `app/lib/call/`)

**Files:**
- Modify: `app/lib/ride/ride_dm_payload.dart` (add `VoiceNotePayload`)
- Create: `app/lib/call/voice_note_service.dart`
- Create: `app/lib/call/voice_note_recorder.dart`
- Create: `app/lib/call/voice_note_player.dart`
- Modify: `app/lib/call/call_providers.dart`
- Modify: `app/pubspec.yaml` (add `record`, `audioplayers`)
- Modify: `app/android/app/src/main/AndroidManifest.xml` (already has `RECORD_AUDIO` from Task 4 — no further change needed)
- Modify: `app/test/ride/ride_dm_payload_test.dart` (round-trip case)
- Test: `app/test/call/voice_note_service_test.dart`
- Test: `app/test/support/fake_voice_note_recorder.dart` (shared test double)

**Interfaces:**
- Produces: `final class VoiceNotePayload extends RideDmPayload { final String tripId, audioBase64; final int durationSeconds; const VoiceNotePayload({...}); }`; `const int kMaxVoiceNoteDurationSeconds = 10; const int kMaxVoiceNoteBytes = 35 * 1024;`; `class VoiceNoteTooLongException implements Exception`; `class VoiceNoteTooLargeException implements Exception`; `void validateVoiceNoteAudio(List<int> audioBytes, int durationSeconds)`; `class ReceivedVoiceNote { final String senderPubkey; final VoiceNotePayload payload; const ReceivedVoiceNote(this.senderPubkey, this.payload); }`; `class VoiceNoteService { Future<void> send({required senderPrivHex, required recipientPubHex, required tripId, required audioBytes, required durationSeconds, required now}); Stream<ReceivedVoiceNote> watchVoiceNotes(String myPubHex, String myPrivHex); }`; `abstract interface class VoiceNoteRecorder { Future<bool> hasPermission(); Future<void> start(); Future<(List<int> bytes, int durationSeconds)> stop(); }`; `RecordPackageVoiceNoteRecorder`, `FakeVoiceNoteRecorder`; `class VoiceNotePlayer { Future<void> playBase64(String audioBase64); Future<void> stop(); }`.
- Consumed by: Task 7's `CallScreen` (this is the UI surface that actually records/sends/plays a voice note, once WebRTC and the phone fallback have both been exhausted).

- [ ] **Step 1: Write the failing round-trip test for `VoiceNotePayload`**

Append to `app/test/ride/ride_dm_payload_test.dart`:

```dart
  test('voice_note payload round-trips through encode/decode', () {
    const note = VoiceNotePayload(
      tripId: 'trip-1',
      audioBase64: 'ZmFrZS1vcHVzLWJ5dGVz',
      durationSeconds: 7,
    );
    final decoded = RideDmPayload.decode(note.encode()) as VoiceNotePayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.audioBase64, 'ZmFrZS1vcHVzLWJ5dGVz');
    expect(decoded.durationSeconds, 7);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ride/ride_dm_payload_test.dart` — Expected: FAIL — `VoiceNotePayload` undefined.

- [ ] **Step 3: Add `VoiceNotePayload`**

Extend the `decode` switch (insert before `final other =>`):

```dart
      'voice_note' => VoiceNotePayload._fromJson(map),
```

Append at the end of the file:

```dart
/// A short voice message (spec §7.3-③ "дуут зурвас") -- the final rung of
/// the calling fallback chain, guaranteed to cross any NAT/CGNAT because
/// it rides the same reliable NIP-17 gift-wrap DM transport as every other
/// ride message: no direct connection between the two devices is ever
/// needed. Capped at [kMaxVoiceNoteDurationSeconds]/[kMaxVoiceNoteBytes]
/// by `validateVoiceNoteAudio` (`app/lib/call/voice_note_service.dart`)
/// *before* a payload is ever constructed on the sending side -- this
/// class itself does not re-validate on decode, so a hand-crafted
/// oversized payload from a misbehaving peer still decodes without
/// throwing (consistent with every other payload's "never crash on
/// foreign input" policy); the receiving UI sizes its player display from
/// `durationSeconds` alone rather than trusting `audioBase64`'s length for
/// anything but playback itself.
final class VoiceNotePayload extends RideDmPayload {
  final String tripId;
  final String audioBase64;
  final int durationSeconds;

  const VoiceNotePayload({
    required this.tripId,
    required this.audioBase64,
    required this.durationSeconds,
  });

  factory VoiceNotePayload._fromJson(Map<String, dynamic> map) =>
      VoiceNotePayload(
        tripId: _requiredString(map, 'tripId'),
        audioBase64: _requiredString(map, 'audioBase64'),
        durationSeconds: _requiredInt(map, 'durationSeconds'),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'voice_note',
    'tripId': tripId,
    'audioBase64': audioBase64,
    'durationSeconds': durationSeconds,
  };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ride/ride_dm_payload_test.dart` — Expected: PASS.

- [ ] **Step 5: Write the failing tests for `validateVoiceNoteAudio` and `VoiceNoteService`**

`app/test/call/voice_note_service_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/voice_note_service.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  group('validateVoiceNoteAudio', () {
    test('accepts audio within both limits', () {
      expect(
        () => validateVoiceNoteAudio(List.filled(1000, 0), 5),
        returnsNormally,
      );
    });

    test('rejects audio longer than kMaxVoiceNoteDurationSeconds', () {
      expect(
        () => validateVoiceNoteAudio(List.filled(1000, 0), 11),
        throwsA(isA<VoiceNoteTooLongException>()),
      );
    });

    test('rejects audio larger than kMaxVoiceNoteBytes', () {
      expect(
        () => validateVoiceNoteAudio(
          List.filled(kMaxVoiceNoteBytes + 1, 0),
          5,
        ),
        throwsA(isA<VoiceNoteTooLargeException>()),
      );
    });
  });

  group('VoiceNoteService', () {
    final sender = generateKeyPair(List<int>.filled(32, 71));
    final recipient = generateKeyPair(List<int>.filled(32, 72));

    test('send rejects an oversized note before touching the network',
        () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = VoiceNoteService(RideDmChannel(pool));

      await expectLater(
        () => service.send(
          senderPrivHex: sender.privateHex,
          recipientPubHex: recipient.publicHex,
          tripId: 'trip-1',
          audioBytes: List.filled(1000, 0),
          durationSeconds: 11,
          now: 1000,
        ),
        throwsA(isA<VoiceNoteTooLongException>()),
      );
      expect(sockets['wss://a']!.sent, isEmpty);
    });

    test('send delivers a base64-encoded note, watchVoiceNotes decodes it',
        () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = VoiceNoteService(RideDmChannel(pool));

      final got = <ReceivedVoiceNote>[];
      final sub = service
          .watchVoiceNotes(recipient.publicHex, recipient.privateHex)
          .listen(got.add);
      final subId = _reqSubId(sockets['wss://a']!);

      await service.send(
        senderPrivHex: sender.privateHex,
        recipientPubHex: recipient.publicHex,
        tripId: 'trip-1',
        audioBytes: [1, 2, 3, 4],
        durationSeconds: 3,
        now: 1000,
      );
      final sent = jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
      sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, sent[1]]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(got.length, 1);
      expect(got.first.senderPubkey, sender.publicHex);
      expect(got.first.payload.tripId, 'trip-1');
      expect(got.first.payload.durationSeconds, 3);
      expect(base64Decode(got.first.payload.audioBase64), [1, 2, 3, 4]);
      await sub.cancel();
    });
  });
}

String _reqSubId(FakeRelaySocket socket) {
  for (final raw in socket.sent.reversed) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    if (decoded[0] == 'REQ') return decoded[1] as String;
  }
  throw StateError('no REQ frame sent');
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/call/voice_note_service_test.dart` — Expected: FAIL — `voice_note_service.dart` doesn't exist.

- [ ] **Step 7: Implement `voice_note_service.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import '../ride/ride_dm_channel.dart';
import '../ride/ride_dm_payload.dart';

/// Spec §7.3-③'s own numbers: "≤10 сек opus ~30KB". [kMaxVoiceNoteBytes]
/// is set slightly above the literal ~30KB target (35KB) to give Opus's
/// variable bitrate a little headroom without ever approving a note that
/// would meaningfully miss the spec's intent.
const int kMaxVoiceNoteDurationSeconds = 10;
const int kMaxVoiceNoteBytes = 35 * 1024;

class VoiceNoteTooLongException implements Exception {
  final int actualSeconds;
  const VoiceNoteTooLongException(this.actualSeconds);
  @override
  String toString() =>
      'VoiceNoteTooLongException: ${actualSeconds}s exceeds '
      '${kMaxVoiceNoteDurationSeconds}s';
}

class VoiceNoteTooLargeException implements Exception {
  final int actualBytes;
  const VoiceNoteTooLargeException(this.actualBytes);
  @override
  String toString() =>
      'VoiceNoteTooLargeException: $actualBytes bytes exceeds '
      '$kMaxVoiceNoteBytes bytes';
}

/// Throws [VoiceNoteTooLongException]/[VoiceNoteTooLargeException] if
/// [audioBytes]/[durationSeconds] exceed spec §7.3-③'s limits. Pure and
/// synchronous -- called by [VoiceNoteService.send] before it ever touches
/// the network, so an oversized recording is rejected locally and never
/// published (verified by this task's "rejects an oversized note before
/// touching the network" test, which asserts nothing was sent).
void validateVoiceNoteAudio(List<int> audioBytes, int durationSeconds) {
  if (durationSeconds > kMaxVoiceNoteDurationSeconds) {
    throw VoiceNoteTooLongException(durationSeconds);
  }
  if (audioBytes.length > kMaxVoiceNoteBytes) {
    throw VoiceNoteTooLargeException(audioBytes.length);
  }
}

class ReceivedVoiceNote {
  final String senderPubkey;
  final VoiceNotePayload payload;
  const ReceivedVoiceNote(this.senderPubkey, this.payload);
}

/// Sends/receives short voice messages over the existing `RideDmChannel`
/// -- the reliable, NAT-agnostic last rung of the calling fallback chain.
class VoiceNoteService {
  final RideDmChannel _dm;
  VoiceNoteService(this._dm);

  Future<void> send({
    required String senderPrivHex,
    required String recipientPubHex,
    required String tripId,
    required List<int> audioBytes,
    required int durationSeconds,
    required int now,
  }) async {
    validateVoiceNoteAudio(audioBytes, durationSeconds);
    await _dm.send(
      senderPrivHex: senderPrivHex,
      recipientPubHex: recipientPubHex,
      payload: VoiceNotePayload(
        tripId: tripId,
        audioBase64: base64Encode(audioBytes),
        durationSeconds: durationSeconds,
      ),
      now: now,
    );
  }

  Stream<ReceivedVoiceNote> watchVoiceNotes(
    String myPubHex,
    String myPrivHex,
  ) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is VoiceNotePayload)
        .map(
          (dm) =>
              ReceivedVoiceNote(dm.senderPubkey, dm.payload as VoiceNotePayload),
        );
  }
}
```

- [ ] **Step 8: Run to verify it passes**

Run: `flutter test test/call/voice_note_service_test.dart` — Expected: PASS.

- [ ] **Step 9: Add the recorder abstraction, real implementation, Fake, and player**

Add to `app/pubspec.yaml`:

```yaml
  record: ^5.2.0
  audioplayers: ^6.1.0
```

Run (from `app/`): `flutter pub get`

`app/lib/call/voice_note_recorder.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record_pkg;

/// Abstracts Opus voice-note capture behind a plain start/stop pair so
/// `CallScreen` (Task 7) is testable with a fake recorder instead of a
/// real microphone -- mirrors `LocationSource` (Plan 4)'s role for GPS.
abstract interface class VoiceNoteRecorder {
  Future<bool> hasPermission();
  Future<void> start();

  /// Stops recording and returns the captured Opus-encoded bytes plus the
  /// elapsed duration in whole seconds.
  Future<(List<int> bytes, int durationSeconds)> stop();
}

/// Real [VoiceNoteRecorder] backed by `package:record`, recording to a
/// temporary `.ogg` (Opus) file and reading it back into memory on
/// [stop] -- `record`'s own permission handling (`hasPermission`) covers
/// `RECORD_AUDIO` without this app needing a separate `permission_handler`
/// dependency.
class RecordPackageVoiceNoteRecorder implements VoiceNoteRecorder {
  final record_pkg.AudioRecorder _recorder = record_pkg.AudioRecorder();
  DateTime? _startedAt;
  String? _path;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/takhi-voice-note-${DateTime.now().millisecondsSinceEpoch}.ogg';
    _startedAt = DateTime.now();
    await _recorder.start(
      const record_pkg.RecordConfig(encoder: record_pkg.AudioEncoder.opus),
      path: _path!,
    );
  }

  @override
  Future<(List<int>, int)> stop() async {
    final path = await _recorder.stop();
    final durationSeconds = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inSeconds;
    if (path == null) return (const <int>[], durationSeconds);
    final bytes = await File(path).readAsBytes();
    return (bytes, durationSeconds);
  }
}

/// Test double -- returns canned bytes/duration instead of recording,
/// mirrors `FakeLocationSource`'s role.
class FakeVoiceNoteRecorder implements VoiceNoteRecorder {
  bool permissionGranted = true;
  List<int> nextBytes = [1, 2, 3];
  int nextDurationSeconds = 3;
  bool started = false;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start() async => started = true;

  @override
  Future<(List<int>, int)> stop() async {
    started = false;
    return (nextBytes, nextDurationSeconds);
  }
}
```

`app/test/support/fake_voice_note_recorder.dart` re-exports the test double for consistency with the rest of `test/support/`'s file-per-fake convention:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
export 'package:takhi/call/voice_note_recorder.dart' show FakeVoiceNoteRecorder;
```

`app/lib/call/voice_note_player.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Plays back a received voice note's base64 Opus payload. Writes it to a
/// short-lived temp file rather than `BytesSource` directly -- keeps this
/// class's behavior identical across the `audioplayers` platform backends,
/// which have historically had uneven `BytesSource` support, at the cost
/// of one small, self-cleaning temp-file write per playback.
class VoiceNotePlayer {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playBase64(String audioBase64) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/takhi-voice-note-playback-${DateTime.now().millisecondsSinceEpoch}.ogg';
    final file = File(path);
    await file.writeAsBytes(base64Decode(audioBase64));
    await _player.play(DeviceFileSource(path));
  }

  Future<void> stop() => _player.stop();
}
```

- [ ] **Step 10: Wire providers**

Add to `app/lib/call/call_providers.dart`:

```dart
import 'voice_note_recorder.dart';
import 'voice_note_service.dart';

final voiceNoteServiceProvider = Provider<VoiceNoteService>(
  (ref) => VoiceNoteService(ref.watch(rideDmChannelProvider)),
);

final voiceNoteRecorderProvider = Provider<VoiceNoteRecorder>(
  (ref) => RecordPackageVoiceNoteRecorder(),
);
```

- [ ] **Step 11: Full re-run and commit**

Run: `flutter test test/ride/ride_dm_payload_test.dart test/call/voice_note_service_test.dart` — Expected: PASS.

```bash
git add app/lib/ride/ride_dm_payload.dart app/lib/call/voice_note_service.dart app/lib/call/voice_note_recorder.dart app/lib/call/voice_note_player.dart app/lib/call/call_providers.dart app/pubspec.yaml app/pubspec.lock app/test/ride/ride_dm_payload_test.dart app/test/call/voice_note_service_test.dart app/test/support/fake_voice_note_recorder.dart
git commit -m "feat(app): voice-message fallback (rung 3 -- Opus, NIP-17 DM)"
```

### Task 7: `CallService` orchestration + `CallScreen` UI + `ActiveTripView` wiring

**Files:**
- Create: `app/lib/call/call_service.dart`
- Create: `app/lib/call/call_screen.dart` (spec + approach)
- Modify: `app/lib/ride/active_trip_view.dart` (Plan 4 deliverable — add the call button + incoming-call listener)
- Modify: `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb`
- Test: `app/test/call/call_service_test.dart`
- Test: `app/test/ride/active_trip_view_call_test.dart` (spec + approach; a new file rather than editing Plan 4's `active_trip_view_test.dart` in place, so this plan's addition is reviewable independently of Plan 4's own test file)

**Interfaces:**
- Consumes: `CallEngine`/`FakeCallEngine` (Task 4), `CallSignalService`/`ReceivedCallSignal` (Task 2), `HelperDirectoryService`/`HelperDirectory`/`buildIceServers` (Task 3), `decideFallbackAction`/`CallFallbackAction` (Task 5), `PhoneShareSettingsStore` (Task 5), `VoiceNoteService`/`VoiceNoteRecorder`/`VoiceNotePlayer` (Task 6), `ActiveTripView` (Plan 4).
- Produces: `sealed class CallState {}` with `CallStateDialing`, `CallStateRinging`, `CallStateConnecting`, `CallStateConnected`, `CallStateFallbackPhone(String phone)`, `CallStateFallbackVoiceNote`, `CallStateEnded(String reason)`; `class CallService { CallService({required CallEngine engine, required CallSignalService signal, required HelperDirectoryService helperDirectory, required PhoneShareSettingsStore phoneShareSettings, required String myPubHex, required String myPrivHex, required String counterpartyPubHex, required String tripId, String? counterpartyPhone, Duration connectTimeout = const Duration(seconds: 15)}); Stream<CallState> get state; Future<void> startAsCaller({required int Function() now}); Future<void> acceptIncomingOffer(String offerSdp, {required int Function() now}); Future<void> setMuted(bool muted); Future<void> hangUp({required int Function() now}); Future<void> dispose(); }`; `class CallScreen extends ConsumerStatefulWidget { const CallScreen({required tripId, required counterpartyPubHex, required bool isCaller, String? incomingOfferSdp, String? counterpartyPhone}); }`; `class IncomingCallListener extends ConsumerStatefulWidget { const IncomingCallListener({required tripId, required counterpartyPubHex, String? counterpartyPhone, required Widget child}); }`.
- Consumed by: Task 8/9's SOS/share buttons render alongside this task's call button inside the same `ActiveTripView` tracking-step layout.

**iOS note, stated once here in full since this is the task where it actually bites:** `IncomingCallListener`'s subscription (and everything above it) only exists while `ActiveTripView`'s tracking step is mounted and the app is in the foreground. On Android this is a real limitation but a survivable one -- the OS keeps background sockets alive long enough in most cases, and the driver-mode limitation (spec §13) is already accepted. On iOS, backgrounding kills the socket outright, so **no incoming call can ever ring unless Тахь is already open on the active-trip screen** -- there is no CallKit/PushKit integration in this plan, and building one would require a server to hold push tokens and trigger wake-ups, directly violating invariant 1. This plan does not build a workaround; it is stated here, in `IncomingCallListener`'s own doc comment, and repeated in this plan's Self-Review, exactly as directly as spec §13 already states the parallel driver-mode limitation. (`app/ios/` does not exist in this repository yet regardless — see Global Constraints.)

- [ ] **Step 1: Write the failing tests for `CallService`**

`app/test/call/call_service_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_engine.dart';
import 'package:takhi/call/call_service.dart';
import 'package:takhi/call/call_signal_service.dart';
import 'package:takhi/call/helper_directory_service.dart';
import 'package:takhi/call/phone_share_settings.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_call_engine.dart';
import '../support/fake_relay_socket.dart';

void main() {
  final caller = generateKeyPair(List<int>.filled(32, 121));
  final callee = generateKeyPair(List<int>.filled(32, 122));

  ({RelayPool pool, Map<String, FakeRelaySocket> sockets}) freshPool() {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    return (pool: pool, sockets: sockets);
  }

  test('startAsCaller creates an offer, sends it, and reaches connected '
      'once the engine reports connected', () async {
    final rp = freshPool();
    await rp.pool.connectAll();
    final engine = FakeCallEngine();
    final service = CallService(
      engine: engine,
      signal: CallSignalService(RideDmChannel(rp.pool)),
      helperDirectory: HelperDirectoryService(rp.pool),
      phoneShareSettings: InMemoryPhoneShareSettingsStore(),
      myPubHex: caller.publicHex,
      myPrivHex: caller.privateHex,
      counterpartyPubHex: callee.publicHex,
      tripId: 'trip-1',
    );

    final states = <CallState>[];
    final sub = service.state.listen(states.add);

    await service.startAsCaller(now: () => 1000);
    expect(states.whereType<CallStateDialing>(), isNotEmpty);
    // The offer was actually published as a gift-wrapped DM.
    expect(
      rp.sockets['wss://a']!.sent.any((f) => f.contains('"kind":1059')),
      isTrue,
    );

    engine.emitConnectionState(CallConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    expect(states.whereType<CallStateConnected>(), isNotEmpty);

    await sub.cancel();
    await service.dispose();
  });

  test('a WebRTC failure with no known phone number falls to a voice-note '
      'offer', () async {
    final rp = freshPool();
    await rp.pool.connectAll();
    final engine = FakeCallEngine();
    final service = CallService(
      engine: engine,
      signal: CallSignalService(RideDmChannel(rp.pool)),
      helperDirectory: HelperDirectoryService(rp.pool),
      phoneShareSettings: InMemoryPhoneShareSettingsStore(),
      myPubHex: caller.publicHex,
      myPrivHex: caller.privateHex,
      counterpartyPubHex: callee.publicHex,
      tripId: 'trip-1',
      counterpartyPhone: null,
    );

    final states = <CallState>[];
    final sub = service.state.listen(states.add);
    await service.startAsCaller(now: () => 1000);

    engine.emitConnectionState(CallConnectionState.failed);
    await Future<void>.delayed(Duration.zero);

    expect(states.whereType<CallStateFallbackVoiceNote>(), isNotEmpty);
    await sub.cancel();
    await service.dispose();
  });

  test('a WebRTC failure with a known, shared phone number falls to '
      'offering a phone call', () async {
    final rp = freshPool();
    await rp.pool.connectAll();
    final engine = FakeCallEngine();
    final phoneSettings = InMemoryPhoneShareSettingsStore();
    final service = CallService(
      engine: engine,
      signal: CallSignalService(RideDmChannel(rp.pool)),
      helperDirectory: HelperDirectoryService(rp.pool),
      phoneShareSettings: phoneSettings,
      myPubHex: caller.publicHex,
      myPrivHex: caller.privateHex,
      counterpartyPubHex: callee.publicHex,
      tripId: 'trip-1',
      counterpartyPhone: '99112233',
    );

    final states = <CallState>[];
    final sub = service.state.listen(states.add);
    await service.startAsCaller(now: () => 1000);

    engine.emitConnectionState(CallConnectionState.failed);
    await Future<void>.delayed(Duration.zero);

    final fallback = states.whereType<CallStateFallbackPhone>().single;
    expect(fallback.phone, '99112233');
    await sub.cancel();
    await service.dispose();
  });

  test('hangUp sends a CallHangupPayload and emits CallStateEnded',
      () async {
    final rp = freshPool();
    await rp.pool.connectAll();
    final service = CallService(
      engine: FakeCallEngine(),
      signal: CallSignalService(RideDmChannel(rp.pool)),
      helperDirectory: HelperDirectoryService(rp.pool),
      phoneShareSettings: InMemoryPhoneShareSettingsStore(),
      myPubHex: caller.publicHex,
      myPrivHex: caller.privateHex,
      counterpartyPubHex: callee.publicHex,
      tripId: 'trip-1',
    );
    final states = <CallState>[];
    final sub = service.state.listen(states.add);

    await service.startAsCaller(now: () => 1000);
    await service.hangUp(now: () => 1001);

    expect(states.whereType<CallStateEnded>(), isNotEmpty);
    final hangupSent = rp.sockets['wss://a']!.sent
        .where((f) => f.contains('"kind":1059'))
        .length;
    expect(hangupSent, greaterThanOrEqualTo(2)); // offer + hangup
    await sub.cancel();
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/call/call_service_test.dart` — Expected: FAIL — `call_service.dart` doesn't exist.

- [ ] **Step 3: Implement `call_service.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'call_engine.dart';
import 'call_signal_service.dart';
import 'fallback_decision.dart';
import 'helper_directory_service.dart';
import 'phone_share_settings.dart';
import '../ride/ride_dm_payload.dart';

/// Where a call attempt currently stands, as the UI (`CallScreen`, Step 4
/// below) renders it. `CallStateFallbackPhone`/`CallStateFallbackVoiceNote`
/// are terminal for the WebRTC attempt but not for the call itself -- the
/// UI offers the next rung, it doesn't auto-dial or auto-record.
sealed class CallState {
  const CallState();
}

class CallStateDialing extends CallState {
  const CallStateDialing();
}

class CallStateRinging extends CallState {
  const CallStateRinging();
}

class CallStateConnecting extends CallState {
  const CallStateConnecting();
}

class CallStateConnected extends CallState {
  const CallStateConnected();
}

class CallStateFallbackPhone extends CallState {
  final String phone;
  const CallStateFallbackPhone(this.phone);
}

class CallStateFallbackVoiceNote extends CallState {
  const CallStateFallbackVoiceNote();
}

class CallStateEnded extends CallState {
  final String reason;
  const CallStateEnded(this.reason);
}

/// Orchestrates one call attempt for [tripId] between this device
/// ([myPubHex]/[myPrivHex]) and [counterpartyPubHex]: drives [CallEngine]
/// (WebRTC), exchanges signaling over [signal] (NIP-17 DM, Task 2), keeps
/// [helperDirectory]'s TURN list flowing into the engine's ICE config
/// (Task 3), and -- if the whole WebRTC attempt does not connect within
/// [connectTimeout] -- applies [decideFallbackAction] (Task 5) to decide
/// between offering a phone call (only if [counterpartyPhone] is non-null
/// and [phoneShareSettings] currently has sharing enabled) or a voice
/// note. One instance is exactly one call attempt; call [dispose] when
/// the call (or the fallback UI built on top of it) is done.
class CallService {
  final CallEngine _engine;
  final CallSignalService _signal;
  final HelperDirectoryService _helperDirectory;
  final PhoneShareSettingsStore _phoneShareSettings;
  final String myPubHex;
  final String myPrivHex;
  final String counterpartyPubHex;
  final String tripId;
  final String? counterpartyPhone;
  final Duration connectTimeout;

  final _helpers = HelperDirectory();
  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get state => _stateController.stream;

  StreamSubscription<void>? _helperSub;
  StreamSubscription<void>? _signalSub;
  StreamSubscription<void>? _iceSub;
  StreamSubscription<void>? _connSub;
  Timer? _timeoutTimer;
  int Function() _now = () => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  bool _webrtcConnected = false;
  bool _disposed = false;

  CallService({
    required CallEngine engine,
    required CallSignalService signal,
    required HelperDirectoryService helperDirectory,
    required PhoneShareSettingsStore phoneShareSettings,
    required this.myPubHex,
    required this.myPrivHex,
    required this.counterpartyPubHex,
    required this.tripId,
    this.counterpartyPhone,
    this.connectTimeout = const Duration(seconds: 15),
  }) : _engine = engine,
       _signal = signal,
       _helperDirectory = helperDirectory,
       _phoneShareSettings = phoneShareSettings;

  Future<void> startAsCaller({required int Function() now}) async {
    _now = now;
    _wireCommon();
    _stateController.add(const CallStateDialing());
    final offer = await _engine.createOffer();
    await _signal.sendOffer(
      privHex: myPrivHex,
      recipientPubHex: counterpartyPubHex,
      tripId: tripId,
      sdp: offer.sdp,
      now: now(),
    );
    _startTimeout();
  }

  Future<void> acceptIncomingOffer(
    String offerSdp, {
    required int Function() now,
  }) async {
    _now = now;
    _wireCommon();
    _stateController.add(const CallStateConnecting());
    final answer = await _engine.createAnswer(offerSdp);
    await _signal.sendAnswer(
      privHex: myPrivHex,
      recipientPubHex: counterpartyPubHex,
      tripId: tripId,
      sdp: answer.sdp,
      now: now(),
    );
    _startTimeout();
  }

  void _wireCommon() {
    _helperSub = _helperDirectory.watchHelpers().listen(_helpers.add);
    _signalSub = _signal
        .watchSignals(myPubHex, myPrivHex, tripId)
        .listen(_onSignal);
    _iceSub = _engine.localIceCandidates.listen((c) {
      unawaited(_signal.sendIceCandidate(
        privHex: myPrivHex,
        recipientPubHex: counterpartyPubHex,
        tripId: tripId,
        candidate: c.candidate,
        sdpMid: c.sdpMid,
        sdpMLineIndex: c.sdpMLineIndex,
        now: _now(),
      ));
    });
    _connSub = _engine.connectionState.listen(_onConnectionState);
  }

  void _onSignal(ReceivedCallSignal received) {
    switch (received.payload) {
      case CallAnswerPayload(:final sdp):
        unawaited(_engine.acceptAnswer(sdp));
      case CallIceCandidatePayload(
        :final candidate,
        :final sdpMid,
        :final sdpMLineIndex,
      ):
        unawaited(_engine.addRemoteIceCandidate(
          IceCandidateData(candidate, sdpMid, sdpMLineIndex),
        ));
      case CallHangupPayload(:final reason):
        _stateController.add(CallStateEnded(reason));
      default:
        break; // CallOfferPayload: handled by IncomingCallListener, not here.
    }
  }

  void _onConnectionState(CallConnectionState s) {
    if (s == CallConnectionState.connected) {
      _webrtcConnected = true;
      _timeoutTimer?.cancel();
      _stateController.add(const CallStateConnected());
    } else if (s == CallConnectionState.failed) {
      unawaited(_applyFallback(webrtcTimedOut: true));
    }
  }

  void _startTimeout() {
    _timeoutTimer = Timer(
      connectTimeout,
      () => unawaited(_applyFallback(webrtcTimedOut: true)),
    );
  }

  Future<void> _applyFallback({required bool webrtcTimedOut}) async {
    if (_disposed || _webrtcConnected) return;
    final action = decideFallbackAction(
      webrtcConnected: _webrtcConnected,
      webrtcTimedOut: webrtcTimedOut,
      counterpartyPhoneKnown: counterpartyPhone != null,
      phoneShareEnabled: await _phoneShareSettings.isEnabled(),
    );
    switch (action) {
      case CallFallbackAction.keepTryingWebrtc:
        return;
      case CallFallbackAction.offerPhoneCall:
        _stateController.add(CallStateFallbackPhone(counterpartyPhone!));
      case CallFallbackAction.offerVoiceMessage:
        _stateController.add(const CallStateFallbackVoiceNote());
    }
  }

  Future<void> setMuted(bool muted) => _engine.setMuted(muted);

  Future<void> hangUp({required int Function() now}) async {
    await _signal.sendHangup(
      privHex: myPrivHex,
      recipientPubHex: counterpartyPubHex,
      tripId: tripId,
      now: now(),
    );
    _stateController.add(const CallStateEnded('local'));
    await dispose();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timeoutTimer?.cancel();
    await _helperSub?.cancel();
    await _signalSub?.cancel();
    await _iceSub?.cancel();
    await _connSub?.cancel();
    await _engine.dispose();
    await _stateController.close();
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/call/call_service_test.dart` — Expected: PASS.

- [ ] **Step 5: Build `CallScreen` and `IncomingCallListener` (spec + approach)**

`app/lib/call/call_screen.dart`, a `ConsumerStatefulWidget` taking `tripId`, `counterpartyPubHex`, `isCaller`, `incomingOfferSdp` (required when `!isCaller`), `counterpartyPhone`. Internal:

1. **`initState`:** read `currentIdentityProvider`; construct `CallService` from `callEngineFactoryProvider()()`, `callSignalServiceProvider`, `helperDirectoryServiceProvider`, `phoneShareSettingsStoreProvider`. Call `startAsCaller(...)` if `widget.isCaller`, else `acceptIncomingOffer(widget.incomingOfferSdp!, ...)`. Listen to `service.state`, mapping into a local `CallState _uiState` field via `setState`.
2. **Rendering by state:** `CallStateDialing`/`CallStateRinging`/`CallStateConnecting` → a centered spinner + `Text(l.callConnectingLabel)` + a hang-up `IconButton` (`Icons.call_end`, red) that calls `service.hangUp(...)` then `Navigator.of(context).pop()`. `CallStateConnected` → an elapsed-time `Text` (a local `Timer.periodic(const Duration(seconds: 1))` ticking a `_elapsed` counter, started the moment this state is first seen), a mute `IconButton` toggling `service.setMuted(...)`, and the same hang-up button. `CallStateFallbackPhone(phone)` → `Text(l.callFailedOfferPhoneLabel)` + a `PrimaryButton(label: l.callViaPhoneAction)` that calls `launchUrl(Uri(scheme: 'tel', path: phone))` (`url_launcher`) then pops -- this is `ACTION_DIAL`, the user still presses call themselves (Global Constraints). `CallStateFallbackVoiceNote` → a hold-to-record UI: a large mic `IconButton` using `GestureDetector.onLongPressStart`/`onLongPressEnd` around `ref.read(voiceNoteRecorderProvider).start()`/`.stop()`, then `ref.read(voiceNoteServiceProvider).send(...)` with the identity's keys, `widget.counterpartyPubHex`, `widget.tripId`, and the returned `(bytes, durationSeconds)` -- a caught `VoiceNoteTooLongException` (recording ran past 10s) truncates the hold and shows `l.voiceNoteTooLongHint` instead of sending. `CallStateEnded(reason)` → `Text(l.callEndedLabel)` + auto-`Navigator.pop` after a short `Future.delayed`.
3. **`dispose()`:** cancel the `service.state` subscription, the elapsed-time `Timer`, and call `service.dispose()` -- mirrors every other page's established `dispose()` pattern.

`app/lib/call/call_screen.dart` also exports `IncomingCallListener`:

1. A `ConsumerStatefulWidget` wrapping `child`, taking `tripId`, `counterpartyPubHex`, `counterpartyPhone`.
2. **`initState`:** subscribes to `ref.read(callSignalServiceProvider).watchSignals(myPubHex, myPrivHex, tripId)`, filtering for `ReceivedCallSignal` whose `.payload is CallOfferPayload`. On one arriving (and no call already in progress), `setState` to show a full-screen incoming-call overlay (`Text(l.incomingCallLabel)`, Accept/Decline `IconButton`s) stacked over `child` via a `Stack`.
3. **Accept:** `Navigator.push(MaterialPageRoute(builder: (_) => CallScreen(tripId: tripId, counterpartyPubHex: counterpartyPubHex, isCaller: false, incomingOfferSdp: (payload as CallOfferPayload).sdp, counterpartyPhone: counterpartyPhone)))`, then dismiss the overlay.
4. **Decline:** send a `CallHangupPayload` via `callSignalServiceProvider` directly (a one-shot `_dm.send`, no full `CallService` needed since no `CallEngine` was ever created for a declined call) and dismiss the overlay.
5. **`dispose()`:** cancel the signal subscription.

- [ ] **Step 6: Add this task's ARB keys**

`app/lib/l10n/app_mn.arb`:

```json
  "callConnectingLabel": "Холбогдож байна…",
  "callViaPhoneAction": "Утсаар залгах",
  "callFailedOfferPhoneLabel": "Апп доторх дуудлага бүтсэнгүй",
  "callEndedLabel": "Дуудлага дууслаа",
  "incomingCallLabel": "Ирж буй дуудлага",
  "acceptCallAction": "Хариулах",
  "declineCallAction": "Татгалзах",
  "startCallAction": "Дуудлага хийх",
  "voiceNoteTooLongHint": "10 секундээс богино байх ёстой",
  "holdToRecordVoiceNoteHint": "Дараад бариад ярь"
```

`app/lib/l10n/app_en.arb`:

```json
  "callConnectingLabel": "Connecting…",
  "callViaPhoneAction": "Call by phone",
  "callFailedOfferPhoneLabel": "In-app call did not connect",
  "callEndedLabel": "Call ended",
  "incomingCallLabel": "Incoming call",
  "acceptCallAction": "Accept",
  "declineCallAction": "Decline",
  "startCallAction": "Call",
  "voiceNoteTooLongHint": "Must be under 10 seconds",
  "holdToRecordVoiceNoteHint": "Press and hold to talk"
```

- [ ] **Step 7: Wire the `CallEngine` factory provider**

Add to `app/lib/call/call_providers.dart`:

```dart
import 'call_engine.dart';
import 'ice_servers.dart';

/// A *factory*, not a shared instance -- every call attempt needs its own
/// fresh `RTCPeerConnection` (`CallEngine.dispose()` tears one down
/// completely). `CallScreen` calls this once per `initState`, passing the
/// currently-known helper list (`HelperDirectoryService`) merged with
/// `kDefaultStunServers` via `buildIceServers`.
final callEngineFactoryProvider =
    Provider<CallEngine Function(List<Map<String, dynamic>> iceServers)>(
  (ref) => (iceServers) => FlutterWebrtcCallEngine(iceServers: iceServers),
);
```

- [ ] **Step 8: Wire `ActiveTripView`'s tracking step (once Plan 4 exists)**

In `app/lib/ride/active_trip_view.dart`, inside the tracking-step body (the step that already renders the live `RideMap` with self/counterparty markers, per Plan 4 Task 7), wrap the existing content in `IncomingCallListener` and add a call-start button:

```dart
IncomingCallListener(
  tripId: widget.tripId,
  counterpartyPubHex: widget.counterpartyPubHex,
  counterpartyPhone: widget.role == TripRole.driver ? _counterpartyPhone : null,
  child: /* the existing tracking-step content, unchanged */,
),
```

plus, alongside the existing phase-transition buttons (driver) or phase display (passenger), one more:

```dart
IconButton(
  icon: const Icon(Icons.call),
  tooltip: l.startCallAction,
  onPressed: () => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CallScreen(
        tripId: widget.tripId,
        counterpartyPubHex: widget.counterpartyPubHex,
        isCaller: true,
        counterpartyPhone:
            widget.role == TripRole.driver ? _counterpartyPhone : null,
      ),
    ),
  ),
),
```

`_counterpartyPhone` is a new private field on `_ActiveTripViewState`, populated once, at `initState` time, only on the driver side: `_counterpartyPhone = widget.role == TripRole.driver ? <the RideHandoffPayload.phone the driver's own handoff subscription already received to reach the tracking step at all> : null;` — the driver side already has this value in scope (it is exactly `ReceivedHandoff.payload.phone`, Task 5), it just was not threaded into `ActiveTripView`'s state before this plan.

- [ ] **Step 9: Write representative tests (spec + approach)**

`app/test/ride/active_trip_view_call_test.dart` mirrors Plan 4's `active_trip_view_test.dart` override style (`ProviderScope` with `relayPoolProvider` fake-socket-backed, `locationSourceProvider` fake). Cover, at minimum:
- Pumping `ActiveTripView(role: TripRole.passenger, ...)`, tapping the call `IconButton`, and asserting a `"kind":1059"` gift-wrapped offer DM was published (decodable into `CallOfferPayload` via `nip17Unwrap` + `RideDmPayload.decode`) and that navigation pushed a `CallScreen`.
- Delivering a fake `CallOfferPayload` from the counterparty through the fake socket while `ActiveTripView` is mounted, and asserting `find.text('Ирж буй дуудлага')` (or the `incomingCallLabel` key) becomes visible without any local button tap -- proving `IncomingCallListener` actually listens.
- Tapping "Decline" on that incoming-call overlay and asserting a `CallHangupPayload` DM was sent, with no `CallScreen` ever pushed.

- [ ] **Step 10: Run and commit**

Run: `flutter test test/call/call_service_test.dart test/ride/active_trip_view_call_test.dart` — Expected: PASS.

```bash
git add app/lib/call/call_service.dart app/lib/call/call_screen.dart app/lib/call/call_providers.dart app/lib/ride/active_trip_view.dart app/lib/l10n app/test/call/call_service_test.dart app/test/ride/active_trip_view_call_test.dart
git commit -m "feat(app): CallService orchestration, CallScreen, incoming-call listener wired into ActiveTripView"
```

### Task 8: Aялал хуваалцах — server-less trip-share (`app/lib/safety/`, `docs/share/`)

**Files:**
- Create: `app/lib/safety/share_link.dart`
- Create: `app/lib/safety/share_session.dart`
- Create: `app/lib/safety/safety_providers.dart`
- Modify: `app/lib/ride/active_trip_view.dart` (Plan 4 deliverable — add the share button)
- Modify: `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb`
- Modify: `app/pubspec.yaml` (add `share_plus`)
- Create: `docs/share/index.html` (spec + approach)
- Test: `app/test/safety/share_link_test.dart`

**Interfaces:**
- Consumes: `KeyPair`/`generateKeyPair` (`takhi_protocol`), `LiveLocationChannel` (Plan 4), `defaultRelayUrls` (Plan 2).
- Produces: `String buildShareUrl({required String baseUrl, required String shareKeyHex, required String tripId, required List<String> relayUrls})`; `({String shareKeyHex, String tripId, List<String> relayUrls}) parseShareFragment(String fragment)`; `const String kShareBaseUrl`; `class ShareSession { final KeyPair shareKeyPair; ShareSession(); String urlFor(String tripId, List<String> relayUrls); }`.
- Consumed by: Task 9's `SosButton` shares this task's ARB/provider file (`safety_providers.dart`) as its home too.

**How this stays server-less, precisely:** every live-location ping (`LiveLocationChannel`, Plan 4, kind `20178`, NIP-44-encrypted) is already addressed to exactly one recipient pubkey. Starting a share session mints a **throwaway keypair** (`ShareSession.shareKeyPair`) that exists only on this device, then the app sends every subsequent live-location fix **twice**: once to the counterparty (unchanged, existing Plan-4 behavior) and once more, identically, to `shareKeyPair.publicHex`. The share link (`buildShareUrl`) embeds `shareKeyPair.privateHex` — never the public half — in the URL's fragment. A browser opening that link runs `docs/share/index.html`'s JS, which derives the public key from the fragment's private key locally, opens a plain WebSocket to the same public relays the app itself uses, subscribes to `{"kinds":[20178],"#p":[<derived pubkey>],"#d":[tripId]}`, and NIP-44-decrypts each event **in the browser**. No party except this device and the browser holding the link ever sees the private half; no HTTP request the browser makes (there are none beyond loading the static file itself) ever carries the fragment, because fragments are a browser-local concept per the URL spec — they are never sent over the wire to any server, including whatever host mirrors `index.html`.

- [ ] **Step 1: Write the failing tests for `buildShareUrl`/`parseShareFragment`**

`app/test/safety/share_link_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/safety/share_link.dart';

void main() {
  test('buildShareUrl embeds k/trip/relays in the fragment, not the path',
      () {
    final url = buildShareUrl(
      baseUrl: 'https://example.org/share/',
      shareKeyHex: 'ab' * 32,
      tripId: 'trip-1',
      relayUrls: ['wss://a', 'wss://b'],
    );
    expect(url, startsWith('https://example.org/share/#'));
    // The path portion (before '#') must not contain the key or trip id.
    final path = url.split('#').first;
    expect(path.contains('ab' * 32), isFalse);
    expect(path.contains('trip-1'), isFalse);
  });

  test('buildShareUrl normalizes a baseUrl missing a trailing slash', () {
    final url = buildShareUrl(
      baseUrl: 'https://example.org/share',
      shareKeyHex: 'cd' * 32,
      tripId: 'trip-1',
      relayUrls: ['wss://a'],
    );
    expect(url, startsWith('https://example.org/share/#'));
  });

  test('parseShareFragment reverses buildShareUrl exactly', () {
    final url = buildShareUrl(
      baseUrl: 'https://example.org/share/',
      shareKeyHex: 'ef' * 32,
      tripId: 'trip-with spaces',
      relayUrls: ['wss://relay.one', 'wss://relay.two'],
    );
    final fragment = url.split('#')[1];
    final parsed = parseShareFragment(fragment);
    expect(parsed.shareKeyHex, 'ef' * 32);
    expect(parsed.tripId, 'trip-with spaces');
    expect(parsed.relayUrls, ['wss://relay.one', 'wss://relay.two']);
  });

  test('parseShareFragment throws on a fragment missing a required part',
      () {
    expect(
      () => parseShareFragment('k=abc&trip=t1'), // no relays
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/safety/share_link_test.dart` — Expected: FAIL — `share_link.dart` doesn't exist.

- [ ] **Step 3: Implement `share_link.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Builds the shareable "watch this trip live" URL (spec §10
/// "Аялал-хуваалцах вэб"): a link to a static, server-less HTML page
/// (`docs/share/index.html`, Step 6 below) that reads straight from the
/// public Nostr relay network with no author infrastructure in the loop.
/// [shareKeyHex] is a throwaway keypair's *private* key
/// (`ShareSession.shareKeyPair.privateHex`) -- see this task's own doc
/// comment for exactly why putting a private key in a URL fragment is
/// safe here (it never leaves the browser that opens the link).
String buildShareUrl({
  required String baseUrl,
  required String shareKeyHex,
  required String tripId,
  required List<String> relayUrls,
}) {
  final relaysParam = relayUrls.map(Uri.encodeComponent).join(',');
  final fragment =
      'k=${Uri.encodeComponent(shareKeyHex)}&trip=${Uri.encodeComponent(tripId)}&relays=$relaysParam';
  final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  return '$normalizedBase#$fragment';
}

/// Reverses [buildShareUrl]'s fragment encoding. [docs/share/index.html]
/// mirrors this same three-field parse independently in plain JS (it
/// cannot depend on this Dart function) -- kept here for the app's own
/// "does my link actually round-trip" tests and any future in-app
/// "preview my share link" feature.
({String shareKeyHex, String tripId, List<String> relayUrls})
    parseShareFragment(String fragment) {
  final clean = fragment.startsWith('#') ? fragment.substring(1) : fragment;
  final params = Uri.splitQueryString(clean);
  final k = params['k'];
  final trip = params['trip'];
  final relays = params['relays'];
  if (k == null || trip == null || relays == null || relays.isEmpty) {
    throw const FormatException('share fragment missing k/trip/relays');
  }
  return (shareKeyHex: k, tripId: trip, relayUrls: relays.split(','));
}

/// Where the static share page is mirrored (spec §10: GitHub Pages or any
/// mirror). `docs/share/` is deliberately placed under `docs/` so
/// "serve Pages from /docs on main" needs zero extra CI/build config --
/// see FORKING.md (Task 10) for pointing this at a fork's own mirror. Open
/// protocol question (see Self-Review), same honesty pattern as Plan 4's
/// `kTakhiAppDownloadUrl`.
const String kShareBaseUrl = 'https://takhi-app.github.io/takhi/share/';
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/safety/share_link_test.dart` — Expected: PASS.

- [ ] **Step 5: Implement `ShareSession`**

`app/lib/safety/share_session.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import 'share_link.dart';

/// One active "аялал хуваалцах" session: a throwaway keypair minted the
/// moment the user taps "share", used only to receive a *second* copy of
/// this device's own live-location pings (wired in `ActiveTripView`, Step
/// 7 below) and to build the link handed to `share_plus`. Never persisted
/// -- a fresh [ShareSession] every time sharing is (re-)started, so an old
/// link naturally stops receiving new pings once the trip's live-location
/// stream ends (`ActiveTripView`'s tracking step disposes, per Plan 4).
class ShareSession {
  final KeyPair shareKeyPair;
  ShareSession() : shareKeyPair = generateKeyPair();

  String urlFor(String tripId, List<String> relayUrls) => buildShareUrl(
    baseUrl: kShareBaseUrl,
    shareKeyHex: shareKeyPair.privateHex,
    tripId: tripId,
    relayUrls: relayUrls,
  );
}
```

- [ ] **Step 6: Write the static share page (spec + approach)**

`docs/share/index.html`, vanilla HTML/CSS/JS, no build step, no framework — genuinely a single static file:

1. **On load:** read `location.hash`, parse the same three fields `parseShareFragment` extracts (`k`, `trip`, `relays`), using plain `URLSearchParams` on `location.hash.slice(1)`.
2. **Crypto:** `import { getPublicKey, nip44 } from 'https://esm.sh/nostr-tools@2'` (a `<script type="module">` ES-module import from a public CDN — the official, widely-used JS reference implementation of the same NIPs `takhi_protocol` implements in Dart, so its `nip44.v2.decrypt` is expected to interoperate byte-for-byte with `nip44Decrypt`, both being NIP-44 v2 conformant). Derive `const pubkey = getPublicKey(k)`.
3. **Relay connection:** open a `WebSocket` to each URL in `relays`, send `["REQ","share1",{"kinds":[20178],"#p":[pubkey],"#d":[trip]}]` on each `onopen`, and on every incoming `["EVENT","share1",<event>]` frame, decrypt `event.content` via `nip44.v2.decrypt(k, event.pubkey, event.content)`, `JSON.parse` the result (`{tripId, lat, lon}`, the exact shape `buildLiveLocationEvent`/`parseLiveLocationEvent` produce/consume, Plan 4 Task 2), and keep only the most recent by `event.created_at`.
4. **Render:** the latest `{lat, lon}` as large text, an `<iframe>` embedding `https://www.openstreetmap.org/export/embed.html?bbox=...&marker=lat,lon` (OSM's own official embeddable-map endpoint — no API key, no third-party map SDK), a "last updated Ns ago" ticking label, and — always, regardless of whether any location has arrived yet — a prominent "Тахь татах" button linking to `kTakhiAppDownloadUrl`'s value (Plan 4 Task 8; hardcode the same URL string here since this page cannot import Dart constants — keep the two literals in sync manually, called out as a `<!-- keep in sync with app/lib/meter/onboarding_qr_config.dart -->` comment in the HTML).
5. **No location received within, say, 60 seconds:** show a plain "аялал идэвхгүй эсвэл дуусгавар болсон" (inactive/ended) message instead of an indefinite spinner.

**Honest, explicitly-noted limitation:** this page's "static, no build step" claim comes with one caveat — it depends on `esm.sh` continuing to serve `nostr-tools` at that URL. A mirror operator who wants a byte-for-byte offline-capable copy needs to also vendor `nostr-tools`' browser bundle locally and change one `import` line; this is called out directly in the HTML file's own top comment and in `FORKING.md` (Task 10), rather than silently overclaiming full self-containment.

- [ ] **Step 7: Add the share button to `ActiveTripView` (once Plan 4 exists)**

Add `share_plus` to `app/pubspec.yaml`:

```yaml
  share_plus: ^10.1.4
```

Run (from `app/`): `flutter pub get`

In `app/lib/ride/active_trip_view.dart`'s tracking step, add a new private field `ShareSession? _shareSession` and a share `IconButton`:

```dart
IconButton(
  icon: const Icon(Icons.share),
  tooltip: l.shareTripAction,
  onPressed: () {
    _shareSession ??= ShareSession();
    unawaited(Share.share(
      _shareSession!.urlFor(widget.tripId, defaultRelayUrls),
    ));
  },
),
```

Then, in the same tracking-step location-fix handler that already forwards each `GpsFix` to `ref.read(liveLocationChannelProvider).send(recipientPubHex: widget.counterpartyPubHex, ...)` on Plan 4's chosen throttle cadence (Task 3's `LiveLocationChannel`), add one more conditional send right alongside it:

```dart
if (_shareSession != null) {
  unawaited(ref.read(liveLocationChannelProvider).send(
    senderPrivHex: identity.privHex,
    recipientPubHex: _shareSession!.shareKeyPair.publicHex,
    tripId: widget.tripId,
    lat: fix.lat,
    lon: fix.lon,
    now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  ));
}
```

This is intentionally described in terms of "wherever Plan 4's throttled send already happens" rather than an exact line number, since `active_trip_view.dart` does not exist as code yet at plan-writing time (only Plan 4's own approach description does) — the implementer wires this alongside whatever concrete throttle mechanism Plan 4 ends up choosing (Plan 4 Task 7's own Self-Review left the exact mechanism as an implementer choice too).

- [ ] **Step 8: Add this task's ARB keys**

`app/lib/l10n/app_mn.arb`:

```json
  "shareTripAction": "Аялал хуваалцах"
```

`app/lib/l10n/app_en.arb`:

```json
  "shareTripAction": "Share trip"
```

- [ ] **Step 9: Wire providers**

`app/lib/safety/safety_providers.dart` (this task creates the file; Task 9 extends it):

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Intentionally near-empty for now -- ShareSession is created directly by
// ActiveTripView (a fresh one per "start sharing" tap, not a singleton),
// so it needs no provider of its own. This file exists from Task 8 onward
// so Task 9's EmergencyContactStore provider has an established home
// alongside it, matching call_providers.dart's role for app/lib/call/.
```

- [ ] **Step 10: Run and commit**

Run: `flutter test test/safety/share_link_test.dart` — Expected: PASS.

```bash
git add app/lib/safety/share_link.dart app/lib/safety/share_session.dart app/lib/safety/safety_providers.dart app/lib/ride/active_trip_view.dart app/lib/l10n app/pubspec.yaml app/pubspec.lock docs/share/index.html app/test/safety/share_link_test.dart
git commit -m "feat(app): server-less trip-share (throwaway-key live location + static page)"
```

### Task 9: SOS button — native dialer + native SMS (`app/lib/safety/`)

**Files:**
- Create: `app/lib/safety/sos_service.dart`
- Create: `app/lib/safety/emergency_contact_store.dart`
- Create: `app/lib/safety/sos_button.dart` (spec + approach)
- Create: `app/lib/safety/emergency_contact_settings_page.dart` (spec + approach)
- Modify: `app/lib/safety/safety_providers.dart`
- Modify: `app/lib/ride/active_trip_view.dart` (Plan 4 deliverable — add the SOS button)
- Modify: `app/lib/router.dart` (settings route)
- Modify: `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb`
- Test: `app/test/safety/sos_service_test.dart`
- Test: `app/test/safety/emergency_contact_store_test.dart`

**Interfaces:**
- Consumes: `GpsFix`, `plusCodeEncode` (`takhi_protocol`).
- Produces: `const kPoliceNumber = '102'; const kAmbulanceNumber = '103'; const kFireNumber = '101';`; `Uri buildEmergencyDialUri(String number)`; `Uri buildEmergencySmsUri({required String contactPhone, required String plusCode, required double lat, required double lon})`; `abstract interface class EmergencyContactStore { Future<String?> loadPhone(); Future<void> savePhone(String phone); }`; `SharedPreferencesEmergencyContactStore`, `InMemoryEmergencyContactStore`; `emergencyContactStoreProvider`; `class SosButton extends ConsumerWidget { const SosButton({GpsFix? lastFix}); }`; `class EmergencyContactSettingsPage extends ConsumerStatefulWidget`.
- Consumed by: `ActiveTripView`'s tracking step (this task's final wiring step).

- [ ] **Step 1: Write the failing tests for the pure URI builders**

`app/test/safety/sos_service_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/safety/sos_service.dart';

void main() {
  test('buildEmergencyDialUri produces a tel: URI for the given number', () {
    final uri = buildEmergencyDialUri(kPoliceNumber);
    expect(uri.scheme, 'tel');
    expect(uri.path, '102');
  });

  test('buildEmergencyDialUri works for the ambulance and fire numbers too',
      () {
    expect(buildEmergencyDialUri(kAmbulanceNumber).path, '103');
    expect(buildEmergencyDialUri(kFireNumber).path, '101');
  });

  test('buildEmergencySmsUri addresses the contact and includes the Plus '
      'Code in the body', () {
    final uri = buildEmergencySmsUri(
      contactPhone: '99887766',
      plusCode: '8Q7XPJ9Q+2V',
      lat: 47.9186,
      lon: 106.9176,
    );
    expect(uri.scheme, 'sms');
    expect(uri.path, '99887766');
    final body = uri.queryParameters['body']!;
    expect(body.contains('8Q7XPJ9Q+2V'), isTrue);
    expect(body.contains('47.9186'), isTrue);
    expect(body.contains('106.9176'), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails, then implement**

Run: `flutter test test/safety/sos_service_test.dart` — Expected: FAIL.

`app/lib/safety/sos_service.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Official Mongolian emergency numbers (spec §6 SOS: "native dialer-ээр
/// 102/103"). Fire is included too even though the spec text names only
/// police/ambulance -- showing all three costs nothing extra and is more
/// useful in a real emergency.
const String kPoliceNumber = '102';
const String kAmbulanceNumber = '103';
const String kFireNumber = '101';

/// A `tel:` URI that opens the phone's native dialer pre-filled with
/// [number] -- `ACTION_DIAL`, not `ACTION_CALL`: the user still presses
/// the call button themselves on their own device's own dialer UI.
/// Deliberate: this app never requests the `CALL_PHONE` permission, so it
/// structurally cannot place a call the user did not explicitly confirm.
Uri buildEmergencyDialUri(String number) => Uri(scheme: 'tel', path: number);

/// An `sms:` URI pre-filled with an emergency body naming [plusCode]
/// (spec §6: "сүүлийн байршлыг (Plus Code)") plus a plain-coordinates OSM
/// link, addressed to [contactPhone] -- the user's own pre-configured
/// emergency contact (`EmergencyContactStore`), never a number this app
/// chose on its own. Opens the phone's native SMS app; the user still
/// presses send themselves (no `SEND_SMS` permission is ever requested).
Uri buildEmergencySmsUri({
  required String contactPhone,
  required String plusCode,
  required double lat,
  required double lon,
}) {
  final body =
      'SOS. Миний сүүлийн байршил: $plusCode '
      '(https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon)';
  return Uri(
    scheme: 'sms',
    path: contactPhone,
    queryParameters: {'body': body},
  );
}
```

- [ ] **Step 3: Run to verify it passes**

Run: `flutter test test/safety/sos_service_test.dart` — Expected: PASS.

- [ ] **Step 4: Write the failing tests for `EmergencyContactStore`**

`app/test/safety/emergency_contact_store_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/safety/emergency_contact_store.dart';

void main() {
  test('loadPhone is null until savePhone is called', () async {
    final store = InMemoryEmergencyContactStore();
    expect(await store.loadPhone(), isNull);
    await store.savePhone('99887766');
    expect(await store.loadPhone(), '99887766');
  });
}
```

- [ ] **Step 5: Run to verify it fails, then implement**

Run: `flutter test test/safety/emergency_contact_store_test.dart` — Expected: FAIL.

`app/lib/safety/emergency_contact_store.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// The user's own pre-configured emergency contact number (spec §6 SOS).
/// Local-only, never published or sent anywhere except as the `sms:`
/// intent's destination the user themselves confirms sending -- mirrors
/// `PhoneShareSettingsStore`/`TariffStore`'s interface shape exactly.
abstract interface class EmergencyContactStore {
  Future<String?> loadPhone();
  Future<void> savePhone(String phone);
}

const _kPhoneKey = 'takhi_emergency_contact_phone';

class SharedPreferencesEmergencyContactStore implements EmergencyContactStore {
  final Future<SharedPreferences> Function() _instance;
  SharedPreferencesEmergencyContactStore(this._instance);

  @override
  Future<String?> loadPhone() async =>
      (await _instance()).getString(_kPhoneKey);

  @override
  Future<void> savePhone(String phone) async =>
      (await _instance()).setString(_kPhoneKey, phone);
}

class InMemoryEmergencyContactStore implements EmergencyContactStore {
  String? _phone;
  @override
  Future<String?> loadPhone() async => _phone;
  @override
  Future<void> savePhone(String phone) async => _phone = phone;
}
```

- [ ] **Step 6: Run to verify it passes, then wire the provider**

Run: `flutter test test/safety/emergency_contact_store_test.dart` — Expected: PASS.

Add to `app/lib/safety/safety_providers.dart` (replacing Task 8's near-empty placeholder comment):

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'emergency_contact_store.dart';

final emergencyContactStoreProvider = Provider<EmergencyContactStore>(
  (ref) => SharedPreferencesEmergencyContactStore(
    SharedPreferences.getInstance,
  ),
);
```

- [ ] **Step 7: Build `SosButton` and `EmergencyContactSettingsPage` (spec + approach)**

`app/lib/safety/sos_button.dart`, a `ConsumerWidget` taking an optional `GpsFix? lastFix`:

1. Renders a small, always-visible, unmistakably-red `IconButton` (`Icons.emergency`, `color: Colors.red`) labeled via `tooltip: l.sosAction`.
2. On tap: `showModalBottomSheet` with three rows built from `ref.read(emergencyContactStoreProvider).loadPhone()`'s result: **"102 — цагдаа"**, **"103 — түргэн тусламж"** (both call `buildEmergencyDialUri` + `launchUrl`), and, only if a contact phone is saved, **"Яаралтай холбоо барих хүнд SMS"** (`buildEmergencySmsUri` using `lastFix`'s `lat`/`lon` and `plusCodeEncode(lat, lon)`, or a `l.locationUnavailableHint` fallback line in the body when `lastFix == null` + `launchUrl`). If no contact phone is saved, that third row is replaced with a single line + button linking to `EmergencyContactSettingsPage` instead.
3. Every action in this sheet is one `url_launcher` call plus, per Global Constraints, nothing else — no confirmation dialog is layered *in front of* the OS's own dialer/SMS-app confirmation, since adding one would only slow down a genuine emergency; the bottom sheet itself (which needs an explicit tap to open, and a second explicit tap to pick an action) is already the deliberate one-step-removed-from-accidental safeguard.

`app/lib/safety/emergency_contact_settings_page.dart`, a `ConsumerStatefulWidget`:

1. Reuses the single-field-and-button layout already established twice in this codebase (`_PriceStep` in `passenger_ride_page.dart`, the tariff-entry step in Plan 4's `TaximeterPage`) — a numeric-keyboard `TextField` (`l.emergencyContactPhoneFieldLabel`) and a `PrimaryButton` (`l.saveEmergencyContactAction`) calling `ref.read(emergencyContactStoreProvider).savePhone(...)` then `Navigator.pop`.

- [ ] **Step 8: Add this task's ARB keys**

`app/lib/l10n/app_mn.arb`:

```json
  "sosAction": "SOS",
  "emergencyContactPhoneFieldLabel": "Яаралтай үед холбогдох дугаар",
  "saveEmergencyContactAction": "Хадгалах",
  "locationUnavailableHint": "Байршил тодорхойгүй байна"
```

`app/lib/l10n/app_en.arb`:

```json
  "sosAction": "SOS",
  "emergencyContactPhoneFieldLabel": "Emergency contact number",
  "saveEmergencyContactAction": "Save",
  "locationUnavailableHint": "Location unavailable"
```

- [ ] **Step 9: Add the settings route**

In `app/lib/router.dart`, add to `routes:`:

```dart
GoRoute(
  path: '/settings/emergency-contact',
  builder: (context, state) => const EmergencyContactSettingsPage(),
),
```

- [ ] **Step 10: Wire `SosButton` into `ActiveTripView` (once Plan 4 exists)**

In `app/lib/ride/active_trip_view.dart`'s tracking step, add `SosButton(lastFix: _track.fixes.isEmpty ? null : _track.fixes.last)` alongside the call/share `IconButton`s added by Tasks 7/8 — `_track` (the `GpsTrackAccumulator` Plan 4 Task 7 already keeps on this exact `State`) is already in scope, so this needs no new plumbing, only the one extra widget in the same row.

- [ ] **Step 11: Full re-run and commit**

Run: `flutter test test/safety/` — Expected: PASS (all files).

```bash
git add app/lib/safety/sos_service.dart app/lib/safety/emergency_contact_store.dart app/lib/safety/sos_button.dart app/lib/safety/emergency_contact_settings_page.dart app/lib/safety/safety_providers.dart app/lib/ride/active_trip_view.dart app/lib/router.dart app/lib/l10n app/test/safety/sos_service_test.dart app/test/safety/emergency_contact_store_test.dart
git commit -m "feat(app): SOS button -- native dialer + native SMS, no server"
```

### Task 10: Polish, city-agnostic seam, world-spread docs, and release APK

**Files:**
- Create: `app/lib/config/city_config.dart`
- Modify: `app/lib/ride/passenger_ride_page.dart`, `app/lib/ride/driver_inbox_page.dart`, `app/lib/meter/taximeter_page.dart` (reference `defaultCityConfig` instead of local lat/lon consts, once each exists)
- Modify: `app/pubspec.yaml` (font family declaration, `flutter_native_splash` dev dependency + config)
- Create: `app/assets/fonts/NotoSans-Regular.ttf`, `app/assets/fonts/NotoSans-Bold.ttf` (vendored, binary — fetched via command, not written by hand)
- Modify: `app/lib/theme/takhi_theme.dart` (remove the "fallback ok now" comment, confirm `fontFamily: 'NotoSans'`)
- Test: `app/test/design_system_audit_test.dart`
- Test: `app/test/l10n_completeness_test.dart`
- Test: `app/test/config/city_config_test.dart`
- Modify: `PROTOCOL.md`
- Create: `FORKING.md`
- Create: `HELPER.md`
- Create: `LICENSE`
- Modify: `README.md` (root — currently missing; create it)
- Modify: `app/android/app/build.gradle.kts` (real release signing config)
- Modify: `.gitignore` (exclude the release keystore/`key.properties`)

**Interfaces:**
- Produces: `class CityConfig { final String name; final double centerLat, centerLon; const CityConfig({...}); }`; `const CityConfig defaultCityConfig`.

- [ ] **Step 1: City-agnostic config seam**

Write the failing test first — `app/test/config/city_config_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/config/city_config.dart';

void main() {
  test('defaultCityConfig is Ulaanbaatar, Sukhbaatar Square', () {
    expect(defaultCityConfig.name, 'Улаанбаатар');
    expect(defaultCityConfig.centerLat, closeTo(47.9186, 0.001));
    expect(defaultCityConfig.centerLon, closeTo(106.9176, 0.001));
  });
}
```

Run: `flutter test test/config/city_config_test.dart` — Expected: FAIL.

`app/lib/config/city_config.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The one seam spec §11 calls for ("Хотын багц" = config JSON: map
/// center, default relay hints, locale) collapsed to its smallest useful
/// form for this MVP: just the map's starting center, which is the only
/// literal city-specific value that was actually hardcoded and duplicated
/// across `passenger_ride_page.dart`, `driver_inbox_page.dart`, and
/// `taximeter_page.dart` (each previously defined its own
/// `_defaultLat`/`_defaultLon`/`_defaultCityCenter` consts, all three
/// pointing at the same coordinates). `FORKING.md` points a new city's
/// fork at exactly this one file. `defaultRelayUrls` (Plan 2,
/// `nostr/relay_pool_provider.dart`) and locale (`app/lib/l10n/`,
/// `MaterialApp.router`'s `locale:`) remain their own separate seams --
/// unifying all three into one `CityConfig` object is a reasonable future
/// step once a second city fork actually exists to prove out the right
/// shape (YAGNI: no second fork exists yet to design against).
class CityConfig {
  final String name;
  final double centerLat;
  final double centerLon;

  const CityConfig({
    required this.name,
    required this.centerLat,
    required this.centerLon,
  });
}

/// Ulaanbaatar, Sukhbaatar Square -- the coordinates every ride/taximeter
/// screen already defaulted to independently before this task.
const CityConfig defaultCityConfig = CityConfig(
  name: 'Улаанбаатар',
  centerLat: 47.9186,
  centerLon: 106.9176,
);
```

Run: `flutter test test/config/city_config_test.dart` — Expected: PASS.

Once Plans 3/4 exist as real code, replace each of `passenger_ride_page.dart`'s `_defaultLat`/`_defaultLon`/`_defaultCityCenter`, `driver_inbox_page.dart`'s `_defaultCityCenter`, and `taximeter_page.dart`'s equivalent with `defaultCityConfig.centerLat`/`.centerLon`/`ll.LatLng(defaultCityConfig.centerLat, defaultCityConfig.centerLon)` and delete the three now-redundant local const definitions — a mechanical, behavior-preserving find-and-replace (same numeric values, just one source of truth instead of three). Re-run each file's existing widget tests after the substitution to confirm no assertion depended on the removed private consts' names.

- [ ] **Step 2: Design-system audit test**

`app/test/design_system_audit_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no widget file hardcodes a raw Color(0x... outside the theme file',
      () {
    final libDir = Directory('lib');
    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.replaceAll('\\', '/').endsWith('theme/takhi_theme.dart')) {
        continue; // the one file allowed to define raw palette values
      }
      final content = entity.readAsStringSync();
      if (RegExp(r'Color\(0x').hasMatch(content)) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Hardcoded Color(0x...) outside theme/takhi_theme.dart -- use '
          'TakhiColors.* or Theme.of(context).colorScheme instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
```

This is a real, mechanical design-system guard, not a placeholder: it fails loudly and lists exact file paths the moment any future widget reaches for a raw hex color instead of the theme, which is precisely what "апп даяар light/dark theme аудит" (Global Constraints/scope item 4) needs to be an enforced check rather than a one-time manual pass. Run it now against the codebase as it stands after Plans 1-4 plus this plan's own Tasks 1-9; fix any offender it finds (there should be none, since every widget written across all five plans already routes through `TakhiColors`/`Theme.of(context).colorScheme`, but this is the point where that claim gets verified rather than assumed).

Run: `flutter test test/design_system_audit_test.dart` — Expected: PASS (or fix the flagged files until it does).

- [ ] **Step 3: i18n completeness test**

`app/test/l10n_completeness_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app_mn.arb and app_en.arb declare exactly the same translation '
      'keys', () {
    final mn = jsonDecode(
      File('lib/l10n/app_mn.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final en = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

    // '@@locale' and per-key '@key' metadata blocks are ARB tooling
    // scaffolding, not translation strings -- excluded from the
    // key-parity check (a metadata block existing only in one file is
    // not a missing translation).
    bool isTranslationKey(String k) => !k.startsWith('@');

    final mnKeys = mn.keys.where(isTranslationKey).toSet();
    final enKeys = en.keys.where(isTranslationKey).toSet();

    final missingFromEn = mnKeys.difference(enKeys);
    final missingFromMn = enKeys.difference(mnKeys);

    expect(
      missingFromEn,
      isEmpty,
      reason: 'Keys in app_mn.arb with no app_en.arb translation: '
          '$missingFromEn',
    );
    expect(
      missingFromMn,
      isEmpty,
      reason: 'Keys in app_en.arb with no app_mn.arb source: $missingFromMn',
    );
  });

  test('every non-empty string value in app_en.arb differs from its '
      'app_mn.arb counterpart (catches a forgotten/copy-pasted '
      'translation)', () {
    final mn = jsonDecode(
      File('lib/l10n/app_mn.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final en = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

    final suspicious = <String>[];
    for (final key in mn.keys) {
      if (key.startsWith('@')) continue;
      final mnValue = mn[key];
      final enValue = en[key];
      if (mnValue is! String || enValue is! String) continue;
      // A handful of keys are legitimately identical across languages
      // (a bare number placeholder string, a brand name, "SOS", '102').
      const allowedIdentical = {'appName', 'sosAction'};
      if (mnValue == enValue &&
          mnValue.isNotEmpty &&
          !allowedIdentical.contains(key)) {
        suspicious.add(key);
      }
    }
    expect(
      suspicious,
      isEmpty,
      reason: 'Keys whose en value is identical to mn (likely untranslated): '
          '$suspicious',
    );
  });
}
```

Run: `flutter test test/l10n_completeness_test.dart` — Expected: PASS (or fix any flagged key — every ARB addition across Plans 1-5 was written with both files edited together, so this is a verification gate, not expected to find real gaps, but it is the mechanical check that makes "i18n бүрэн эсэх шалгалт" (scope item 4) an enforced fact rather than a claim).

- [ ] **Step 4: Bundle NotoSans**

Vendor two static weights of Noto Sans (OFL-1.1 licensed, the family already named as the app's `fontFamily` since Plan 2's `takhi_theme.dart`, currently falling back to the platform default):

```bash
mkdir -p app/assets/fonts
curl -L -o app/assets/fonts/NotoSans-Regular.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/notosans/NotoSans%5Bwdth%2Cwght%5D.ttf"
curl -L -o app/assets/fonts/NotoSans-Bold.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/notosans/NotoSans-Bold.ttf"
```

**Confirm both exact paths against the live `google/fonts` repository before running** — Noto Sans is currently distributed there as a single variable font (`NotoSans[wdth,wght].ttf`, covering weights 100-900 in one file) rather than separate static `-Regular`/`-Bold` files; if a static `-Bold` file no longer exists at that path, download only the variable font once and reference the same file for both weights in `pubspec.yaml`'s `fonts:` block (Flutter selects the requested weight from a variable font automatically via `FontWeight`). This is called out explicitly, the same way Plan 4 flagged `geolocator`'s exact API and this plan's own Task 4 flagged `flutter_webrtc`'s exact enum spelling — confirm the live shape, don't assume the plan's guess is exact.

In `app/pubspec.yaml`, under the `flutter:` section:

```yaml
  fonts:
    - family: NotoSans
      fonts:
        - asset: assets/fonts/NotoSans-Regular.ttf
        - asset: assets/fonts/NotoSans-Bold.ttf
          weight: 700
```

And add `- assets/fonts/` (or list the two files explicitly) to the existing `assets:` list.

In `app/lib/theme/takhi_theme.dart`, change:

```dart
    fontFamily: 'NotoSans', // bundled in Task later; fallback ok now
```

to:

```dart
    fontFamily: 'NotoSans', // bundled: assets/fonts/ (Cyrillic-complete)
```

Run: `flutter pub get` then `flutter test test/theme_test.dart test/dark_theme_test.dart` — Expected: PASS unchanged (these tests assert color/scheme behavior, not font rendering, so bundling the actual font file doesn't change their assertions — it changes what a human sees on a real device, verified manually per Step 8's screenshot check below).

- [ ] **Step 5: Splash screen**

Add to `app/pubspec.yaml` under `dev_dependencies:`:

```yaml
  flutter_native_splash: ^2.4.4
```

And a top-level config block:

```yaml
flutter_native_splash:
  color: "#F4F1E9"
  image: brand/out/takhi_horse_ink.png
  color_dark: "#1C1A16"
  image_dark: brand/out/takhi_horse_gold.png
  android_12:
    color: "#F4F1E9"
    image: brand/out/takhi_horse_ink.png
    color_dark: "#1C1A16"
    image_dark: brand/out/takhi_horse_gold.png
```

(`brand/out/takhi_horse_ink.png`/`takhi_horse_gold.png` are the already-produced transparent-silhouette brand assets, `BRAND.md`'s own "watermark, дотоод UI-д" use case — light background gets the dark-ink horse, dark background gets the gold horse, matching `takhi_theme.dart`'s existing light/dark surface colors exactly.)

Run:

```bash
flutter pub get
dart run flutter_native_splash:create
```

This generates the native Android splash resources (`android/app/src/main/res/drawable*/`) — a real, one-time code-generation step, not something `flutter test` covers; verify by actually launching the app (`flutter run`) and observing the splash frame.

- [ ] **Step 6: App icon — actually run the already-configured generator**

`app/pubspec.yaml`'s `flutter_launcher_icons:` block has been configured since Plan 2 (gold background, brand mark, per `BRAND.md`) but was never executed. Run it now:

```bash
dart run flutter_launcher_icons
```

Verify `app/android/app/src/main/res/mipmap-*/ic_launcher.png` were (re)generated with the brand mark, not the default Flutter icon.

- [ ] **Step 7: Finalize `PROTOCOL.md`**

Update §3's kind table: kind `30178`'s "Хэрэгжилт" column changes from "kind тогтмол ... тодорхойлогдсон; builder Plan 5 (P2P дуудлага)-д" to `` `buildHelperAnnouncement` / `parseHelperAnnouncement` (Plan 5) ``.

Add a new §4.5 documenting that call signaling (`call_offer`/`call_answer`/`call_ice`/`call_hangup`) and the voice-message fallback (`voice_note`) both ride the *existing* kind-1059 gift-wrap DM channel (§4.3's `RideDmPayload`-equivalent wire family) as five additional `type` discriminator values — no new top-level Nostr kind was needed for any of them, which is itself worth stating explicitly (a reader scanning only the kind table in §3 could otherwise wrongly conclude calling needed a new kind).

Add a new §7 (renumbering the current §7-12 down by one, or appending as §13 before the existing §11/§12 — pick whichever keeps the document's own internal cross-references consistent, and grep the file for every `§N` self-reference before renumbering to catch all of them) documenting `kDefaultStunServers`, `buildIceServers`, and the kind-30178 helper-discovery flow end to end, cross-referencing `HELPER.md`.

Remove the final "Deviation" bullet in the current §11 that refers to kind `30178`'s builder being unimplemented (it is, as of this plan).

Bump the version line at the top from `0.1.0` to `0.2.0` — the reference implementation is now feature-complete against the spec's MVP list (§14), which is a real, user-visible milestone worth a minor version bump, not a cosmetic one.

- [ ] **Step 8: Write `FORKING.md`**

```markdown
# Тахь-г өөр хотод/улсад асаах — FORKING.md

Энэ протокол хот-агностик (спек §11): УБ ямар ч тусгай эрх эдэлдэггүй,
кодонд hardcode-логдоогүй.

1. **Fork хий.** GitHub дээр "Fork", эсвэл `git clone` + шинэ origin.
2. **Хотын төв солих.** `app/lib/config/city_config.dart`-ийн
   `defaultCityConfig`-г өөрийн хотын координатаар солино уу.
3. **Брэнд солих (сонголттой).** `brand/` доtorх лого/өнгө, `app/lib/
   theme/takhi_theme.dart`-ийн `TakhiColors`, `applicationId`
   (`app/android/app/build.gradle.kts`) өөрийн нэрээр.
4. **Relay жагсаалт шалга.** `app/lib/nostr/relay_pool_provider.dart`-ийн
   `defaultRelayUrls` таны бүс нутагт хүрдэг эсэхийг шалгаад шаардлагатай
   бол өөрчил.
5. **Аялал-хуваалцах хуудас.** `docs/share/index.html`-г GitHub Pages-ээр
   ("Settings → Pages → Deploy from /docs")  нийтэл, `app/lib/safety/
   share_link.dart`-ийн `kShareBaseUrl`-г шинэ URL-аараа солино уу.
6. **APK build.** `docs/superpowers/plans/2026-07-22-takhi-calling-safety-ship.md`-ийн
   Task 10-ийн build алхмуудыг дага (өөрийн release keystore үүсгэнэ).
7. Ингээд та зохиогчоос **бүрэн хараат бус**, протоколын хувьд бүрэн
   нийцтэй, өөрийн хот/улсад ажилладаг Тахь-ийн хувилбартай боллоо.
   AGPL-3.0 нь зөвхөн танай өөрчлөлт нээлттэй хэвээр байхыг шаардана —
   бусад бүх зүйл чөлөөтэй.
```

- [ ] **Step 9: Write `HELPER.md`**

```markdown
# Туслагч зангилаа (blind TURN relay) асаах — HELPER.md

Спек §6/§7.3-①: хэн ч энэ зангилааг ажиллуулж, Nostr-оор зарлаж болно.
Зохиогч ХЭЗЭЭ Ч энэ зангилааг ажиллуулахгүй.

## 1. coturn суулгах

Жижиг VM (1 vCPU / 512MB хангалттай):

```bash
sudo apt install coturn
```

`/etc/turnserver.conf`:

```
listening-port=3478
realm=takhi-helper
use-auth-secret
static-auth-secret=<өөрийн нууц үг>
```

```bash
sudo systemctl enable --now coturn
```

## 2. Nostr-оор зарлах

`nak` (nostr army knife, https://github.com/fiatjaf/nak) ашиглан:

```bash
nak event -k 30178 \
  --tag d=<өвөрмөц-helper-id> \
  --tag host=<таны IP эсвэл домэйн> \
  --tag port=3478 \
  --tag expiration=$(($(date +%s) + 3600)) \
  --content "<static-auth-secret>" \
  --sec <таны Nostr хувийн түлхүүр> \
  wss://relay.damus.io wss://nos.lol
```

Эсвэл `packages/takhi_protocol`-ийн `buildHelperAnnouncement` функцийг Dart
скриптдээ шууд ашиглаж болно (жишээ: `tool/announce_helper.dart`,
`buildHelperAnnouncement` + `signEvent` + WebSocket publish).

## 3. Дахин зарлах

`expiration` (NIP-40) tag-тай тул зарлал хугацаа дуусахад автоматаар
устана. Cron-оор 30 минут тутам дахин зарлаарай:

```
*/30 * * * * /path/to/announce.sh
```

## 4. Болоо

Ямар ч Тахь клиент (энэ апп, эсвэл өөр хэн нэгний бичсэн бусад клиент)
таны зарлалыг олж, ICE тохиргоондоо автоматаар нэмнэ. Бүртгэл,
зөвшөөрөл шаардахгүй.
```

- [ ] **Step 10: `LICENSE` and root `README.md`**

```bash
curl -o LICENSE https://www.gnu.org/licenses/agpl-3.0.txt
```

Root `README.md` (currently missing at the repo root — only `app/README.md`'s generic Flutter boilerplate exists):

```markdown
# Тахь (takhi)

Эзэнгүй, шимтгэлгүй, нээлттэй эхийн такси-учралын апп — Nostr дээр
суурилсан. Жолооч, зорчигч хоёр шууд учирч, өөрсдөө үнээ тохирч,
өөрсдөө төлбөрөө шийддэг. Голд нь хэн ч байхгүй.

## Баримт бичгүүд

- [`docs/superpowers/specs/2026-07-21-takhi-design.md`](docs/superpowers/specs/2026-07-21-takhi-design.md) — бүрэн дизайны спек
- [`PROTOCOL.md`](PROTOCOL.md) — протоколын лавлагаа (kind, event схем)
- [`FORKING.md`](FORKING.md) — өөр хот/улсад асаах заавар
- [`HELPER.md`](HELPER.md) — туслагч зангилаа (blind TURN relay) асаах заавар
- [`brand/BRAND.md`](brand/BRAND.md) — брэнд систем
- [`LICENSE`](LICENSE) — AGPL-3.0-or-later

## Бүтэц

```
takhi/
├── packages/takhi_protocol/   # цэвэр Dart протокол (UI-гүй, сервергүй)
└── app/                       # Flutter апп "Тахь"
```

## Ажиллуулах

```bash
cd app
flutter pub get
flutter run
```

## Лиценз

AGPL-3.0-or-later. CLA байхгүй. Нийтийн өмч хэвээр үлдэнэ.
```

- [ ] **Step 11: Real release signing**

Generate a real release keystore (interactive — the passphrase is a secret, never scripted/hardcoded, per this project's Dart/Flutter security rule):

```bash
keytool -genkey -v -keystore app/android/takhi-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias takhi
```

Create `app/android/key.properties` (gitignored, Step 12):

```properties
storePassword=<the password just entered>
keyPassword=<the password just entered>
keyAlias=takhi
storeFile=takhi-release.jks
```

In `app/android/app/build.gradle.kts`, replace the placeholder release block:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ... existing namespace/compileSdk/defaultConfig unchanged ...

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}
```

(The `if (keystorePropertiesFile.exists())` fallback to debug-signing keeps CI/contributors who have not generated their own keystore able to build a *debug-signed* release variant locally without erroring — only the actual shipped APK, built on a machine that has run Step 11, is properly signed.)

- [ ] **Step 12: Update `.gitignore`**

Append to `.gitignore`:

```
app/android/key.properties
app/android/*.jks
app/android/*.keystore
build/debug-info/
```

- [ ] **Step 13: Build the release APK**

```bash
cd app
flutter analyze
flutter test
dart test --directory=../packages/takhi_protocol
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

Verify size (spec §10: "APK < 40MB"):

```bash
ls -la build/app/outputs/flutter-apk/app-release.apk
```

If it exceeds 40MB, the most likely single cause given this plan's additions is `flutter_webrtc`'s native binaries across multiple ABIs — build a per-ABI split instead of one universal APK:

```bash
flutter build apk --release --obfuscate --split-debug-info=build/debug-info --split-per-abi
```

and distribute the `arm64-v8a` variant as the primary download (the overwhelming majority of Android phones in use in Mongolia, matching the rest of the world, are arm64) with the others available as alternates.

- [ ] **Step 14: Final commit**

```bash
git add app/lib/config app/lib/theme/takhi_theme.dart app/lib/ride/passenger_ride_page.dart app/lib/ride/driver_inbox_page.dart app/lib/meter/taximeter_page.dart app/pubspec.yaml app/pubspec.lock app/assets/fonts app/test/design_system_audit_test.dart app/test/l10n_completeness_test.dart app/test/config/city_config_test.dart PROTOCOL.md FORKING.md HELPER.md LICENSE README.md app/android/app/build.gradle.kts .gitignore
git commit -m "chore(release): city config seam, bundled font, splash/icon, PROTOCOL.md finalized, FORKING/HELPER/LICENSE, signed release build"
```

The generated `app/android/takhi-release.jks`, `app/android/key.properties`, and `build/app/outputs/flutter-apk/app-release.apk` are **not** part of this commit — the first two are secrets excluded by `.gitignore` (Step 12), the APK itself is a release artifact uploaded to GitHub Releases (`kTakhiAppDownloadUrl`, Plan 4 Task 8), never committed to the repository.

---

## Self-Review

**1. Spec coverage (brief scope item → task):**
- Scope item 1 (P2P voice calling, `flutter_webrtc`, NIP-17 DM signaling, public STUN config, community blind-relay/TURN discovery via kind `30178`) → Task 1 (protocol event) + Task 2 (signaling payloads/channel) + Task 3 (STUN/helper ICE config) + Task 4 (`CallEngine`) + Task 7 (`CallService`/`CallScreen`). The "P2P vs. helper-relay isn't two app-level attempts, ICE handles it internally" correction is stated explicitly in Task 3/5's doc comments rather than left as an implicit assumption.
- Scope item 2 (fallback chain: P2P → helper → phone (opt-in, toggle default on) → voice note ≤10s/~30KB, auto-drops on CGNAT) → Task 5 (`decideFallbackAction`, phone toggle + handoff field) + Task 6 (voice note) + Task 7 (`CallService` wires the whole chain together and is the one place all three rungs are actually driven end to end, verified by `call_service_test.dart`'s three fallback-path tests).
- Scope item 3a (trip-share: static HTML, key in URL fragment, browser reads relay directly, app-less viewer, native share/SMS) → Task 8, end to end (`buildShareUrl`/`parseShareFragment` pure and tested, `ShareSession`'s throwaway-keypair design, `docs/share/index.html` spec+approach, `share_plus` wiring).
- Scope item 3b (SOS: native dialer 102/103, SMS with Plus Code to a pre-configured contact, no server) → Task 9, end to end (`buildEmergencyDialUri`/`buildEmergencySmsUri` pure and tested, `EmergencyContactStore`, `SosButton`).
- Scope item 4 (NotoSans bundling, light/dark theme audit, i18n completeness, brand icon/splash) → Task 10 Steps 2-6 (`design_system_audit_test.dart` and `l10n_completeness_test.dart` are real enforced checks, not one-time manual passes; splash/icon are real generator invocations, not just config that sits unused as it currently does).
- Scope item 5 (PROTOCOL.md finalized, FORKING.md, HELPER.md, city-agnostic config check) → Task 10 Steps 1, 7, 8, 9.
- Scope item 6 (`flutter build apk --release` succeeding, README + LICENSE) → Task 10 Steps 10-13, plus the real signed/obfuscated build this project's own security rule requires rather than shipping the current debug-signed placeholder.
- Spec §7.3's three-channel description (①②③, in that order, with ② and ③ both usable simultaneously as long as ① has failed) is reflected exactly in `decideFallbackAction`'s three-way branch and `CallService._applyFallback`'s call site.
- Spec §13's iOS driver-mode caveat is extended, honestly, to iOS incoming-calling specifically (Task 7's own "iOS note"), and to the plain fact that `app/ios/` does not exist in this repository at all yet (Global Constraints) — neither is glossed over.

**2. Placeholder scan:** No `TODO`/`TBD`/"handle appropriately" anywhere. Several spots that look unusual are intentional, flagged uncertainties rather than placeholders, matching the exact pattern Plan 4 already used for its own open items: `flutter_webrtc`'s exact enum/constructor shapes (Task 4), the NotoSans static-vs-variable-font file path (Task 10 Step 4), `kShareBaseUrl`/`kDefaultStunServers`'s exact final values (both explicitly still-open protocol questions, see below). Task 3 Step 5's SPDX-line typo (`AGPL-3.0-01-later`) is shown once, deliberately, as a proofreading reminder and immediately corrected in the same step — not a real defect carried into the deliverable, the identical device Plan 4 Task 6 used for the same purpose.

**3. Type consistency:** `RideDmPayload` (Plan 3) gains exactly five new subtypes across this plan (`CallOfferPayload`/`CallAnswerPayload`/`CallIceCandidatePayload`/`CallHangupPayload` in Task 2, `VoiceNotePayload` in Task 6, plus a new optional field on the pre-existing `RideHandoffPayload` in Task 5) — every one additive, none changes an existing case's shape, and the same "no exhaustive switch over `RideDmPayload` exists anywhere" invariant Plan 4 verified before its own addition holds after this plan's five additions too (`CallService._onSignal`'s `switch` explicitly ends in `default: break;`, never an exhaustive match). `IceCandidateData`'s three fields (`candidate`/`sdpMid`/`sdpMLineIndex`) are the single representation used identically by `CallEngine` (Task 4), `CallIceCandidatePayload` (Task 2), and `CallService`'s ICE-forwarding wiring (Task 7) — no second ICE-candidate shape exists anywhere in the plan. `CallFallbackAction`/`decideFallbackAction` (Task 5) is the only fallback-decision logic `CallService._applyFallback` (Task 7) calls — no duplicate decision logic is inlined into the service. `HelperAnnouncement` (Task 1) is the one representation flowing unchanged through `HelperDirectoryService`/`HelperDirectory` (Task 3) into `buildIceServers` (Task 3) and `CallService` (Task 7). `GpsFix`/`GpsTrackAccumulator` (Plan 4) are reused, not reimplemented, by Task 9's `SosButton` (`_track.fixes.last`) exactly as Plan 4 itself reused them between the ride tracker and the taximeter.

## How the fallback chain actually works, restated plainly

There are really only two decision points, not three, despite the spec listing three numbered channels. (1) **Within** a single WebRTC connection attempt, the ICE agent (standard WebRTC behavior, RFC 8445 — not code this project writes) tries every candidate pair STUN and any configured TURN helpers produced, direct-first, automatically. This is spec's "①" and the "туслагч зангилаа" clause of "②" collapsed into one mechanism from the app's point of view — `buildIceServers` (Task 3) is the entire extent of the app's involvement. (2) **Between attempts**, `CallService` (Task 7) starts a timer the moment signaling begins; if the whole WebRTC attempt has neither connected nor definitively failed by the time it fires, `decideFallbackAction` (Task 5) is consulted exactly once, and its answer is binary: keep waiting, or drop external — to a real phone call if one was voluntarily shared (spec's remaining "②"), else straight to a voice note (spec's "③", which always works because it needs no direct connection of any kind). CGNAT specifically shows up as case (1) simply never producing a connectable candidate pair — nothing CGNAT-specific is coded anywhere; it is exactly the scenario (2)'s timeout exists to catch.

## Open questions

1. **`kDefaultStunServers`'s final default list** (Task 3) is a reasonable, widely-mirrored seed, not a verified-against-real-Mongolian-ISP set — spec §16.6 already flagged this as open at plan-writing time ("Нийтийн STUN серверүүдийн default жагсаалт... план бичих үед үнэлнэ"); this plan supplies the list PROTOCOL.md's new §7 (Task 10 Step 7) documents, but real-network validation (Мобиком/Юнител/Скайтел, per spec §13's CGNAT note) is still a PoC-phase field-test item, not something this plan can verify from a repository.
2. **The default "туслагч" (helper/TURN) population is expected to be empty or near-empty at launch** — `HELPER.md` (Task 10 Step 9) is the entire mechanism for growing it, and it depends on volunteers actually running `coturn` and re-announcing. Until that community exists, `buildIceServers`'s helper list is realistically empty for most calls, meaning the fallback chain's step (2) timeout fires purely on STUN-only NAT failures (i.e., CGNAT) more often than the spec's steady-state vision — an accepted, explicitly-flagged bootstrap gap, the same shape as spec §13's own "cold start" risk for the marketplace side of the app.
3. **iOS is entirely unscaffolded in this repository** (`app/ios/` does not exist) — every iOS-specific claim in this plan (Info.plist microphone usage string, CallKit/PushKit tradeoffs) is prospective, describing what would be needed if/when `flutter create --platforms=ios .` is run, not something this plan builds. Stated once here and in Task 7's own "iOS note" rather than left implicit.
4. **`flutter_webrtc`'s exact API surface** (enum member spelling, `RTCIceCandidate`/`createPeerConnection` parameter shapes, Task 4) needs confirmation against whatever version `flutter pub add flutter_webrtc` actually resolves at implementation time — flagged explicitly in Task 4's own "Open item" note, same treatment Plan 4 gave `geolocator`'s `LocationSettings`.
5. **The NotoSans vendoring path** (Task 10 Step 4) needs confirmation against the live `google/fonts` repository, which has moved between static per-weight files and a single variable font for this family before and may do so again.
6. **New dependency count is high across this plan** (`flutter_webrtc`, `url_launcher`, `share_plus`, `record`, `audioplayers`, `flutter_native_splash` — six, on top of Plan 4's own six), each justified by a distinct, named spec capability and each a widely-used, actively-maintained pub.dev package — still worth one `flutter pub outdated` pass before Task 10's release build, matching Plans 3/4's own version-pin caution.
7. **`kShareBaseUrl`/`kTakhiAppDownloadUrl` staying manually in sync** (Task 8 Step 6, `docs/share/index.html`'s hardcoded copy of Plan 4's download-URL constant) is a small, explicitly-flagged duplication rather than a shared source of truth, because the static HTML page cannot import a Dart constant — acceptable for two literals that change rarely (both are already-flagged open protocol questions, §16.4/§16.5), not acceptable if a third or fourth copy of either URL ever appears; watch for that in review.








