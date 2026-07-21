# Тахь — Идэвхтэй аялал, хос баримт, төлбөр, Замын Унаа таксиметр — Implementation Plan (Plan 4/5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pick up exactly where Plan 3 (ride-matching) left off — the moment a passenger has selected a driver and sent the exact-location handoff — and build everything through to a rated, dual-signed trip receipt: live position sharing between the two matched parties, driver-initiated trip-phase signaling, the shared in-trip screen both roles compose into their existing state machines, local-only bank-QR payment display, and a fully offline driver-only taximeter ("Замын Унаа" mode) for street-hail passengers who never touch the app. Calling (P2P WebRTC) and safety/SOS are explicitly Plan 5, not here.

**Architecture:** Two new leaf modules in `packages/takhi_protocol` (`live_location.dart`, `trip_pairing.dart`) extend the pure, UI-free protocol layer exactly like Plan 1/3's existing files. `app/lib/geo/` is a new shared, Flutter-light package-internal module providing a mockable GPS abstraction (`LocationSource`) and pure haversine-distance math, consumed by both the ride flow and the taximeter — written once so neither duplicates the other's distance math (DRY). `app/lib/ride/` gains a second, lighter-weight transport (`LiveLocationChannel`, direct NIP-44 on ephemeral kind 20178) alongside the existing NIP-17 `RideDmChannel`, plus a new discrete-event DM payload (`RideTripStatusPayload`) for driver-initiated phase transitions, and a new shared widget (`ActiveTripView`) that `PassengerRidePage` and `DriverInboxPage` each compose into their own existing step-switch state machines — no new go_router route, no restructuring of either page's already-tested flow. `app/lib/payment/` is new: a local-only file-backed store for the driver's own bank-QR image, never touching the public profile or any relay. `app/lib/meter/` is new: fully offline pure fare math (tariff × distance, and an online-routing/offline-straight-line pre-trip estimate), a local journal, and `TaximeterPage`, the one genuinely new routed screen this plan adds (`/meter`) — reachable only from driver mode, touches no identity and no `RelayPool` at all.

**Tech Stack:** Everything from Plan 1-3 unchanged (`takhi_protocol`, `RelayPool`, Riverpod, ARB i18n, `go_router`, `flutter_map`/`latlong2`). New: `geolocator` (device GPS), `http` (OSRM-compatible routing REST call), `path_provider` (local QR image file), `shared_preferences` (local tariff setting + meter journal), `image_picker` (driver picks their own QR image from gallery), `qr_flutter` (renders the "Тахь тат" onboarding QR). Test: `dart test` for `takhi_protocol`, `flutter test` (unit + widget) for the app — every network-facing class still driven by `FakeRelaySocket`, every GPS-facing class by a new `FakeLocationSource`, mirroring Plan 2/3's established fake-boundary pattern exactly.

## Global Constraints

- **SPDX header** on every new Dart file: `// SPDX-License-Identifier: AGPL-3.0-or-later`.
- **ALL user-facing text via ARB** (`app/lib/l10n/app_mn.arb` is the template/default, `app_en.arb` the translation) — no hardcoded string literals in widgets. New keys are added to both files in the same task that first uses them.
- **Kind constants, reused unchanged from Plan 1:** `kKindLiveLocation = 20178`, `kKindTripReceipt = 30177`. No new relay-published kind is introduced by this plan — live location and trip status both reuse existing kinds/transports (20178 direct, and the existing NIP-17 gift-wrap kind 1059 rumor channel via a new `RideDmPayload` subtype).
- **App never touches money.** No transaction is ever performed by the app. The driver's bank QR is a locally stored *image*, shown on-screen for the other person to scan with their own banking app, or the parties agree cash. The QR image is never attached to the public kind-0 profile and never published to any relay.
- **The taximeter (`app/lib/meter/`) is fully offline by construction.** No file under `app/lib/meter/` may import `RelayPool`, `RideDmChannel`, or anything from `identity/` — a meter session never touches a relay and never mints a Nostr event (spec §7.4 step 4). This is enforced by code review, not tooling, and is called out explicitly in Task 6/8's own doc comments.
- **Хос-баримт (paired-receipt) rule, spec §9/§4.3:** a trip receipt only counts toward reputation when both sides have published one, same `trip_id`, pointing at each other. This plan never weakens or bypasses that — `TripReceiptRepository.publish` (Task 4) only ever writes one side's own receipt; pairing state is a read-only, non-blocking UI signal (`isTripReceiptPaired`), never a gate on completing the flow. The taximeter's local journal entry (Task 6) is explicitly one-sided and never becomes a trip receipt — no counterpart ever signs it, so it must never feed `computeReputation`.
- **GPS is abstracted behind a mockable interface (`app/lib/geo/location_source.dart`).** No widget or service in this plan calls `package:geolocator` directly — everything goes through `LocationSource`, so every distance/fare/tracking behavior is unit-testable with `FakeLocationSource` and never requires a real device or emulator GPS fix to test.
- **Immutability, with one named exception.** All value/model types (`GpsFix`, `LiveLocation`, `TripPhase`, `MeterTripEntry`, `FareEstimate`, ...) are immutable: `final` fields, `const` constructors where possible. `GpsTrackAccumulator`, `MeterSession`, and `RelayPool`-family classes are intentionally small, explicitly-documented *mutable accumulators* over a live stream — the same precedent `RelayPool._sockets`/`_seenEventIds` (Plan 2) already established in this codebase; state transitions elsewhere (widget `setState`, DM payload copies) still always build a fresh value, never mutate one in place.
- **`NostrEvent.tags` stays defensively copied and unmodifiable** (Plan 1's `event.dart`) — nothing in this plan reaches around that.
- **Inherited invariants (unaffected by this plan):** no author-run server, no phone number as identity, no fee/subscription layer, identity = keypair only, AGPL-3.0.

---

### Task 1: Shared GPS abstraction (`app/lib/geo/`)

**Files:**
- Create: `app/lib/geo/gps_fix.dart`
- Create: `app/lib/geo/gps_track.dart`
- Create: `app/lib/geo/location_source.dart`
- Create: `app/lib/geo/geo_providers.dart`
- Modify: `app/pubspec.yaml` (add `geolocator`)
- Modify: `app/android/app/src/main/AndroidManifest.xml` (location permissions)
- Test: `app/test/geo/gps_track_test.dart`
- Test: `app/test/support/fake_location_source.dart` (shared test double, not itself a test file — mirrors `app/test/support/fake_relay_socket.dart`)

**Interfaces:**
- Produces: `class GpsFix { final double lat, lon; final int timestampSeconds; const GpsFix({required lat, required lon, required timestampSeconds}); }`; `double haversineMeters(double lat1, double lon1, double lat2, double lon2)`; `int trackDistanceMeters(List<GpsFix> fixes)`; `int trackDurationSeconds(List<GpsFix> fixes)`; `class GpsTrackAccumulator { void addFix(GpsFix); List<GpsFix> get fixes; int get distanceMeters; int get durationSeconds; }`; `abstract interface class LocationSource { Stream<GpsFix> watch({Duration interval}); }`; `class GeolocatorLocationSource implements LocationSource`; `Future<bool> ensureLocationPermission()`; `final locationSourceProvider = Provider<LocationSource>(...)`; `class FakeLocationSource implements LocationSource { void emit(GpsFix); }` (test support).
- Consumed by: Task 3 (`LiveLocationChannel` callers), Task 6 (`MeterSession` wraps `GpsTrackAccumulator`), Task 7 (`ActiveTripView` wraps `GpsTrackAccumulator` directly for the ride-flow tracker), Task 8 (`TaximeterPage`).

- [ ] **Step 1: Write the failing tests for the pure track math**

`app/test/geo/gps_track_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_track.dart';

void main() {
  test('haversineMeters: one degree of longitude at the equator is ~111.19km', () {
    final d = haversineMeters(0, 0, 0, 1);
    expect(d, closeTo(111194.9, 1.0));
  });

  test('haversineMeters: same point is zero distance', () {
    expect(haversineMeters(47.9186, 106.9176, 47.9186, 106.9176), 0);
  });

  test('trackDistanceMeters sums consecutive-fix distances', () {
    final fixes = [
      const GpsFix(lat: 0, lon: 0, timestampSeconds: 0),
      const GpsFix(lat: 0, lon: 1, timestampSeconds: 60),
      const GpsFix(lat: 0, lon: 2, timestampSeconds: 120),
    ];
    // Two equal ~111,195m legs.
    expect(trackDistanceMeters(fixes), closeTo(222390, 4));
  });

  test('trackDistanceMeters is zero for fewer than 2 fixes', () {
    expect(trackDistanceMeters([]), 0);
    expect(
      trackDistanceMeters([const GpsFix(lat: 0, lon: 0, timestampSeconds: 0)]),
      0,
    );
  });

  test('trackDurationSeconds is last minus first timestamp', () {
    final fixes = [
      const GpsFix(lat: 0, lon: 0, timestampSeconds: 100),
      const GpsFix(lat: 0, lon: 0, timestampSeconds: 250),
    ];
    expect(trackDurationSeconds(fixes), 150);
  });

  test('trackDurationSeconds is zero for fewer than 2 fixes', () {
    expect(trackDurationSeconds([]), 0);
  });

  test('GpsTrackAccumulator exposes a growing, unmodifiable fix list', () {
    final acc = GpsTrackAccumulator();
    acc.addFix(const GpsFix(lat: 0, lon: 0, timestampSeconds: 0));
    acc.addFix(const GpsFix(lat: 0, lon: 1, timestampSeconds: 60));
    expect(acc.fixes.length, 2);
    expect(() => acc.fixes.add(const GpsFix(lat: 0, lon: 0, timestampSeconds: 0)),
        throwsUnsupportedError);
    expect(acc.distanceMeters, closeTo(111195, 2));
    expect(acc.durationSeconds, 60);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run (from `app/`): `flutter test test/geo/gps_track_test.dart`
Expected: FAIL — `package:takhi/geo/gps_fix.dart` and `gps_track.dart` don't exist yet.

- [ ] **Step 3: Implement `gps_fix.dart` and `gps_track.dart`**

`app/lib/geo/gps_fix.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// A single GPS reading: coordinates plus the device clock time it was
/// captured, in unix seconds (matching `NostrEvent.createdAt`'s unit, so a
/// fix's timestamp compares directly against event timestamps elsewhere).
class GpsFix {
  final double lat;
  final double lon;
  final int timestampSeconds;
  const GpsFix({
    required this.lat,
    required this.lon,
    required this.timestampSeconds,
  });
}
```

`app/lib/geo/gps_track.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'gps_fix.dart';

const double _earthRadiusMeters = 6371000;

/// Great-circle distance between two points, in meters (haversine). Pure
/// math, no Flutter/location dependency — the shared building block behind
/// both the active-trip tracker (Task 7) and the taximeter (Task 6).
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * c;
}

double _radians(double degrees) => degrees * math.pi / 180.0;

/// Total path length across consecutive [fixes], rounded to whole meters.
/// Fewer than 2 fixes has no distance yet.
int trackDistanceMeters(List<GpsFix> fixes) {
  if (fixes.length < 2) return 0;
  var total = 0.0;
  for (var i = 1; i < fixes.length; i++) {
    total += haversineMeters(
      fixes[i - 1].lat,
      fixes[i - 1].lon,
      fixes[i].lat,
      fixes[i].lon,
    );
  }
  return total.round();
}

/// Elapsed time between the first and last [fixes], in seconds. Fewer than
/// 2 fixes has no duration yet.
int trackDurationSeconds(List<GpsFix> fixes) {
  if (fixes.length < 2) return 0;
  return fixes.last.timestampSeconds - fixes.first.timestampSeconds;
}

/// Mutable accumulator over a live sequence of [GpsFix]es — the shared
/// engine behind the active-trip distance tracker (`ride/`, Task 7) and
/// the taximeter (`meter/`, Task 6, via `MeterSession`), so the haversine-
/// sum logic lives in exactly one place (DRY). Intentionally mutable — see
/// Global Constraints' immutability note.
class GpsTrackAccumulator {
  final List<GpsFix> _fixes = [];

  void addFix(GpsFix fix) => _fixes.add(fix);

  List<GpsFix> get fixes => List.unmodifiable(_fixes);
  int get distanceMeters => trackDistanceMeters(_fixes);
  int get durationSeconds => trackDurationSeconds(_fixes);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/geo/gps_track_test.dart` — Expected: PASS.

- [ ] **Step 5: Add `geolocator`, the real/fake `LocationSource`, and the permission helper**

In `app/pubspec.yaml`, under `dependencies:`:

```yaml
  geolocator: ^13.0.2
```

Run (from `app/`): `flutter pub get`

`app/lib/geo/location_source.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:geolocator/geolocator.dart';

import 'gps_fix.dart';

/// Abstracts the device GPS behind a plain [Stream] so every consumer
/// (Task 3's live-location channel, Task 7's active-trip tracker, Task 8's
/// taximeter) is testable with a fake stream instead of a real device —
/// per the plan's Global Constraints, nothing outside this file talks to
/// `package:geolocator` directly.
abstract interface class LocationSource {
  /// Emits a new [GpsFix] as the device moves. [interval] documents the
  /// intended cadence (spec §6: every 5-10s) but is only a *hint* here —
  /// `package:geolocator`'s base `LocationSettings` has no direct interval
  /// knob; the platform-specific subclasses (`AndroidSettings.intervalDuration`,
  /// `AppleSettings`) can honor it once the resolved `geolocator` version's
  /// exact constructor is confirmed (see Self-Review open questions).
  Stream<GpsFix> watch({Duration interval = const Duration(seconds: 5)});
}

/// Real device GPS via `package:geolocator`. Requires
/// `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (AndroidManifest.xml,
/// Step 6 below) and a granted runtime permission — [watch] does not
/// request permission itself; callers must call [ensureLocationPermission]
/// first (Task 7/8 UI) before constructing/using this class.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Stream<GpsFix> watch({Duration interval = const Duration(seconds: 5)}) {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).map(
      (position) => GpsFix(
        lat: position.latitude,
        lon: position.longitude,
        timestampSeconds: position.timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }
}

/// Requests location permission if not already granted, returning whether
/// GPS is now usable. Every UI that starts a [GeolocatorLocationSource]
/// subscription (Task 7/8) must check this first and show a clear "location
/// needed" state instead if it returns `false`, rather than letting
/// `Geolocator.getPositionStream` throw.
Future<bool> ensureLocationPermission() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}
```

`app/lib/geo/geo_providers.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_source.dart';

/// The app-wide [LocationSource]. Overridden with a `FakeLocationSource` in
/// every widget test that needs GPS (Task 7/8) — mirrors
/// `relayPoolProvider`'s override pattern exactly.
final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);
```

`app/test/support/fake_location_source.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/location_source.dart';

/// Deterministic [LocationSource] test double — feeds pre-scripted fixes
/// via [emit] instead of a real GPS radio, mirroring [FakeRelaySocket]'s
/// role for [RelayPool]. `GeolocatorLocationSource` itself is intentionally
/// left without a dedicated unit test, for the same reason
/// `WsRelaySocket` (`nostr/relay_pool.dart`) has none: it is a thin,
/// untestable-without-a-real-device wrapper around a platform plugin —
/// everything built on top of the [LocationSource] interface is fully
/// covered through this fake instead.
class FakeLocationSource implements LocationSource {
  final _controller = StreamController<GpsFix>.broadcast();

  @override
  Stream<GpsFix> watch({Duration interval = const Duration(seconds: 5)}) =>
      _controller.stream;

  void emit(GpsFix fix) => _controller.add(fix);

  Future<void> dispose() => _controller.close();
}
```

- [ ] **Step 6: Add Android location permissions**

In `app/android/app/src/main/AndroidManifest.xml`, add before the `<application>` tag:

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

Foreground-only — no background-location permission is requested, matching this plan's MVP scope (GPS only while a trip/meter screen is open, never in the background).

- [ ] **Step 7: Run the full test file again and commit**

Run: `flutter test test/geo/gps_track_test.dart` — Expected: PASS.

```bash
git add app/lib/geo app/test/geo app/test/support/fake_location_source.dart app/pubspec.yaml app/pubspec.lock app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(app): shared GPS abstraction and haversine track math"
```

---

### Task 2: Live-location protocol event (kind 20178, `takhi_protocol`)

**Files:**
- Create: `packages/takhi_protocol/lib/src/live_location.dart`
- Modify: `packages/takhi_protocol/lib/takhi_protocol.dart` (export)
- Test: `packages/takhi_protocol/test/live_location_test.dart`

**Interfaces:**
- Consumes: `NostrEvent`, `kKindLiveLocation` (`takhi_events.dart`), `pubkeyFromPrivate` (`keys.dart`), `nip44Encrypt`/`nip44Decrypt` (`nip44.dart`), `signEvent` (`sign.dart`).
- Produces: `NostrEvent buildLiveLocationEvent({required String senderPrivHex, required String recipientPubHex, required int now, required String tripId, required double lat, required double lon, int expirySeconds = 30, List<int>? nonce32, List<int>? auxRand})`; `class LiveLocation { final String senderPubkey, tripId; final double lat, lon; const LiveLocation({...}); }`; `LiveLocation parseLiveLocationEvent(NostrEvent e, String recipientPrivHex)` (throws `FormatException` for wrong kind or malformed decrypted payload; propagates `nip44Decrypt`'s `Exception` when undecryptable with this key).
- Consumed by: Task 3's `LiveLocationChannel`.

- [ ] **Step 1: Write the failing tests**

`packages/takhi_protocol/test/live_location_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  final sender = generateKeyPair(List<int>.filled(32, 71));
  final recipient = generateKeyPair(List<int>.filled(32, 72));

  test('buildLiveLocationEvent has kind 20178, a p tag, a d tag, and an '
      'expiration tag', () {
    final e = buildLiveLocationEvent(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      now: 1000,
      tripId: 'trip-1',
      lat: 47.9186,
      lon: 106.9176,
    );
    expect(e.kind, kKindLiveLocation);
    expect(e.pubkey, sender.publicHex);
    expect(e.tags.firstWhere((t) => t.first == 'p')[1], recipient.publicHex);
    expect(e.tags.firstWhere((t) => t.first == 'd')[1], 'trip-1');
    expect(e.tags.firstWhere((t) => t.first == 'expiration')[1], '1030');
    // The plaintext content must not contain the raw coordinates.
    expect(e.content.contains('47.9186'), isFalse);
  });

  test('buildLiveLocationEvent produces a validly signed event', () {
    final e = buildLiveLocationEvent(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      now: 1000,
      tripId: 'trip-1',
      lat: 47.9186,
      lon: 106.9176,
      auxRand: List<int>.filled(32, 0),
    );
    expect(verifyEvent(e), isTrue);
  });

  test('parseLiveLocationEvent round-trips lat/lon/tripId', () {
    final e = buildLiveLocationEvent(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      now: 1000,
      tripId: 'trip-1',
      lat: 47.9186,
      lon: 106.9176,
    );
    final parsed = parseLiveLocationEvent(e, recipient.privateHex);
    expect(parsed.senderPubkey, sender.publicHex);
    expect(parsed.tripId, 'trip-1');
    expect(parsed.lat, 47.9186);
    expect(parsed.lon, 106.9176);
  });

  test('parseLiveLocationEvent rejects the wrong kind', () {
    final wrong = NostrEvent(
      pubkey: sender.publicHex,
      createdAt: 1000,
      kind: 1,
      tags: const [],
      content: 'x',
    );
    expect(() => parseLiveLocationEvent(wrong, recipient.privateHex),
        throwsFormatException);
  });

  test('parseLiveLocationEvent throws when decrypted with the wrong key',
      () {
    final stranger = generateKeyPair(List<int>.filled(32, 73));
    final e = buildLiveLocationEvent(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      now: 1000,
      tripId: 'trip-1',
      lat: 47.9186,
      lon: 106.9176,
    );
    expect(() => parseLiveLocationEvent(e, stranger.privateHex),
        throwsA(isA<Exception>()));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run (from `packages/takhi_protocol/`): `dart test test/live_location_test.dart`
Expected: FAIL — `buildLiveLocationEvent`/`parseLiveLocationEvent` undefined.

- [ ] **Step 3: Implement `live_location.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'event.dart';
import 'keys.dart';
import 'nip44.dart';
import 'sign.dart';
import 'takhi_events.dart' show kKindLiveLocation;

/// Builds a signed, NIP-44-encrypted live-location ping (kind 20178, spec
/// §6/§7.1 step 5): a lightweight position heartbeat sent every 5-10s while
/// a trip is in progress, addressed to exactly one recipient via the
/// public `p` tag.
///
/// Deliberately NOT wrapped through NIP-17/NIP-59 (`nip17Wrap`) like
/// offer/handoff/cancel DMs — those exist to hide the sender's identity and
/// randomize timing for messages exchanged before two strangers have
/// committed to a trip. By the time live location starts, both pubkeys are
/// already mutually known (the passenger picked this driver from a
/// reputation-visible offer, spec §7.1 step 3), so gift-wrap's per-message
/// ephemeral-key signing cost buys no privacy here, only battery. A plain
/// NIP-44-encrypted ephemeral event (the `2xxxx` kind range: relays don't
/// persist it, only relay it to currently-connected subscribers) is the
/// lighter-weight fit spec §6's data-model table calls for.
///
/// Only [lat]/[lon]/[tripId] are encrypted into `content`; the `p`/`d`/
/// `expiration` tags are plaintext relay-routing metadata, same tiering as
/// every other takhi event.
NostrEvent buildLiveLocationEvent({
  required String senderPrivHex,
  required String recipientPubHex,
  required int now,
  required String tripId,
  required double lat,
  required double lon,
  int expirySeconds = 30,
  List<int>? nonce32,
  List<int>? auxRand,
}) {
  final payload = jsonEncode({'tripId': tripId, 'lat': lat, 'lon': lon});
  final encrypted = nip44Encrypt(
    payload,
    senderPrivHex,
    recipientPubHex,
    nonce32: nonce32,
  );
  final unsigned = NostrEvent(
    pubkey: pubkeyFromPrivate(senderPrivHex),
    createdAt: now,
    kind: kKindLiveLocation,
    tags: [
      ['p', recipientPubHex],
      ['d', tripId],
      ['expiration', (now + expirySeconds).toString()],
    ],
    content: encrypted,
  );
  return signEvent(unsigned, senderPrivHex, auxRand: auxRand);
}

/// A live-location ping recovered from [parseLiveLocationEvent]: the
/// sender's pubkey (read straight off the signed event — no seal/unwrap
/// layer needed, unlike a NIP-17 DM) plus the decrypted position.
class LiveLocation {
  final String senderPubkey;
  final String tripId;
  final double lat;
  final double lon;
  const LiveLocation({
    required this.senderPubkey,
    required this.tripId,
    required this.lat,
    required this.lon,
  });
}

/// Reverses [buildLiveLocationEvent]: checks [e]'s kind, decrypts `content`
/// with [recipientPrivHex], and parses the `{tripId, lat, lon}` payload.
///
/// Throws [FormatException] for the wrong kind or a malformed decrypted
/// payload. Throws the underlying [Exception] (from [nip44Decrypt]) if [e]
/// cannot be decrypted with [recipientPrivHex] at all — e.g. it was
/// addressed to someone else. Does not itself call [verifyEvent] — every
/// event reaching application code through `RelayPool.subscribe` (Task 3)
/// is already signature-verified there, matching `parseRideRequest`/
/// `parseTripReceipt`'s existing convention of not re-checking it.
LiveLocation parseLiveLocationEvent(NostrEvent e, String recipientPrivHex) {
  if (e.kind != kKindLiveLocation) {
    throw FormatException('not a live location event (kind ${e.kind})');
  }
  final decrypted = nip44Decrypt(e.content, recipientPrivHex, e.pubkey);
  final decoded = jsonDecode(decrypted);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('live location payload is not a JSON object');
  }
  final tripId = decoded['tripId'];
  final lat = decoded['lat'];
  final lon = decoded['lon'];
  if (tripId is! String) {
    throw FormatException("live location payload: 'tripId' must be a String");
  }
  if (lat is! num) {
    throw FormatException("live location payload: 'lat' must be a number");
  }
  if (lon is! num) {
    throw FormatException("live location payload: 'lon' must be a number");
  }
  return LiveLocation(
    senderPubkey: e.pubkey,
    tripId: tripId,
    lat: lat.toDouble(),
    lon: lon.toDouble(),
  );
}
```

Add to `packages/takhi_protocol/lib/takhi_protocol.dart`:

```dart
export 'src/live_location.dart';
```

- [ ] **Step 4: Run to verify it passes**

Run: `dart test test/live_location_test.dart` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/takhi_protocol/lib/src/live_location.dart packages/takhi_protocol/lib/takhi_protocol.dart packages/takhi_protocol/test/live_location_test.dart
git commit -m "feat(protocol): live-location event (kind 20178, direct NIP-44)"
```

---

### Task 3: Trip phase + trip-status DM + live-location channel (`app/lib/ride/`)

**Files:**
- Create: `app/lib/ride/trip_phase.dart`
- Modify: `app/lib/ride/ride_dm_payload.dart` (add `RideTripStatusPayload`)
- Create: `app/lib/ride/trip_status_service.dart`
- Create: `app/lib/ride/live_location_channel.dart`
- Modify: `app/lib/ride/ride_providers.dart` (add two providers)
- Modify: `app/test/ride/ride_dm_payload_test.dart` (round-trip cases for the new payload)
- Test: `app/test/ride/trip_status_service_test.dart`
- Test: `app/test/ride/live_location_channel_test.dart`

**Interfaces:**
- Consumes: `RideDmChannel` (Plan 3, unchanged), `RelayPool`/`RelayFilter` (Plan 2), `buildLiveLocationEvent`/`parseLiveLocationEvent`/`kKindLiveLocation` (Task 2).
- Produces: `enum TripPhase { enRouteToPickup, tripInProgress, arrived }`; `final class RideTripStatusPayload extends RideDmPayload { final String tripId; final TripPhase phase; const RideTripStatusPayload({required tripId, required phase}); }`; `class ReceivedTripStatus { final String senderPubkey, tripId; final TripPhase phase; const ReceivedTripStatus(...); }`; `class TripStatusService { Future<void> sendStatus({required driverPrivHex, required passengerPubHex, required tripId, required phase, required now}); Stream<ReceivedTripStatus> watchStatus(String myPubHex, String myPrivHex); }`; `class LiveLocationChannel { Future<void> send({required senderPrivHex, required recipientPubHex, required tripId, required lat, required lon, required now}); Stream<LiveLocation> watch(String myPubHex, String myPrivHex, String tripId); }`; `liveLocationChannelProvider`, `tripStatusServiceProvider`.
- Consumed by: Task 7's `ActiveTripView`.

- [ ] **Step 1: Add `TripPhase`**

`app/lib/ride/trip_phase.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The driver-observed stage of an in-progress trip (spec §7.1 step 5:
/// "жолооч ирж байгаа→суусан→замд→хүрсэн"). Every transition is a driver
/// action (spec step 6: "Жолооч «Аялал дууслаа» дарна") — the passenger's
/// UI (Task 7) only ever displays whatever phase arrives via
/// [RideTripStatusPayload], it never sets one itself.
///
/// The spec's four Mongolian labels collapse to three enum values: "суусан"
/// (passenger boarded) and "замд" (en route to destination) merge into
/// [tripInProgress]. There is no driver action that distinguishes them —
/// the moment the driver marks the passenger boarded, the trip IS en
/// route; splitting them would add a state with no transition of its own
/// (YAGNI), and both share one display treatment (live map, "аяллын
/// явцад") regardless.
enum TripPhase {
  /// Initial phase, entered automatically the moment the active-trip view
  /// opens after handoff — the driver is navigating to the passenger's
  /// exact pickup point.
  enRouteToPickup,

  /// The passenger has boarded (driver tapped "Зорчигч сууллаа") and the
  /// trip is now underway toward the destination.
  tripInProgress,

  /// The driver tapped "Аялал дууслаа" — distance/duration tracking stops
  /// on both sides and both move to the rating + receipt step.
  arrived,
}
```

- [ ] **Step 2: Write the failing round-trip test for the new DM payload**

Append to `app/test/ride/ride_dm_payload_test.dart` (new `import 'package:takhi/ride/trip_phase.dart';` at the top):

```dart
  test('trip_status payload round-trips through encode/decode', () {
    const status = RideTripStatusPayload(
      tripId: 'trip-abc',
      phase: TripPhase.tripInProgress,
    );
    final decoded =
        RideDmPayload.decode(status.encode()) as RideTripStatusPayload;
    expect(decoded.tripId, 'trip-abc');
    expect(decoded.phase, TripPhase.tripInProgress);
  });

  test('trip_status decode throws FormatException for an unknown phase '
      'string', () {
    expect(
      () => RideDmPayload.decode(
        jsonEncode({
          'type': 'trip_status',
          'tripId': 'trip-abc',
          'phase': 'flying',
        }),
      ),
      throwsFormatException,
    );
  });
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/ride/ride_dm_payload_test.dart` — Expected: FAIL — `RideTripStatusPayload` undefined.

- [ ] **Step 4: Add `RideTripStatusPayload` to `ride_dm_payload.dart`**

Add the import at the top of `app/lib/ride/ride_dm_payload.dart`:

```dart
import 'trip_phase.dart';
```

Extend the `decode` switch:

```dart
    return switch (map['type']) {
      'offer' => RideOfferPayload._fromJson(map),
      'handoff' => RideHandoffPayload._fromJson(map),
      'cancel' => RideCancelPayload._fromJson(map),
      'trip_status' => RideTripStatusPayload._fromJson(map),
      final other => throw FormatException(
        'unknown ride DM payload type: $other',
      ),
    };
```

Append a new subtype at the end of the file:

```dart
/// A driver-initiated trip-phase transition (spec §7.1 steps 5-6). Rides
/// the same reliable NIP-17 gift-wrap transport as offer/handoff/cancel —
/// unlike position pings (`LiveLocationChannel`, ephemeral kind 20178), a
/// phase change is discrete, low-frequency, and must not be missed (in
/// particular `TripPhase.arrived`, which is what tells the passenger's
/// side to move into the rating step), so it does not ride the lighter,
/// best-effort location channel.
final class RideTripStatusPayload extends RideDmPayload {
  final String tripId;
  final TripPhase phase;

  const RideTripStatusPayload({required this.tripId, required this.phase});

  factory RideTripStatusPayload._fromJson(Map<String, dynamic> map) {
    final tripId = _requiredString(map, 'tripId');
    final phaseName = _requiredString(map, 'phase');
    final phase = TripPhase.values.firstWhere(
      (p) => p.name == phaseName,
      orElse: () =>
          throw FormatException('unknown trip phase: $phaseName'),
    );
    return RideTripStatusPayload(tripId: tripId, phase: phase);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'trip_status',
    'tripId': tripId,
    'phase': phase.name,
  };
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/ride/ride_dm_payload_test.dart` — Expected: PASS.

- [ ] **Step 6: Write the failing tests for `TripStatusService` and `LiveLocationChannel`**

`app/test/ride/trip_status_service_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi/ride/trip_status_service.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final driver = generateKeyPair(List<int>.filled(32, 101));
  final passenger = generateKeyPair(List<int>.filled(32, 102));

  test('sendStatus delivers a phase transition to the passenger', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = TripStatusService(RideDmChannel(pool));

    final got = <ReceivedTripStatus>[];
    final sub = service
        .watchStatus(passenger.publicHex, passenger.privateHex)
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await service.sendStatus(
      driverPrivHex: driver.privateHex,
      passengerPubHex: passenger.publicHex,
      tripId: 'trip-1',
      phase: TripPhase.arrived,
      now: 1000,
    );
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, driver.publicHex);
    expect(got.first.tripId, 'trip-1');
    expect(got.first.phase, TripPhase.arrived);
    await sub.cancel();
  });
}
```

`app/test/ride/live_location_channel_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/live_location_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final driver = generateKeyPair(List<int>.filled(32, 103));
  final passenger = generateKeyPair(List<int>.filled(32, 104));

  test('send + watch delivers a position ping scoped to one trip', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = LiveLocationChannel(pool);

    final got = <LiveLocation>[];
    final sub = channel
        .watch(passenger.publicHex, passenger.privateHex, 'trip-1')
        .listen(got.add);
    final subId =
        (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
            as String;

    await channel.send(
      senderPrivHex: driver.privateHex,
      recipientPubHex: passenger.publicHex,
      tripId: 'trip-1',
      lat: 47.92,
      lon: 106.91,
      now: 1000,
    );
    final publishedFrame =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(got.length, 1);
    expect(got.first.senderPubkey, driver.publicHex);
    expect(got.first.tripId, 'trip-1');
    expect(got.first.lat, 47.92);
    expect(got.first.lon, 106.91);
    await sub.cancel();
  });

  test('watch filters by both #p and #d tags', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final channel = LiveLocationChannel(pool);

    channel.watch(passenger.publicHex, passenger.privateHex, 'trip-1');
    final reqFrame =
        jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>;
    final filter = reqFrame[2] as Map<String, dynamic>;
    expect(filter['kinds'], [kKindLiveLocation]);
    expect(filter['#p'], [passenger.publicHex]);
    expect(filter['#d'], ['trip-1']);
  });
}
```

- [ ] **Step 7: Run to verify both fail**

Run: `flutter test test/ride/trip_status_service_test.dart test/ride/live_location_channel_test.dart`
Expected: FAIL — neither class exists yet.

- [ ] **Step 8: Implement `TripStatusService` and `LiveLocationChannel`**

`app/lib/ride/trip_status_service.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'ride_dm_channel.dart';
import 'ride_dm_payload.dart';
import 'trip_phase.dart';

/// A trip-phase transition as the receiving side sees it.
class ReceivedTripStatus {
  final String senderPubkey;
  final String tripId;
  final TripPhase phase;
  const ReceivedTripStatus(this.senderPubkey, this.tripId, this.phase);
}

/// Sends/receives driver-initiated trip-phase transitions (spec §7.1 steps
/// 5-6) over the existing reliable NIP-17 [RideDmChannel] — see
/// [RideTripStatusPayload]'s doc comment for why this rides the DM
/// transport rather than the lighter-weight [LiveLocationChannel].
class TripStatusService {
  final RideDmChannel _dm;
  TripStatusService(this._dm);

  Future<void> sendStatus({
    required String driverPrivHex,
    required String passengerPubHex,
    required String tripId,
    required TripPhase phase,
    required int now,
  }) async {
    await _dm.send(
      senderPrivHex: driverPrivHex,
      recipientPubHex: passengerPubHex,
      payload: RideTripStatusPayload(tripId: tripId, phase: phase),
      now: now,
    );
  }

  Stream<ReceivedTripStatus> watchStatus(String myPubHex, String myPrivHex) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is RideTripStatusPayload)
        .map((dm) {
      final payload = dm.payload as RideTripStatusPayload;
      return ReceivedTripStatus(
        dm.senderPubkey,
        payload.tripId,
        payload.phase,
      );
    });
  }
}
```

`app/lib/ride/live_location_channel.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';

/// Publishes and subscribes to kind-20178 live-location pings (spec §6/
/// §7.1 step 5) over a [RelayPool] — the position-heartbeat sibling of
/// [RideDmChannel], deliberately NOT built on it: live location skips the
/// NIP-17 gift-wrap layer entirely (see `buildLiveLocationEvent`'s doc
/// comment) and calls `pool.publish`/`pool.subscribe` directly with a
/// plain NIP-44-encrypted kind-20178 event.
class LiveLocationChannel {
  final RelayPool _pool;
  LiveLocationChannel(this._pool);

  Future<void> send({
    required String senderPrivHex,
    required String recipientPubHex,
    required String tripId,
    required double lat,
    required double lon,
    required int now,
  }) async {
    final event = buildLiveLocationEvent(
      senderPrivHex: senderPrivHex,
      recipientPubHex: recipientPubHex,
      now: now,
      tripId: tripId,
      lat: lat,
      lon: lon,
    );
    await _pool.publish(event);
  }

  /// Every live-location ping addressed to [myPubHex] for [tripId] —
  /// scoped to one trip so a device with more than one concurrent trip
  /// (not expected in this MVP, but not structurally prevented either)
  /// never mixes their position streams.
  Stream<LiveLocation> watch(
    String myPubHex,
    String myPrivHex,
    String tripId,
  ) {
    final filter = RelayFilter(
      kinds: [kKindLiveLocation],
      tagFilters: {
        '#p': [myPubHex],
        '#d': [tripId],
      },
    );
    return _pool.subscribe(filter).asyncExpand((event) async* {
      try {
        yield parseLiveLocationEvent(event, myPrivHex);
      } on Exception {
        // Not decryptable with our key, or malformed; drop rather than
        // surfacing it as an error — same policy as `RideDmChannel.inbox`.
      }
    });
  }
}
```

- [ ] **Step 9: Wire providers**

Add to `app/lib/ride/ride_providers.dart`:

```dart
import '../nostr/relay_pool_provider.dart';
import 'live_location_channel.dart';
import 'trip_status_service.dart';

final liveLocationChannelProvider = Provider<LiveLocationChannel>(
  (ref) => LiveLocationChannel(ref.watch(relayPoolProvider)),
);

final tripStatusServiceProvider = Provider<TripStatusService>(
  (ref) => TripStatusService(ref.watch(rideDmChannelProvider)),
);
```

(`relayPoolProvider` is already imported transitively in most call sites but add the explicit import above if the file doesn't already have it — check before duplicating.)

- [ ] **Step 10: Run everything and commit**

Run: `flutter test test/ride/ride_dm_payload_test.dart test/ride/trip_status_service_test.dart test/ride/live_location_channel_test.dart` — Expected: PASS.

```bash
git add app/lib/ride/trip_phase.dart app/lib/ride/ride_dm_payload.dart app/lib/ride/trip_status_service.dart app/lib/ride/live_location_channel.dart app/lib/ride/ride_providers.dart app/test/ride/ride_dm_payload_test.dart app/test/ride/trip_status_service_test.dart app/test/ride/live_location_channel_test.dart
git commit -m "feat(app): trip-phase DM signaling and live-location channel"
```

---

### Task 4: Trip receipt pairing + publish

**Files:**
- Create: `packages/takhi_protocol/lib/src/trip_pairing.dart`
- Modify: `packages/takhi_protocol/lib/takhi_protocol.dart` (export)
- Modify: `app/lib/ride/trip_receipt_repository.dart` (add `publish`)
- Test: `packages/takhi_protocol/test/trip_pairing_test.dart`
- Test: `app/test/ride/trip_receipt_repository_test.dart` (extend)

**Interfaces:**
- Consumes: `TripReceipt`, `buildTripReceipt`, `pubkeyFromPrivate`, `signEvent` (all Plan 1), `RelayPool.publish` (Plan 2).
- Produces: `bool isTripReceiptPaired({required TripReceipt mine, required List<TripReceipt> candidates})`; `TripReceiptRepository.publish({required String privHex, required int now, required String tripId, required String counterpartyPubkey, required String role, required int ratingStars, required int distanceMeters, required int durationSeconds, required int priceMnt, String comment = ''}) -> Future<NostrEvent>`.
- Consumed by: Task 7's `ActiveTripView`.

- [ ] **Step 1: Write the failing pairing tests**

`packages/takhi_protocol/test/trip_pairing_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

TripReceipt _receipt({
  required String tripId,
  required String author,
  required String counterparty,
}) =>
    TripReceipt(
      tripId: tripId,
      counterpartyPubkey: counterparty,
      role: 'passenger',
      ratingStars: 5,
      distanceMeters: 1000,
      durationSeconds: 300,
      priceMnt: 5000,
      comment: '',
      authorPubkey: author,
      createdAt: 1,
    );

void main() {
  test('isTripReceiptPaired is true when the reciprocal receipt is '
      'present', () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    final theirs = _receipt(tripId: 't1', author: 'B', counterparty: 'A');
    expect(isTripReceiptPaired(mine: mine, candidates: [theirs]), isTrue);
  });

  test('isTripReceiptPaired is false when trip ids differ', () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    final theirs = _receipt(tripId: 't2', author: 'B', counterparty: 'A');
    expect(isTripReceiptPaired(mine: mine, candidates: [theirs]), isFalse);
  });

  test('isTripReceiptPaired is false when the candidate points at someone '
      'else', () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    final unrelated = _receipt(tripId: 't1', author: 'B', counterparty: 'C');
    expect(isTripReceiptPaired(mine: mine, candidates: [unrelated]), isFalse);
  });

  test('isTripReceiptPaired is false for an empty candidate list', () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    expect(isTripReceiptPaired(mine: mine, candidates: []), isFalse);
  });

  test('isTripReceiptPaired finds the match among unrelated candidates',
      () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    final theirs = _receipt(tripId: 't1', author: 'B', counterparty: 'A');
    final noise = _receipt(tripId: 't9', author: 'X', counterparty: 'Y');
    expect(
      isTripReceiptPaired(mine: mine, candidates: [noise, theirs]),
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run (from `packages/takhi_protocol/`): `dart test test/trip_pairing_test.dart` — Expected: FAIL.

- [ ] **Step 3: Implement `trip_pairing.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'takhi_events.dart';

/// Whether [mine] — a receipt this device already published — has its
/// reciprocal counterpart in [candidates]: the other side's own kind-30177
/// receipt for the same trip, pointing back (spec §9 "хос гарын үсэгтэй
/// баримт" / §4.3 "Хос баримтын дүрэм").
///
/// This is a single-trip UI-facing check ("has my counterparty signed
/// yet?"), distinct from `computeReputation`'s internal `hasCounter`,
/// which answers the aggregate "how much does this pubkey's whole history
/// weigh" question across every trip at once. Both walk the same
/// three-field match (`tripId` + swapped author/counterparty); kept as two
/// small functions rather than one shared helper because they serve
/// different callers with different return shapes (bool vs. a weighted
/// score) and unifying them would only add an indirection neither call
/// site needs.
bool isTripReceiptPaired({
  required TripReceipt mine,
  required List<TripReceipt> candidates,
}) {
  return candidates.any((other) =>
      other.tripId == mine.tripId &&
      other.authorPubkey == mine.counterpartyPubkey &&
      other.counterpartyPubkey == mine.authorPubkey);
}
```

Add to `packages/takhi_protocol/lib/takhi_protocol.dart`:

```dart
export 'src/trip_pairing.dart';
```

- [ ] **Step 4: Run to verify it passes**

Run: `dart test test/trip_pairing_test.dart` — Expected: PASS.

- [ ] **Step 5: Write the failing test for `TripReceiptRepository.publish`**

Append to `app/test/ride/trip_receipt_repository_test.dart`:

```dart
  test('publish builds, signs, and publishes this device\'s own trip '
      'receipt', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final repo = TripReceiptRepository(pool);

    final kp = generateKeyPair(List<int>.filled(32, 86));
    final signed = await repo.publish(
      privHex: kp.privateHex,
      now: 1000,
      tripId: 'trip-9',
      counterpartyPubkey: 'D9',
      role: 'passenger',
      ratingStars: 5,
      distanceMeters: 3000,
      durationSeconds: 600,
      priceMnt: 7000,
      comment: 'сайн жолооч',
    );

    expect(signed.kind, kKindTripReceipt);
    expect(signed.pubkey, kp.publicHex);
    final published =
        jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
    expect(published[0], 'EVENT');
    expect((published[1] as Map<String, dynamic>)['id'], signed.id);
    final parsed = parseTripReceipt(signed);
    expect(parsed.tripId, 'trip-9');
    expect(parsed.counterpartyPubkey, 'D9');
    expect(parsed.ratingStars, 5);
    expect(parsed.distanceMeters, 3000);
    expect(parsed.priceMnt, 7000);
  });
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/ride/trip_receipt_repository_test.dart` — Expected: FAIL — `publish` undefined.

- [ ] **Step 7: Add `publish` to `TripReceiptRepository`**

Append inside the `TripReceiptRepository` class in `app/lib/ride/trip_receipt_repository.dart`:

```dart
  /// Builds, signs, and publishes this device's own trip receipt (spec
  /// §7.1 step 6 / §9): one call per side, both on the same [tripId], each
  /// naming the other as [counterpartyPubkey]. Pairing (whether the other
  /// side has published theirs yet) is a separate read via
  /// [receiptsAbout] + `isTripReceiptPaired` — this method only ever
  /// writes.
  Future<NostrEvent> publish({
    required String privHex,
    required int now,
    required String tripId,
    required String counterpartyPubkey,
    required String role,
    required int ratingStars,
    required int distanceMeters,
    required int durationSeconds,
    required int priceMnt,
    String comment = '',
  }) async {
    final pubHex = pubkeyFromPrivate(privHex);
    final unsigned = buildTripReceipt(
      pubkey: pubHex,
      now: now,
      tripId: tripId,
      counterpartyPubkey: counterpartyPubkey,
      role: role,
      ratingStars: ratingStars,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      priceMnt: priceMnt,
      comment: comment,
    );
    final signed = signEvent(unsigned, privHex);
    await _pool.publish(signed);
    return signed;
  }
```

- [ ] **Step 8: Run everything and commit**

Run: `flutter test test/ride/trip_receipt_repository_test.dart` — Expected: PASS.

```bash
git add packages/takhi_protocol/lib/src/trip_pairing.dart packages/takhi_protocol/lib/takhi_protocol.dart packages/takhi_protocol/test/trip_pairing_test.dart app/lib/ride/trip_receipt_repository.dart app/test/ride/trip_receipt_repository_test.dart
git commit -m "feat: trip-receipt pairing check and repository publish"
```

---

### Task 5: Payment module — local-only driver QR (`app/lib/payment/`)

**Files:**
- Create: `app/lib/payment/driver_qr_store.dart`
- Create: `app/lib/payment/payment_providers.dart`
- Create: `app/lib/payment/driver_qr_capture_page.dart` (spec + approach)
- Create: `app/lib/payment/driver_qr_display.dart` (spec + approach)
- Modify: `app/pubspec.yaml` (add `path_provider`, `image_picker`)
- Modify: `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb`
- Modify: `app/lib/ride/driver_inbox_page.dart` (one AppBar action to reach QR capture)
- Test: `app/test/payment/driver_qr_store_test.dart`

**Interfaces:**
- Produces: `abstract interface class DriverQrStore { Future<void> save(Uint8List pngBytes); Future<Uint8List?> load(); Future<void> clear(); }`; `class FileDriverQrStore implements DriverQrStore` (constructor takes `Future<String> Function() documentsDirectoryPath`); `driverQrStoreProvider`; `class DriverQrCapturePage extends ConsumerWidget`; `class DriverQrDisplay extends ConsumerWidget` (renders the saved QR image, or a "not set" hint + link to capture).
- Consumed by: Task 7 (`ActiveTripView`'s completion step, driver role only) and Task 8 (`TaximeterPage`'s finished step).

- [ ] **Step 1: Write the failing store test**

`app/test/payment/driver_qr_store_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/payment/driver_qr_store.dart';

void main() {
  late Directory tempDir;
  late FileDriverQrStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('takhi_qr_test');
    store = FileDriverQrStore(() async => tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('load returns null when nothing has been saved', () async {
    expect(await store.load(), isNull);
  });

  test('save then load round-trips the exact bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await store.save(bytes);
    final loaded = await store.load();
    expect(loaded, bytes);
  });

  test('save overwrites a previously saved image', () async {
    await store.save(Uint8List.fromList([1]));
    await store.save(Uint8List.fromList([9, 9]));
    expect(await store.load(), Uint8List.fromList([9, 9]));
  });

  test('clear removes the saved image', () async {
    await store.save(Uint8List.fromList([1, 2, 3]));
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('clear is a no-op when nothing was saved', () async {
    await store.clear();
    expect(await store.load(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/payment/driver_qr_store_test.dart` — Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `driver_qr_store.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

/// Local-only storage for the driver's own bank QR image (spec §8: "QR
/// зураг зөвхөн утсан дээрээ локал хадгалагдана" — never published to any
/// public profile, never leaves the device except when the driver
/// deliberately shows their own screen or, in a later plan, sends it
/// DM-encrypted to one specific rider). Abstracted behind an interface
/// (mirrors `KeyStore` in `identity/identity_service.dart`) so trip-
/// completion UI tests never touch the real filesystem directly.
abstract interface class DriverQrStore {
  Future<void> save(Uint8List pngBytes);
  Future<Uint8List?> load();
  Future<void> clear();
}

/// Persists the QR image as a single file in the app's private documents
/// directory. Never touches `flutter_secure_storage` — a bank QR image is
/// bytes, not a secret key, and secure storage's platform keystore
/// backends are not designed for arbitrary-sized binary blobs.
///
/// [documentsDirectoryPath] is injected (typically
/// `() async => (await getApplicationDocumentsDirectory()).path` from
/// `path_provider`) rather than called directly here, so tests can point
/// this at a real temp directory instead of mocking a platform channel —
/// the same "keep the untestable plugin call at the edge" shape as
/// `LocationSource`/`GeolocatorLocationSource` (Task 1).
class FileDriverQrStore implements DriverQrStore {
  final Future<String> Function() _documentsDirectoryPath;
  static const _fileName = 'driver_qr.bin';

  const FileDriverQrStore(this._documentsDirectoryPath);

  Future<File> _file() async {
    final dir = await _documentsDirectoryPath();
    return File('$dir/$_fileName');
  }

  @override
  Future<void> save(Uint8List pngBytes) async {
    final f = await _file();
    await f.writeAsBytes(pngBytes, flush: true);
  }

  @override
  Future<Uint8List?> load() async {
    final f = await _file();
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/payment/driver_qr_store_test.dart` — Expected: PASS.

- [ ] **Step 5: Add dependencies and the provider**

In `app/pubspec.yaml`, under `dependencies:`:

```yaml
  path_provider: ^2.1.4
  image_picker: ^1.1.2
```

Run: `flutter pub get`

`app/lib/payment/payment_providers.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'driver_qr_store.dart';

final driverQrStoreProvider = Provider<DriverQrStore>(
  (ref) => FileDriverQrStore(
    () async => (await getApplicationDocumentsDirectory()).path,
  ),
);
```

- [ ] **Step 6: Add the ARB keys this task's UI needs**

In `app/lib/l10n/app_mn.arb`:

```json
  "qrNotSetHint": "Та банкны QR-аа хараахан оруулаагүй байна",
  "qrCaptureTitle": "Банкны QR зураг",
  "qrCaptureAction": "Зураг сонгох",
  "qrSavedConfirmation": "QR хадгалагдлаа",
  "payWithQrOrCashHint": "Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү"
```

In `app/lib/l10n/app_en.arb`:

```json
  "qrNotSetHint": "You haven't added your bank QR yet",
  "qrCaptureTitle": "Bank QR image",
  "qrCaptureAction": "Choose image",
  "qrSavedConfirmation": "QR saved",
  "payWithQrOrCashHint": "Scan the driver's QR or pay cash"
```

- [ ] **Step 7: Build the capture and display widgets (spec + approach)**

`app/lib/payment/driver_qr_capture_page.dart` — a simple `ConsumerWidget`: an `image_picker` `ImagePicker().pickImage(source: ImageSource.gallery)` button (gallery only for MVP — no camera permission needed), a preview (`Image.memory`) of the picked file's bytes once chosen, and a `PrimaryButton` that calls `ref.read(driverQrStoreProvider).save(bytes)` then shows `l.qrSavedConfirmation` (e.g. a `SnackBar`) and pops. Follows `SeedBackupPage`'s existing single-purpose-page shape (`app/lib/onboarding/seed_backup_page.dart` — read it before implementing, for the app's established page-with-one-primary-action layout).

`app/lib/payment/driver_qr_display.dart` — a small `ConsumerWidget` used by both Task 7 and Task 8's completion screens:

```dart
class DriverQrDisplay extends ConsumerWidget {
  const DriverQrDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return FutureBuilder<Uint8List?>(
      future: ref.read(driverQrStoreProvider).load(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return Column(
            children: [
              Text(l.qrNotSetHint),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DriverQrCapturePage(),
                  ),
                ),
                child: Text(l.qrCaptureAction),
              ),
            ],
          );
        }
        return Image.memory(bytes, width: 220, height: 220);
      },
    );
  }
}
```

`DriverQrDisplay` is only ever instantiated when the current role is driver (Tasks 7/8 gate on `role`) — a passenger never renders their own QR-shaped hole, they see `l.payWithQrOrCashHint` text instead.

- [ ] **Step 8: Add a settings entry point from `DriverInboxPage`**

In `app/lib/ride/driver_inbox_page.dart`, add an `actions:` entry to both `Scaffold`'s `AppBar` (the map view and the awarded-handoff view):

```dart
appBar: AppBar(
  title: Text(l.appName),
  actions: [
    IconButton(
      icon: const Icon(Icons.qr_code),
      tooltip: l.qrCaptureTitle,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DriverQrCapturePage()),
      ),
    ),
  ],
),
```

Import `../payment/driver_qr_capture_page.dart` at the top. This is additive only — every existing `find.text(...)`/`find.byIcon(...)` assertion in `app/test/ride/driver_inbox_page_test.dart` still holds unchanged; no existing test needs modification for this step.

- [ ] **Step 9: Commit**

```bash
git add app/lib/payment app/lib/l10n app/lib/ride/driver_inbox_page.dart app/pubspec.yaml app/pubspec.lock app/test/payment
git commit -m "feat(app): local-only driver bank-QR storage and display"
```

---

### Task 6: Taximeter core — pure fare math, routing client, journal (`app/lib/meter/`)

**Files:**
- Create: `app/lib/meter/tariff_store.dart`
- Create: `app/lib/meter/fare_calc.dart`
- Create: `app/lib/meter/routing_client.dart`
- Create: `app/lib/meter/fare_estimate.dart`
- Create: `app/lib/meter/meter_session.dart`
- Create: `app/lib/meter/meter_journal.dart`
- Create: `app/lib/meter/meter_providers.dart`
- Modify: `app/pubspec.yaml` (add `http`, `shared_preferences`)
- Test: `app/test/meter/tariff_store_test.dart`
- Test: `app/test/meter/fare_calc_test.dart`
- Test: `app/test/meter/routing_client_test.dart`
- Test: `app/test/meter/fare_estimate_test.dart`
- Test: `app/test/meter/meter_session_test.dart`
- Test: `app/test/meter/meter_journal_test.dart`

**Interfaces:**
- Consumes: `GpsFix`, `GpsTrackAccumulator`, `haversineMeters` (Task 1).
- Produces: `abstract interface class TariffStore { Future<void> saveMntPerKm(int); Future<int?> loadMntPerKm(); }` + `SharedPreferencesTariffStore`/`InMemoryTariffStore`; `int computeFareMnt({required int mntPerKm, required int distanceMeters})`; `int estimateFareMntOffline({required int mntPerKm, required double straightLineDistanceMeters, double urbanFactor = 1.35})`; `abstract interface class RoutingClient { Future<double?> routeDistanceMeters({required fromLat, required fromLon, required toLat, required toLon}); }` + `OsrmRoutingClient`; `const List<String> defaultRoutingEndpoints`; `class FareEstimate { final int mnt; final bool isApproximate; }` + `Future<FareEstimate> estimateTripFare({required RoutingClient, required int mntPerKm, required fromLat, fromLon, toLat, toLon, double urbanFactor = 1.35, Duration timeout = const Duration(seconds: 4)})`; `class MeterSession { MeterSession({required int mntPerKm}); void addFix(GpsFix); List<GpsFix> get fixes; int get distanceMeters; int get durationSeconds; int get fareMnt; }`; `class MeterTripEntry { final int startedAt, endedAt, distanceMeters, fareMnt; ...toJson/fromJson }`; `abstract interface class MeterJournalStore { Future<void> append(MeterTripEntry); Future<List<MeterTripEntry>> loadAll(); }` + `SharedPreferencesMeterJournalStore`/`InMemoryMeterJournalStore`; providers `tariffStoreProvider`, `meterJournalStoreProvider`, `routingClientProvider`.
- Consumed by: Task 8's `TaximeterPage`.
- **Constraint:** no file in this task imports `RelayPool`, `RideDmChannel`, or `identity/` — see Global Constraints.

- [ ] **Step 1: Write the failing fare-math tests**

`app/test/meter/fare_calc_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/meter/fare_calc.dart';

void main() {
  test('computeFareMnt multiplies tariff by kilometers', () {
    expect(computeFareMnt(mntPerKm: 500, distanceMeters: 3000), 1500);
  });

  test('computeFareMnt rounds to the nearest төгрөг', () {
    expect(computeFareMnt(mntPerKm: 1000, distanceMeters: 1234), 1234);
  });

  test('computeFareMnt is zero at zero distance', () {
    expect(computeFareMnt(mntPerKm: 900, distanceMeters: 0), 0);
  });

  test('estimateFareMntOffline applies the urban-inflation factor', () {
    expect(
      estimateFareMntOffline(
        mntPerKm: 1000,
        straightLineDistanceMeters: 10000,
        urbanFactor: 1.35,
      ),
      13500,
    );
  });

  test('estimateFareMntOffline defaults urbanFactor to 1.35', () {
    expect(
      estimateFareMntOffline(mntPerKm: 1000, straightLineDistanceMeters: 10000),
      13500,
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/meter/fare_calc_test.dart` — Expected: FAIL.

- [ ] **Step 3: Implement `fare_calc.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Metered fare for a completed (or in-progress) distance: tariff ×
/// distance (spec §7.4 step 3: "бодогдож буй ₮ = профайлын км-тариф ×
/// явсан зай"). Rounds to the nearest whole төгрөг.
int computeFareMnt({required int mntPerKm, required int distanceMeters}) =>
    (mntPerKm * distanceMeters / 1000).round();

/// The offline pre-trip estimate (spec §7.4 step 2): straight-line
/// distance inflated by [urbanFactor] (spec default 1.35 — a real street
/// grid is never a straight line) times the tariff. The caller is always
/// responsible for labeling this "ойролцоогоор" (approximate) — this
/// function only computes the number.
int estimateFareMntOffline({
  required int mntPerKm,
  required double straightLineDistanceMeters,
  double urbanFactor = 1.35,
}) =>
    (mntPerKm * straightLineDistanceMeters * urbanFactor / 1000).round();
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/meter/fare_calc_test.dart` — Expected: PASS.

- [ ] **Step 5: Write the failing `RoutingClient`/`OsrmRoutingClient` tests**

Add `http` to `app/pubspec.yaml` under `dependencies:` (Step 5 continues below with the second dependency):

```yaml
  http: ^1.2.2
```

Run: `flutter pub get`

`app/test/meter/routing_client_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:takhi/meter/routing_client.dart';

void main() {
  test('routeDistanceMeters parses a successful OSRM response', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/route/v1/driving/106.9,47.9;107.0,48.0');
      return http.Response(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {'distance': 12345.6},
          ],
        }),
        200,
      );
    });
    final routing = OsrmRoutingClient(
      'https://router.project-osrm.org',
      httpClient: client,
    );
    final distance = await routing.routeDistanceMeters(
      fromLat: 47.9,
      fromLon: 106.9,
      toLat: 48.0,
      toLon: 107.0,
    );
    expect(distance, 12345.6);
  });

  test('routeDistanceMeters returns null on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('', 503));
    final routing = OsrmRoutingClient('https://x', httpClient: client);
    final distance = await routing.routeDistanceMeters(
      fromLat: 0,
      fromLon: 0,
      toLat: 1,
      toLon: 1,
    );
    expect(distance, isNull);
  });

  test('routeDistanceMeters returns null when the service reports no '
      'route', () async {
    final client = MockClient(
      (request) async =>
          http.Response(jsonEncode({'code': 'NoRoute', 'routes': []}), 200),
    );
    final routing = OsrmRoutingClient('https://x', httpClient: client);
    final distance = await routing.routeDistanceMeters(
      fromLat: 0,
      fromLon: 0,
      toLat: 1,
      toLon: 1,
    );
    expect(distance, isNull);
  });
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/meter/routing_client_test.dart` — Expected: FAIL.

- [ ] **Step 7: Implement `routing_client.dart`**

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches a real driving-route distance from a public OSRM/Valhalla-
/// compatible routing service (spec §7.4 step 2: "нийтийн routing
/// үйлчилгээгээр ... жинхэнэ маршрутын зай"), when the device is online.
/// Abstracted so [estimateTripFare] (`fare_estimate.dart`) is testable
/// without a real HTTP call.
abstract interface class RoutingClient {
  /// Returns the routed driving distance in meters, or `null` if the
  /// service could not compute a route (e.g. no road connectivity between
  /// the two points) — distinct from throwing, which signals the service
  /// itself was unreachable or returned a malformed response.
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  });
}

/// Default public routing endpoints (OSRM demo-server-compatible
/// `/route/v1/driving/{lon},{lat};{lon},{lat}` REST shape) — same public-
/// infrastructure category as the default relay/tile URLs (spec §11: "OSM
/// tile/relay-тэй ижил зарчмаар"), user-editable, never author-run.
/// Finalizing this list is an open protocol question (spec §16.7); this is
/// the working MVP default.
const List<String> defaultRoutingEndpoints = [
  'https://router.project-osrm.org',
];

/// Calls an OSRM-compatible `/route/v1/driving/...` endpoint.
class OsrmRoutingClient implements RoutingClient {
  final String baseUrl;
  final http.Client _http;

  OsrmRoutingClient(this.baseUrl, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/$fromLon,$fromLat;$toLon,$toLat'
      '?overview=false',
    );
    final response = await _http.get(uri);
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['code'] != 'Ok') return null;
    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final first = routes.first;
    if (first is! Map<String, dynamic>) return null;
    final distance = first['distance'];
    if (distance is! num) return null;
    return distance.toDouble();
  }
}
```

- [ ] **Step 8: Run to verify it passes, then write the failing `estimateTripFare` test**

Run: `flutter test test/meter/routing_client_test.dart` — Expected: PASS.

`app/test/meter/fare_estimate_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/meter/fare_estimate.dart';
import 'package:takhi/meter/routing_client.dart';

class _FakeRoutingClient implements RoutingClient {
  final Future<double?> Function() _onCall;
  _FakeRoutingClient(this._onCall);

  @override
  Future<double?> routeDistanceMeters({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) =>
      _onCall();
}

void main() {
  test('estimateTripFare uses the routed distance when available', () async {
    final routing = _FakeRoutingClient(() async => 10000);
    final estimate = await estimateTripFare(
      routingClient: routing,
      mntPerKm: 1000,
      fromLat: 0,
      fromLon: 0,
      toLat: 1,
      toLon: 1,
    );
    expect(estimate.mnt, 10000);
    expect(estimate.isApproximate, isFalse);
  });

  test('estimateTripFare falls back to the offline estimate when the '
      'routing client throws', () async {
    final routing = _FakeRoutingClient(() async => throw Exception('offline'));
    final estimate = await estimateTripFare(
      routingClient: routing,
      mntPerKm: 1000,
      fromLat: 0,
      fromLon: 0,
      toLat: 0,
      toLon: 1,
    );
    expect(estimate.isApproximate, isTrue);
    // haversine(0,0 -> 0,1) ~111195m * 1.35 * 1 mnt/m -> ~150,113
    expect(estimate.mnt, closeTo(150113, 50));
  });

  test('estimateTripFare falls back when the routing client returns null',
      () async {
    final routing = _FakeRoutingClient(() async => null);
    final estimate = await estimateTripFare(
      routingClient: routing,
      mntPerKm: 500,
      fromLat: 0,
      fromLon: 0,
      toLat: 0,
      toLon: 1,
    );
    expect(estimate.isApproximate, isTrue);
  });

  test('estimateTripFare falls back when the routing client exceeds the '
      'timeout', () async {
    final routing = _FakeRoutingClient(
      () => Future.delayed(const Duration(milliseconds: 50), () => 5000.0),
    );
    final estimate = await estimateTripFare(
      routingClient: routing,
      mntPerKm: 500,
      fromLat: 0,
      fromLon: 0,
      toLat: 0,
      toLon: 1,
      timeout: const Duration(milliseconds: 5),
    );
    expect(estimate.isApproximate, isTrue);
  });
}
```

- [ ] **Step 9: Run to verify it fails, then implement `fare_estimate.dart`**

Run: `flutter test test/meter/fare_estimate_test.dart` — Expected: FAIL.

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import '../geo/gps_track.dart';
import 'fare_calc.dart';
import 'routing_client.dart';

/// A pre-trip fare estimate (spec §7.4 step 2): the number, plus whether it
/// came from real routed distance ([isApproximate] false) or the offline
/// straight-line fallback ([isApproximate] true — UI must label it
/// "ойролцоогоор").
class FareEstimate {
  final int mnt;
  final bool isApproximate;
  const FareEstimate({required this.mnt, required this.isApproximate});
}

/// Tries [routingClient] first (bounded by [timeout]); falls back to the
/// offline straight-line × [urbanFactor] estimate on any failure — network
/// error, timeout, or the routing service returning no route. This IS the
/// online/offline branch spec §7.4 step 2 describes; there is no separate
/// "are we online" check first, because attempting the call and catching
/// its failure is the only reliable signal on a mobile network (a passed
/// connectivity check does not guarantee the follow-up request succeeds).
Future<FareEstimate> estimateTripFare({
  required RoutingClient routingClient,
  required int mntPerKm,
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
  double urbanFactor = 1.35,
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final routed = await routingClient
        .routeDistanceMeters(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
        )
        .timeout(timeout);
    if (routed != null) {
      return FareEstimate(
        mnt: computeFareMnt(mntPerKm: mntPerKm, distanceMeters: routed.round()),
        isApproximate: false,
      );
    }
  } on Exception {
    // Network error, timeout, or malformed response — fall through to the
    // offline estimate below.
  }
  final straightLine = haversineMeters(fromLat, fromLon, toLat, toLon);
  return FareEstimate(
    mnt: estimateFareMntOffline(
      mntPerKm: mntPerKm,
      straightLineDistanceMeters: straightLine,
    ),
    isApproximate: true,
  );
}
```

- [ ] **Step 10: Run to verify it passes**

Run: `flutter test test/meter/fare_estimate_test.dart` — Expected: PASS.

- [ ] **Step 11: Write the failing `MeterSession` test, then implement it**

`app/test/meter/meter_session_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-01-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/meter_session.dart';

void main() {
  test('MeterSession accumulates distance/duration/fare from fed fixes', () {
    final session = MeterSession(mntPerKm: 1000);
    session.addFix(const GpsFix(lat: 0, lon: 0, timestampSeconds: 0));
    session.addFix(const GpsFix(lat: 0, lon: 1, timestampSeconds: 60));
    expect(session.distanceMeters, closeTo(111195, 2));
    expect(session.durationSeconds, 60);
    expect(session.fareMnt, closeTo(111195, 2));
  });

  test('MeterSession starts at zero before any fix', () {
    final session = MeterSession(mntPerKm: 500);
    expect(session.distanceMeters, 0);
    expect(session.durationSeconds, 0);
    expect(session.fareMnt, 0);
  });
}
```

(Fix the stray `01` typo — the SPDX line must read exactly `// SPDX-License-Identifier: AGPL-3.0-or-later`.)

Run: `flutter test test/meter/meter_session_test.dart` — Expected: FAIL.

`app/lib/meter/meter_session.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import '../geo/gps_fix.dart';
import '../geo/gps_track.dart';
import 'fare_calc.dart';

/// Accumulates GPS fixes for one taximeter run (spec §7.4 step 3: the big
/// live ₮/km/time display) and derives the running fare. `TaximeterPage`
/// (Task 8) owns the actual `LocationSource` subscription and calls
/// [addFix] as fixes arrive; this class has no I/O of its own.
class MeterSession {
  final int mntPerKm;
  final GpsTrackAccumulator _track = GpsTrackAccumulator();

  MeterSession({required this.mntPerKm});

  void addFix(GpsFix fix) => _track.addFix(fix);

  List<GpsFix> get fixes => _track.fixes;
  int get distanceMeters => _track.distanceMeters;
  int get durationSeconds => _track.durationSeconds;
  int get fareMnt =>
      computeFareMnt(mntPerKm: mntPerKm, distanceMeters: distanceMeters);
}
```

Run: `flutter test test/meter/meter_session_test.dart` — Expected: PASS.

- [ ] **Step 12: Write the failing `TariffStore`/`MeterJournalStore` tests, then implement them**

Add `shared_preferences` to `app/pubspec.yaml` under `dependencies:`:

```yaml
  shared_preferences: ^2.3.2
```

Run: `flutter pub get`

`app/test/meter/tariff_store_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/meter/tariff_store.dart';

void main() {
  test('InMemoryTariffStore round-trips a saved value', () async {
    final store = InMemoryTariffStore();
    expect(await store.loadMntPerKm(), isNull);
    await store.saveMntPerKm(1200);
    expect(await store.loadMntPerKm(), 1200);
  });

  test('SharedPreferencesTariffStore persists via shared_preferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store =
        SharedPreferencesTariffStore(SharedPreferences.getInstance);
    expect(await store.loadMntPerKm(), isNull);
    await store.saveMntPerKm(950);
    expect(await store.loadMntPerKm(), 950);
  });
}
```

`app/test/meter/meter_journal_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/meter/meter_journal.dart';

void main() {
  test('InMemoryMeterJournalStore appends and lists entries in order',
      () async {
    final store = InMemoryMeterJournalStore();
    expect(await store.loadAll(), isEmpty);
    await store.append(
      const MeterTripEntry(
        startedAt: 1,
        endedAt: 100,
        distanceMeters: 2000,
        fareMnt: 3000,
      ),
    );
    await store.append(
      const MeterTripEntry(
        startedAt: 200,
        endedAt: 260,
        distanceMeters: 500,
        fareMnt: 800,
      ),
    );
    final all = await store.loadAll();
    expect(all.length, 2);
    expect(all.first.fareMnt, 3000);
    expect(all.last.fareMnt, 800);
  });

  test('SharedPreferencesMeterJournalStore persists JSON-encoded entries',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store =
        SharedPreferencesMeterJournalStore(SharedPreferences.getInstance);
    await store.append(
      const MeterTripEntry(
        startedAt: 1,
        endedAt: 90,
        distanceMeters: 1500,
        fareMnt: 2200,
      ),
    );
    final all = await store.loadAll();
    expect(all.length, 1);
    expect(all.first.distanceMeters, 1500);
    expect(all.first.fareMnt, 2200);
  });
}
```

Run: `flutter test test/meter/tariff_store_test.dart test/meter/meter_journal_test.dart` — Expected: FAIL.

`app/lib/meter/tariff_store.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// The driver's own km-tariff (₮/km), local-only. Plan 3 (spec §16, own
/// Self-Review open question #4) explicitly deferred the public kind-0
/// profile extension (car/plate/km-tariff) as not yet built — this store
/// is the taximeter's local-only stand-in for that field, never published,
/// never part of any Nostr event.
abstract interface class TariffStore {
  Future<void> saveMntPerKm(int mntPerKm);
  Future<int?> loadMntPerKm();
}

class SharedPreferencesTariffStore implements TariffStore {
  static const _key = 'takhi_driver_tariff_mnt_per_km';
  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesTariffStore(this._prefs);

  @override
  Future<void> saveMntPerKm(int mntPerKm) async =>
      (await _prefs()).setInt(_key, mntPerKm);

  @override
  Future<int?> loadMntPerKm() async => (await _prefs()).getInt(_key);
}

/// Test double, mirrors `InMemoryKeyStore` (`identity/identity_service.dart`).
class InMemoryTariffStore implements TariffStore {
  int? _value;

  @override
  Future<void> saveMntPerKm(int mntPerKm) async => _value = mntPerKm;

  @override
  Future<int?> loadMntPerKm() async => _value;
}
```

`app/lib/meter/meter_journal.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One completed taximeter run, kept purely as the driver's own local
/// statistics (spec §7.4 step 7: "локал журналд бичигдэнэ ... нэр хүнд
/// ҮҮСГЭХГҮЙ"). Never signed, never published, never leaves the device,
/// and — critically — never fed into `computeReputation`: no counterpart
/// ever signs a reciprocal receipt for it, so per spec §9/§4.3 it can
/// never be anything but weightless even if it were mistakenly published.
class MeterTripEntry {
  final int startedAt;
  final int endedAt;
  final int distanceMeters;
  final int fareMnt;

  const MeterTripEntry({
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.fareMnt,
  });

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt,
        'endedAt': endedAt,
        'distanceMeters': distanceMeters,
        'fareMnt': fareMnt,
      };

  factory MeterTripEntry.fromJson(Map<String, dynamic> json) =>
      MeterTripEntry(
        startedAt: json['startedAt'] as int,
        endedAt: json['endedAt'] as int,
        distanceMeters: json['distanceMeters'] as int,
        fareMnt: json['fareMnt'] as int,
      );
}

abstract interface class MeterJournalStore {
  Future<void> append(MeterTripEntry entry);
  Future<List<MeterTripEntry>> loadAll();
}

/// Persists the journal as one JSON array under a single
/// `shared_preferences` key. A local append-only list of a few dozen
/// entries a day comfortably fits `shared_preferences`' expected size
/// envelope; a real database is unwarranted for this MVP volume (YAGNI).
class SharedPreferencesMeterJournalStore implements MeterJournalStore {
  static const _key = 'takhi_meter_journal';
  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesMeterJournalStore(this._prefs);

  @override
  Future<void> append(MeterTripEntry entry) async {
    final prefs = await _prefs();
    final all = await loadAll();
    final updated = [...all, entry];
    await prefs.setString(
      _key,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Future<List<MeterTripEntry>> loadAll() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MeterTripEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Test double, mirrors `InMemoryKeyStore`.
class InMemoryMeterJournalStore implements MeterJournalStore {
  final List<MeterTripEntry> _entries = [];

  @override
  Future<void> append(MeterTripEntry entry) async => _entries.add(entry);

  @override
  Future<List<MeterTripEntry>> loadAll() async =>
      List.unmodifiable(_entries);
}
```

Run: `flutter test test/meter/tariff_store_test.dart test/meter/meter_journal_test.dart` — Expected: PASS.

- [ ] **Step 13: Wire providers**

`app/lib/meter/meter_providers.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meter_journal.dart';
import 'routing_client.dart';
import 'tariff_store.dart';

final tariffStoreProvider = Provider<TariffStore>(
  (ref) => SharedPreferencesTariffStore(SharedPreferences.getInstance),
);

final meterJournalStoreProvider = Provider<MeterJournalStore>(
  (ref) => SharedPreferencesMeterJournalStore(SharedPreferences.getInstance),
);

final routingClientProvider = Provider<RoutingClient>(
  (ref) => OsrmRoutingClient(defaultRoutingEndpoints.first),
);
```

- [ ] **Step 14: Run every meter test and commit**

Run: `flutter test test/meter/` — Expected: PASS (all 6 files).

```bash
git add app/lib/meter app/test/meter app/pubspec.yaml app/pubspec.lock
git commit -m "feat(app): offline taximeter core -- fare math, routing client, journal"
```

---

### Task 7: Active-trip view — shared by both roles (`app/lib/ride/`)

**Files:**
- Create: `app/lib/ride/trip_role.dart`
- Create: `app/lib/ride/active_trip_view.dart` (spec + approach)
- Modify: `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb`
- Test: `app/test/ride/trip_role_test.dart`
- Test: `app/test/ride/active_trip_view_test.dart` (spec + approach)

**Interfaces:**
- Consumes: `GpsTrackAccumulator`, `LocationSource`, `ensureLocationPermission` (Task 1), `TripPhase`, `TripStatusService`, `LiveLocationChannel` (Task 3), `TripReceiptRepository.publish`, `isTripReceiptPaired` (Task 4), `DriverQrDisplay` (Task 5), `RideMap` (Plan 3), `currentIdentityProvider` (Plan 2).
- Produces: `enum TripRole { driver, passenger; String get wireValue; }`; `class ActiveTripView extends ConsumerStatefulWidget { const ActiveTripView({required TripRole role, required String tripId, required String counterpartyPubHex, required int agreedPriceMnt}); }`.
- Consumed by: Task 9's edits to `PassengerRidePage`/`DriverInboxPage` (composed as a step, **not** a routed page — no new go_router route is added for this widget).

- [ ] **Step 1: Write the failing `TripRole` test**

`app/test/ride/trip_role_test.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/trip_role.dart';

void main() {
  test('wireValue matches buildTripReceipt/PROTOCOL.md §4.2 role strings',
      () {
    expect(TripRole.driver.wireValue, 'driver');
    expect(TripRole.passenger.wireValue, 'passenger');
  });
}
```

- [ ] **Step 2: Run to verify it fails, then implement `trip_role.dart`**

Run: `flutter test test/ride/trip_role_test.dart` — Expected: FAIL.

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Which side of a trip the local device is on.
enum TripRole {
  driver,
  passenger;

  /// The wire value `buildTripReceipt`'s `role` field and PROTOCOL.md §4.2
  /// expect — 'driver' or 'passenger'. Kept as an explicit mapping (rather
  /// than relying on `.name`, which happens to match today) so a future
  /// rename of the enum case can never silently change the wire value.
  String get wireValue => switch (this) {
        TripRole.driver => 'driver',
        TripRole.passenger => 'passenger',
      };
}
```

Run: `flutter test test/ride/trip_role_test.dart` — Expected: PASS.

- [ ] **Step 3: Build `ActiveTripView` (spec + approach)**

`ActiveTripView` is a `ConsumerStatefulWidget` taking `role`, `tripId`, `counterpartyPubHex`, `agreedPriceMnt`. Internal state machine (private, not exported):

```dart
enum _ActiveTripStep { tracking, rating, done }
```

Behavior, by phase:

1. **On `initState`:** read `currentIdentityProvider`. Call `ensureLocationPermission()` (Task 1); if it returns `false`, show a full-screen "location access needed" state with a retry button instead of proceeding. Once granted, subscribe to `ref.read(locationSourceProvider).watch()`, feeding every fix into a local `GpsTrackAccumulator` (own-side distance/duration tracker for the eventual receipt) AND, throttled to roughly once every `LiveLocationChannel`-appropriate interval (e.g. only forward every 2nd-3rd fix, or gate by a `Timer.periodic(Duration(seconds: 5))` sampling the accumulator's latest fix), calling `ref.read(liveLocationChannelProvider).send(...)` to the counterparty.
2. Also subscribe to `ref.read(liveLocationChannelProvider).watch(myPubHex, myPrivHex, tripId)` for the counterparty's position (drives a second `Marker` on the `RideMap`), and to `ref.read(tripStatusServiceProvider).watchStatus(myPubHex, myPrivHex)` filtered to `tripId` for incoming phase changes (passenger side only needs this; driver side is the one calling `sendStatus`).
3. **Phase display:** a `TripPhase` local field, initialized to `TripPhase.enRouteToPickup`. Driver role only: two buttons appear as the phase progresses — "Зорчигч сууллаа" (`markPassengerBoardedAction`, visible while phase is `enRouteToPickup`, transitions local phase to `tripInProgress` and calls `sendStatus(phase: tripInProgress)`), then "Аялал дууслаа" (`endTripAction`, visible while phase is `tripInProgress`, transitions local phase to `arrived`, calls `sendStatus(phase: arrived)`, cancels the location-stream subscriptions, and moves `_ActiveTripStep` to `rating`). Passenger role: no buttons for phase — the phase field is driven entirely by `watchStatus`'s incoming stream; receiving `TripPhase.arrived` cancels its own subscriptions and moves to `_ActiveTripStep.rating` the same way.
4. **Map:** a `RideMap` with two `Marker`s (self, from the local `GpsTrackAccumulator`'s latest fix; counterparty, from the latest `LiveLocation` received) — reuse `RideMap`'s existing `layers:` parameter (Plan 3, `app/lib/map/ride_map.dart`) with a small new `MarkerLayer` built inline (no new file needed — two markers is not worth its own reusable layer class the way `NearbyRequestsLayer` was for an unbounded list).
5. **`_ActiveTripStep.rating`:** a star-rating input (1-5, e.g. `Row` of 5 `IconButton`s toggling `Icons.star`/`Icons.star_border`) + an optional comment `TextField`, and a `PrimaryButton` (`submitRatingAction`) that calls:

```dart
await ref.read(tripReceiptRepositoryProvider).publish(
  privHex: identity.privHex,
  now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  tripId: widget.tripId,
  counterpartyPubkey: widget.counterpartyPubHex,
  role: widget.role.wireValue,
  ratingStars: _selectedStars,
  distanceMeters: _track.distanceMeters,
  durationSeconds: _track.durationSeconds,
  priceMnt: widget.agreedPriceMnt,
  comment: _commentController.text,
);
```

then moves to `_ActiveTripStep.done`.

6. **`_ActiveTripStep.done`:** `Text(l.tripReceiptPublished)`, `Text(l.agreedPriceLabel(widget.agreedPriceMnt))`; if `widget.role == TripRole.driver`, also render `const DriverQrDisplay()` (Task 5); if passenger, render `Text(l.payWithQrOrCashHint)` instead. `isTripReceiptPaired` is available here (via a one-shot `tripReceiptRepositoryProvider.receiptsAbout(counterpartyPubHex)` call) for an optional "нэр хүнд баталгаажлаа" confirmation badge once the counterpart's receipt shows up — this is a nice-to-have, non-blocking enhancement layered on top of the already-complete flow, not a gate on reaching `done`.
7. **`dispose()`:** cancel every subscription opened in `initState` (mirrors `PassengerRidePage.dispose`/`DriverInboxPage.dispose`'s existing pattern exactly) — without this, the location/status streams leak for the app's remaining lifetime, same class of bug those two `dispose()` overrides already guard against.

- [ ] **Step 4: Add this task's ARB keys**

`app/lib/l10n/app_mn.arb`:

```json
  "tripPhaseEnRouteToPickup": "Жолооч ирж байна",
  "tripPhaseInProgress": "Аяллын явцад",
  "tripPhaseArrived": "Хүрлээ",
  "markPassengerBoardedAction": "Зорчигч сууллаа",
  "endTripAction": "Аялал дууслаа",
  "rateTripTitle": "Аяллыг үнэлнэ үү",
  "submitRatingAction": "Илгээх",
  "tripReceiptPublished": "Баримт нийтлэгдлээ",
  "agreedPriceLabel": "Тохирсон үнэ: {price}₮",
  "@agreedPriceLabel": { "placeholders": { "price": { "type": "int" } } },
  "locationPermissionNeededHint": "Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай",
  "grantLocationPermissionAction": "Зөвшөөрөл өгөх"
```

`app/lib/l10n/app_en.arb`:

```json
  "tripPhaseEnRouteToPickup": "Driver is on the way",
  "tripPhaseInProgress": "Trip in progress",
  "tripPhaseArrived": "Arrived",
  "markPassengerBoardedAction": "Passenger boarded",
  "endTripAction": "End trip",
  "rateTripTitle": "Rate this trip",
  "submitRatingAction": "Submit",
  "tripReceiptPublished": "Receipt published",
  "agreedPriceLabel": "Agreed price: {price}₮",
  "locationPermissionNeededHint": "Location access is needed to track this trip",
  "grantLocationPermissionAction": "Grant permission"
```

- [ ] **Step 5: Write a representative widget test (spec + approach)**

`app/test/ride/active_trip_view_test.dart` should mirror `handoff_service_test.dart`/`passenger_ride_page_test.dart`'s override style: `ProviderScope` with `keyStoreProvider`, `relayPoolProvider` (a `FakeRelaySocket`-backed pool) and `locationSourceProvider` (a `FakeLocationSource`) all overridden. Cover, at minimum:
- Pumping `ActiveTripView(role: TripRole.driver, ...)`, emitting two `GpsFix`es through the fake location source, and asserting a live-location event (`"kind":20178`) was published to the fake socket.
- Tapping `markPassengerBoardedAction` then `endTripAction` and asserting a gift-wrapped (`"kind":1059`) DM was sent for each, decodable via `nip17Unwrap` + `RideDmPayload.decode` into `RideTripStatusPayload` with the expected `phase`.
- Selecting a star rating and tapping `submitRatingAction`, then asserting a `"kind":30177` event was published whose `parseTripReceipt(...).tripId`/`.priceMnt`/`.ratingStars` match what was entered.
- Pumping `ActiveTripView(role: TripRole.passenger, ...)`, emitting an incoming `RideTripStatusPayload(phase: TripPhase.arrived)` DM from the fake socket, and asserting the widget reaches the rating step without any local button tap (proving the passenger side is receive-only for phase).

- [ ] **Step 6: Run and commit**

Run: `flutter test test/ride/trip_role_test.dart test/ride/active_trip_view_test.dart` — Expected: PASS.

```bash
git add app/lib/ride/trip_role.dart app/lib/ride/active_trip_view.dart app/lib/l10n app/test/ride/trip_role_test.dart app/test/ride/active_trip_view_test.dart
git commit -m "feat(app): shared active-trip view (live map, phase, rating, receipt publish)"
```

---

### Task 8: Taximeter screen (`app/lib/meter/taximeter_page.dart`)

**Files:**
- Create: `app/lib/meter/taximeter_page.dart` (spec + approach)
- Create: `app/lib/meter/onboarding_qr_config.dart`
- Modify: `app/pubspec.yaml` (add `qr_flutter`)
- Modify: `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb`
- Test: `app/test/meter/taximeter_page_test.dart` (spec + approach)

**Interfaces:**
- Consumes: `TariffStore`, `MeterSession`, `MeterJournalStore`, `RoutingClient`, `estimateTripFare` (Task 6), `LocationSource`, `ensureLocationPermission` (Task 1), `DriverQrDisplay` (Task 5), `LocationPickerField`/`RideMap` (Plan 3).
- Produces: `const String kTakhiAppDownloadUrl`; `class TaximeterPage extends ConsumerStatefulWidget`.
- Consumed by: Task 9's router wiring (the one new routed screen this plan adds, `/meter`) and `HomePage`'s driver-mode entry button.
- **Constraint (repeated from Global Constraints):** this file and everything it imports from `meter/` must never import `RelayPool`, `RideDmChannel`, or `identity/` — the taximeter never touches a relay or mints a Nostr event.

- [ ] **Step 1: Add the onboarding-QR config constant**

`app/lib/meter/onboarding_qr_config.dart`:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Where the "Тахь тат" QR (spec §7.4 step 6, §10 onboarding loop) points a
/// scanning phone. The real distribution channel (own domain vs. GitHub
/// Releases vs. F-Droid) is an open protocol question (spec §16.4/§16.5) —
/// this is the MVP default, easy to swap in one place once decided.
const String kTakhiAppDownloadUrl =
    'https://github.com/takhi-app/takhi/releases/latest';
```

- [ ] **Step 2: Add `qr_flutter`**

In `app/pubspec.yaml` under `dependencies:`:

```yaml
  qr_flutter: ^4.1.0
```

Run: `flutter pub get`

- [ ] **Step 3: Build `TaximeterPage` (spec + approach)**

`ConsumerStatefulWidget`, no constructor parameters (reads everything from providers). Internal state:

```dart
enum _MeterStep { needsTariff, idle, running, finished }
```

Behavior:

1. **On `initState`:** `ref.read(tariffStoreProvider).loadMntPerKm()`; if `null`, start at `_MeterStep.needsTariff` — a one-field form (`meterTariffFieldLabel`, numeric `TextField`) + `PrimaryButton` (`saveTariffAction`) that calls `saveMntPerKm` and advances to `idle`. This directly reuses the existing `_PriceStep`-style single-field-and-button layout already established in `passenger_ride_page.dart` — follow that shape, don't invent a new one.
2. **`_MeterStep.idle`:** a big `PrimaryButton` (`startMeterAction`, styled prominently per spec §7.4 step 1 — "Товч дарж эхлүүлэх") plus an optional `LocationPickerField` (Plan 3, `app/lib/map/location_picker.dart`) for an optional destination pin. If a destination is set, call `ensureLocationPermission()` + get one fix from `ref.read(locationSourceProvider).watch()` (`.first`) as the "from" point, then `estimateTripFare(routingClient: ref.read(routingClientProvider), mntPerKm: tariff, fromLat/fromLon: current fix, toLat/toLon: picked destination)` and show `l.estimatedFareLabel(estimate.mnt)`, adding the literal word "ойролцоогоор" via a separate `Text(l.estimatedFareApproxLabel)` line whenever `estimate.isApproximate` is true. Tapping start: `ensureLocationPermission()`, construct a `MeterSession(mntPerKm: tariff)`, subscribe to `locationSourceProvider.watch()` feeding `session.addFix`, record `startedAt = DateTime.now()`, move to `running`.
3. **`_MeterStep.running`:** the spec's "том тоогоор" screen — a large `Text('${session.fareMnt}₮')` (biggest text on the page, e.g. `fontSize: 56`+, matching spec §7.4 step 3's "Дэлгэцэд том тоогоор... Зорчигчид харуулахад зориулагдсан тод харагдац"), plus `l.meterRunningDistanceLabel(session.distanceMeters / 1000)`, `l.meterRunningDurationLabel(session.durationSeconds ~/ 60)`, a `RideMap` showing the accumulated route as a `Polyline` built from `session.fixes`, and a `PrimaryButton` (`finishMeterAction`). Rebuilds on a periodic `Timer` (e.g. every 2s) rather than only on each GPS fix, so the elapsed-time display keeps advancing between fixes.
4. Tapping finish: cancel the location subscription, record `endedAt`, append a `MeterTripEntry(startedAt, endedAt, session.distanceMeters, session.fareMnt)` via `ref.read(meterJournalStoreProvider).append(...)`, move to `finished`.
5. **`_MeterStep.finished`:** `l.meterSummaryTitle`, the final ₮/km/time, `const DriverQrDisplay()` (Task 5 — always shown here, since this screen is driver-only by construction), and a small `QrImageView(data: kTakhiAppDownloadUrl, size: 96)` (from `qr_flutter`) with `l.downloadTakhiQrLabel` beneath it (spec §7.4 step 6). A final button resets to `idle` for the next passenger.

- [ ] **Step 4: Add this task's ARB keys**

`app/lib/l10n/app_mn.arb`:

```json
  "taximeterTitle": "Таксиметр",
  "startMeterAction": "Эхлүүл",
  "meterDestinationOptionalHint": "Очих цэг (сонголттой)",
  "estimatedFareLabel": "≈ {mnt}₮",
  "@estimatedFareLabel": { "placeholders": { "mnt": { "type": "int" } } },
  "estimatedFareApproxLabel": "ойролцоогоор",
  "meterRunningDistanceLabel": "{km} км",
  "@meterRunningDistanceLabel": { "placeholders": { "km": { "type": "double" } } },
  "meterRunningDurationLabel": "{min} мин",
  "@meterRunningDurationLabel": { "placeholders": { "min": { "type": "int" } } },
  "finishMeterAction": "Дуусгах",
  "meterSummaryTitle": "Аяллын дүн",
  "downloadTakhiQrLabel": "Тахь — эзэнгүй такси",
  "meterTariffFieldLabel": "1 км-ийн үнэ (₮)",
  "saveTariffAction": "Хадгалах",
  "startAsMeterAction": "Таксиметр"
```

`app/lib/l10n/app_en.arb`:

```json
  "taximeterTitle": "Taximeter",
  "startMeterAction": "Start",
  "meterDestinationOptionalHint": "Destination (optional)",
  "estimatedFareLabel": "≈ {mnt}₮",
  "estimatedFareApproxLabel": "approximate",
  "meterRunningDistanceLabel": "{km} km",
  "meterRunningDurationLabel": "{min} min",
  "finishMeterAction": "Finish",
  "meterSummaryTitle": "Trip total",
  "downloadTakhiQrLabel": "Takhi — ownerless taxi",
  "meterTariffFieldLabel": "Price per km (₮)",
  "saveTariffAction": "Save",
  "startAsMeterAction": "Taximeter"
```

- [ ] **Step 5: Write a representative widget test (spec + approach)**

`app/test/meter/taximeter_page_test.dart`, overriding `tariffStoreProvider` with an `InMemoryTariffStore`, `meterJournalStoreProvider` with an `InMemoryMeterJournalStore`, `locationSourceProvider` with `FakeLocationSource`, and `routingClientProvider` with a fake that always throws (forcing the offline-estimate path deterministically). Cover:
- Setting a tariff advances from `needsTariff` to `idle`.
- Tapping start, emitting fixes through `FakeLocationSource`, and asserting the growing fare/distance text updates.
- Tapping finish and asserting `InMemoryMeterJournalStore.loadAll()` gained exactly one entry with the expected `distanceMeters`/`fareMnt`.
- Asserting the `finished` step never touches `relayPoolProvider` — the simplest structural proof is that this test's `ProviderScope` never overrides `relayPoolProvider` at all and the test still passes, showing the whole flow works without one existing.

- [ ] **Step 6: Run and commit**

Run: `flutter test test/meter/taximeter_page_test.dart` — Expected: PASS.

```bash
git add app/lib/meter/taximeter_page.dart app/lib/meter/onboarding_qr_config.dart app/lib/l10n app/pubspec.yaml app/pubspec.lock app/test/meter/taximeter_page_test.dart
git commit -m "feat(app): taximeter screen (Замын Унаа mode)"
```

---

### Task 9: Wire it all together

**Files:**
- Modify: `app/lib/router.dart` (add `/meter` route + `HomePage`'s driver-mode taximeter button)
- Modify: `app/lib/ride/passenger_ride_page.dart` (`_DoneStep` gains a button into `ActiveTripView`)
- Modify: `app/lib/ride/driver_inbox_page.dart` (awarded-handoff view gains a button into `ActiveTripView`; retain the offered price)
- Modify: `PROTOCOL.md` (mark kind 20178's builder as implemented)
- Modify: `app/test/ride/passenger_ride_page_test.dart`, `app/test/ride/driver_inbox_page_test.dart`, `app/test/home_page_test.dart` (extend, not replace)

**Interfaces:**
- Consumes everything from Tasks 1-8. Produces nothing new — this is pure composition.

- [ ] **Step 1: `PassengerRidePage` — add the "go to active trip" step**

Add a new enum value to `_PassengerStep`:

```dart
enum _PassengerStep { pickup, destination, price, offers, done, activeTrip }
```

In `_PassengerRidePageState`, keep `_select` exactly as-is (still transitions to `.done` — the existing `passenger_ride_page_test.dart` flow is unchanged up through this point) and extend the `_DoneStep` widget with a button:

```dart
class _DoneStep extends StatelessWidget {
  final RankedRideOffer? selected;
  final VoidCallback onStartTrip;
  const _DoneStep({required this.selected, required this.onStartTrip});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final vehicle = selected?.offer.payload.vehicleDescription;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            vehicle == null ? '' : l.driverOnTheWay(vehicle),
            style: const TextStyle(color: TakhiColors.gold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l.startTripAction, onPressed: onStartTrip),
        ],
      ),
    );
  }
}
```

Wire it in `PassengerRidePage.build`'s `switch`:

```dart
_PassengerStep.done => _DoneStep(
  selected: _selected,
  onStartTrip: () => setState(() => _step = _PassengerStep.activeTrip),
),
_PassengerStep.activeTrip => ActiveTripView(
  role: TripRole.passenger,
  tripId: /* the tripId HandoffService.sendHandoff returned in _select — store it in a new _tripId field set alongside _selected */,
  counterpartyPubHex: _selected!.offer.driverPubkey,
  agreedPriceMnt: _selected!.offer.payload.priceMnt,
),
```

(`_select` already calls `HandoffService.sendHandoff`, which returns the trip id — capture it in a new `String? _tripId` field there, exactly as `_rideRequestId` is already captured from `publishRequest`'s return value.)

Add `startTripAction` to both ARB files: mn `"Аялал руу очих"`, en `""Go to trip"`.

- [ ] **Step 2: Run the existing passenger test to confirm it is unaffected**

Run: `flutter test test/ride/passenger_ride_page_test.dart` — Expected: PASS unchanged (it never taps past the `_DoneStep`'s existing "Prius" assertion, so the new button doesn't interfere).

- [ ] **Step 3: Add a new passenger test covering the extra step**

Append to `app/test/ride/passenger_ride_page_test.dart` a second `testWidgets` that repeats the existing flow through the "Prius" assertion, then additionally taps `find.text('Аялал руу очих')` and asserts `find.byType(ActiveTripView)` (or a distinguishing piece of its content, e.g. the phase label) becomes visible.

- [ ] **Step 4: `DriverInboxPage` — retain the offered price and add the "start trip" button**

Add a new state field:

```dart
int? _lastOfferedPriceMnt;
bool _activeTrip = false;
```

In `_sendOffer`'s `onSubmit` callback, right before calling `offerServiceProvider.sendOffer`, add:

```dart
setState(() => _lastOfferedPriceMnt = priceMnt);
```

In the awarded-handoff branch of `build`, append a button below the existing landmark/plus-code `Column` children (leave every existing child and every existing test assertion untouched):

```dart
const SizedBox(height: 16),
PrimaryButton(
  label: l.viewActiveTripAction,
  onPressed: () => setState(() => _activeTrip = true),
),
```

Then, before the existing `if (_awardedHandoff != null) { ... }` block, add:

```dart
if (_activeTrip && _awardedHandoff != null) {
  return Scaffold(
    appBar: AppBar(title: Text(l.appName)),
    body: ActiveTripView(
      role: TripRole.driver,
      tripId: _awardedHandoff!.payload.tripId,
      counterpartyPubHex: _awardedHandoff!.senderPubkey,
      agreedPriceMnt: _lastOfferedPriceMnt ?? 0,
    ),
  );
}
```

Add `viewActiveTripAction` to both ARB files: mn `"Аялал эхлүүлэх"`, en `"Start trip"`.

- [ ] **Step 5: Run the existing driver test to confirm it is unaffected, then add a new one**

Run: `flutter test test/ride/driver_inbox_page_test.dart` — Expected: PASS unchanged (the existing test never taps past its final three `find.text` assertions).

Append a second `testWidgets` repeating the flow through the handoff-received assertions, then tapping `find.text('Аялал эхлүүлэх')` and asserting the `ActiveTripView` content is now shown instead of the plain handoff summary.

- [ ] **Step 6: Add the taximeter entry point and route**

In `app/lib/router.dart`, add to `routes:`:

```dart
GoRoute(path: '/meter', builder: (context, state) => const TaximeterPage()),
```

Import `'meter/taximeter_page.dart'` and `'ride/active_trip_view.dart'`/`'ride/trip_role.dart'` (the latter two are used inside `passenger_ride_page.dart`/`driver_inbox_page.dart`, not `router.dart` itself — import them there instead).

In `HomePage.build`, inside the `TakhiMode.driver` branch, add a second button below the existing `PrimaryButton`:

```dart
if (_mode == TakhiMode.driver) ...[
  const SizedBox(height: 12),
  OutlinedButton(
    onPressed: () => context.go('/meter'),
    child: Text(l.startAsMeterAction),
  ),
],
```

(Placed as a conditional spread inside the existing `Column`'s `children:` list, immediately after the primary "start as driver/passenger" `PrimaryButton`.)

- [ ] **Step 7: Run `home_page_test.dart` and adjust if it asserts an exact widget count**

Run: `flutter test test/home_page_test.dart`. If it fails because it counts buttons exactly (e.g. `findsOneWidget` for a `PrimaryButton`/`OutlinedButton` type-based finder rather than a text-based one), update its finder to be specific by text/key rather than by count — this is a pre-existing test, read it first before editing.

- [ ] **Step 8: Update `PROTOCOL.md`**

In `PROTOCOL.md`, change the kind-20178 row (§3) from:

```
| `20178` | Аяллын амьд байршил | ephemeral, NIP-44 шифртэй | kind тогтмол (`kKindLiveLocation`) тодорхойлогдсон; builder Plan 3 (ride state machine)-д |
```

to:

```
| `20178` | Аяллын амьд байршил | ephemeral, NIP-44 шифртэй | `buildLiveLocationEvent` / `parseLiveLocationEvent` (Plan 4) |
```

And remove the now-stale "Deviation" bullet in §11 that referred to this row (the one starting "**Deviation:** `20178` ... ба `30178` ..."), narrowing it to only `30178` (still correctly deferred to Plan 5).

- [ ] **Step 9: Full test suite, both packages**

Run (from `packages/takhi_protocol/`): `dart test` — Expected: all PASS.
Run (from `app/`): `flutter test` — Expected: all PASS.
Run (from `app/`): `flutter analyze` — Expected: no errors.

- [ ] **Step 10: Commit**

```bash
git add app/lib/router.dart app/lib/ride/passenger_ride_page.dart app/lib/ride/driver_inbox_page.dart app/lib/l10n PROTOCOL.md app/test/ride/passenger_ride_page_test.dart app/test/ride/driver_inbox_page_test.dart app/test/home_page_test.dart
git commit -m "feat(app): wire active-trip view and taximeter into both ride pages"
```

---

## Self-Review

**1. Spec coverage (brief scope item → task):**
- Scope item 1 (active trip + live location, kind 20178, NIP-44, phase states жолооч ирж байгаа→суусан→замд→хүрсэн) → Task 2 (protocol event) + Task 3 (channel + phase signaling) + Task 7 (UI wiring both roles). The "суусан"/"замд" merge into one `tripInProgress` phase is a documented, deliberate simplification (Task 3 Step 1's doc comment) — there is no driver action that distinguishes them.
- Scope item 2 (trip completion + dual-signed receipt on one `trip_id`, paired-only weight per §9) → Task 4 (`isTripReceiptPaired` + `TripReceiptRepository.publish`) + Task 7 (rating UI calling `publish` on both sides independently).
- Scope item 3 (payment: driver's QR shown on completion screen, local-only, never in the public profile) → Task 5 (`DriverQrStore`/`DriverQrDisplay`/capture page) + Task 7/8 (both completion screens render it, driver-role-gated).
- Scope item 4 (offline taximeter / Замын Унаа: driver-only, no address required, optional destination, big ₮/km/time display, online routing vs. offline straight-line×1.35 estimate, fully offline execution with zero Nostr events, local journal, "Тахь тат" onboarding QR) → Task 6 (pure fare math + routing client + journal) + Task 8 (`TaximeterPage`). The "never touches `RelayPool`/identity" constraint is stated explicitly in both tasks' headers and Global Constraints, and Task 8 Step 5's test plan calls out a structural proof (no `relayPoolProvider` override needed for the flow to pass).
- Spec §7.5 (cancellation before a trip starts) — unaffected by this plan; already fully handled by Plan 3's `RideCancelPayload`/`RideRequestService.cancelWithDriver`. Not touched here since Plan 4's scope begins strictly after handoff.
- **Deferred to Plan 5, explicitly out of scope here (per the task brief):** P2P WebRTC calling (§7.3) and safety/SOS/trip-sharing (§10's "Аялал-хуваалцах вэб"). No file under `app/lib/call/` or `app/lib/safety/` is touched by this plan.
- **Gap noted honestly, carried forward from Plan 3's own Self-Review:** driver profile (kind-0 extension: car, plate, km-tariff) is still not built. The taximeter's `TariffStore` (Task 6) is a local-only, device-only stand-in for the km-tariff field specifically, not a general profile system — the same open item Plan 3 flagged remains open for a future plan.
- **Gap noted honestly:** `DriverInboxPage`'s pre-existing one-active-engagement limitation (documented in its own doc comment since Plan 3) is not fixed by this plan — `_lastOfferedPriceMnt`/`_awardedHandoff` still track only the single most recent engagement. A real multi-offer dashboard remains a future-plan item, as Plan 3's own Self-Review already anticipated.

**2. Placeholder scan:** No `TODO`/`TBD`/"handle appropriately" anywhere. Two spots that look unusual are intentional, not placeholders: `kTakhiAppDownloadUrl` (Task 8) is a real, working URL shape explicitly documented as an MVP stand-in pending spec §16.4/§16.5's still-open domain/F-Droid decision — the same honesty pattern Plan 3 used for its PoW-difficulty and `flutter_map` version-pin open questions. `defaultRoutingEndpoints` (Task 6) is likewise flagged as pending spec §16.7. Task 6 Step 11's test file's SPDX-line typo (`AGPL-3.0-01-later`) is called out and corrected inline in the same step, not left as a real defect in the deliverable.

**3. Type consistency:** `TripPhase` (Task 3) is defined once and used identically in `RideTripStatusPayload` (Task 3), `TripStatusService`/`ReceivedTripStatus` (Task 3), and `ActiveTripView` (Task 7) — no separate phase representation is introduced anywhere else. `TripRole`/`.wireValue` (Task 7) is the only role representation passed into `TripReceiptRepository.publish`'s `role:` parameter, matching `buildTripReceipt`'s existing `String role` field exactly (verified by `trip_role_test.dart` against the literal wire strings 'driver'/'passenger' already used throughout `takhi_events_test.dart`/`trip_receipt_repository_test.dart`). `GpsFix`/`GpsTrackAccumulator` (Task 1) are the single distance/duration engine reused unchanged by both `MeterSession` (Task 6, composition) and `ActiveTripView`'s own tracker (Task 7) — no duplicate haversine implementation exists anywhere in the plan. `LiveLocationChannel.send`/`.watch` (Task 3) and `buildLiveLocationEvent`/`parseLiveLocationEvent` (Task 2) signatures match at every call site. `DriverQrStore`/`DriverQrDisplay` (Task 5) are the only QR-image storage/display path referenced by both Task 7 and Task 8's completion screens — no second implementation is introduced for the taximeter.

## How live location and the paired receipt were modeled

Live location (kind 20178) deliberately skips the NIP-17/NIP-59 gift-wrap envelope that offers/handoff/cancel/trip-status all use: it is a single NIP-44-encrypted event, signed by the sender's real key, sent every few seconds for the duration of a trip. By the time it starts, both pubkeys are already mutually known from the reputation-visible offer exchange (spec §7.1 step 3) and the driver's exact-pickup handoff — gift-wrap's identity-hiding and timing-randomization properties protect nothing at this stage, only cost battery and latency on a high-frequency channel. Discrete, must-not-be-missed state transitions (in particular "trip arrived," which is what tells the passenger to move into rating) stay on the already-reliable NIP-17 `RideDmChannel` via a fourth `RideDmPayload` subtype, `RideTripStatusPayload` — this is the one place this plan extends a Plan 3 sealed class, and it is additive-only (no exhaustive switch over `RideDmPayload` exists anywhere in the app, confirmed by grep before adding the fourth case).

The paired-receipt rule (spec §9/§4.3) was already fully enforced at the reputation-aggregation level by Plan 1's `computeReputation`/`hasCounter`. This plan adds the single-trip, UI-facing companion (`isTripReceiptPaired`) that answers "has my counterpart signed yet" for one specific `trip_id` rather than weighing a whole history — deliberately a separate, smaller function rather than a shared abstraction with `hasCounter`, since the two serve different callers with different return shapes (bool vs. a diminishing-returns weighted score).

## Open questions

1. **`geolocator`'s exact `LocationSettings` interval API** (Task 1) needs confirmation against whatever `flutter pub add geolocator` resolves — the base `LocationSettings` class has no interval knob; `AndroidSettings`/`AppleSettings` subclasses may be needed to honor the spec's 5-10s cadence precisely. `GeolocatorLocationSource`'s doc comment already flags this; nothing above the `LocationSource` interface depends on the exact resolution.
2. **`defaultRoutingEndpoints` (Task 6) and `kTakhiAppDownloadUrl` (Task 8) are MVP placeholders for still-open spec questions** (§16.7 routing endpoints, §16.4/§16.5 domain/F-Droid) — both are one-line changes once those are decided, same shape as Plan 3's PoW-difficulty open question.
3. **New dependency count is high for one plan** (`geolocator`, `http`, `path_provider`, `shared_preferences`, `image_picker`, `qr_flutter` — six). Each is genuinely required by a distinct spec capability (GPS, routing REST call, local file, local key-value, gallery picker, QR rendering) and each is a widely-used, actively maintained pub.dev package; still worth a deliberate `flutter pub outdated` pass once implementation starts, matching Plan 3's own version-pin caution.
4. **`ActiveTripView`'s live-location send throttling** (Task 7 Step 3, "throttled to roughly once every ... interval") is described at the approach level, not with an exact sampling algorithm — the implementer should pick a concrete throttle (e.g. a 5-second `Timer.periodic` reading the accumulator's latest fix) during Task 7 and cover it with a test asserting the publish rate, not just that at least one event was sent.
5. **Driver profile (kind-0 extension) remains unbuilt**, carried forward from Plan 3. `TariffStore` (Task 6) is scoped narrowly to the taximeter's own local tariff, not a general fix for that gap.
