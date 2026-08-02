# Тахь — SDD progress ledger

## Plan 1 — takhi_protocol цөм (docs/superpowers/plans/2026-07-21-takhi-protocol-core.md)
Branch: build. 13/13 tasks built (workflow wf_6dff1fee-20e), 47 tests green, analyze 2 info-lint.
Commits: 2e01fce..6ac97c3
Final whole-branch review: spec=OK, quality=BLOCKED on 5 IMPORTANT → fix wave (commit 9d5c7b2): all 5 fixed.
NIP-44 >32B padding verified interop-correct vs official vectors. **Plan 1 COMPLETE**: 61/61 tests, analyze clean, coverage 97.73%.
Public API confirmed: generateKeyPair/pubkeyFromPrivate/generateMnemonic/privateKeyFromMnemonic, hexToNpub/npubToHex/nsecToHex, NostrEvent/computeEventId/signEvent/verifyEvent, geohashEncode, plusCodeEncode, minePow, buildRideRequest/parseRideRequest/buildTripReceipt/parseTripReceipt, computeReputation, nip44Encrypt/Decrypt.

## Plan 2 — app shell — COMPLETE
6/6 tasks (workflow wf_7840e927), final review 2 CRITICAL + 2 IMPORTANT → fix (commit c015ab9): all fixed.
43 tests green, analyze clean, `flutter build web` succeeds. RelayPool wired (4 default relays, relayConnectionProvider),
router redirect + key-overwrite guard, functional dark theme. App public: routerProvider, relayPoolProvider,
relayConnectionProvider, identityServiceProvider, currentIdentityProvider, IdentityService, RelayPool, RelayFilter, TakhiColors, takhiTheme.

## Plan 3 — NIP-17 + ride matching + map — COMPLETE
9/9 tasks (workflow wf_dd450013). Final review spec=OK quality=OK, 1 IMPORTANT (DriverInboxPage widget-test gap) → fix (162f46d): DriverInboxPage widget test + 2 real bugs fixed (silent 0-offer, dropped async Future). 91 app tests green.
Protocol 76 tests, app 90 tests, analyze clean. Ride screens wired to router. NIP-17 adversarial (spoof/wrong-recipient) green.
App public added: nip17Wrap/nip17Unwrap/UnwrappedDm (protocol); ride/ services (RideRequestService, DriverInboxService, OfferService, rankRideOffers, HandoffService, TripReceiptRepository, RideDmChannel), map/ (RideMap, LocationPickerField, NearbyRequestsLayer), PassengerRidePage, DriverInboxPage, ride_providers.dart.

## Plan 4 — active trip + taximeter + payment QR (docs/.../2026-07-22-takhi-active-trip.md) — BUILDING
9 tasks: GPS abstraction (geo/), live-location kind 20178 (protocol, direct NIP-44), trip phase+status DM+live channel,
trip receipt pairing (isTripReceiptPaired, protocol), payment local-only DriverQrStore, taximeter core (fare math+OSRM+journal),
ActiveTripView (composed into both role pages), TaximeterPage (offline), wiring. Tasks 2,4 touch protocol; rest app.

Plan 4 built 9/9 (workflow wf_48891afc): protocol 90 tests, app 143 tests, analyze clean. ActiveTripView composed into both role pages, TaximeterPage routed, taximeter offline. Final review spec=OK quality=BLOCKED 2 IMPORTANT (taximeter dest onChanged no-debounce→OSRM spam+race; DriverQrDisplay FutureBuilder rebuild flicker)+3 minor → fix wave.

Plan 4 COMPLETE: fix (5918280) taximeter debounce+race, DriverQrDisplay cached future, 3 minors. 147 app + 90 protocol tests, analyze clean.

## Plan 5 — P2P calling + safety + polish + Android APK — COMPLETE
10/10 tasks (workflow wf_8ff19b00). Final review found 3 CRITICAL (fallback rungs unwired: helper-TURN dead, phone-fallback unreachable, voice-note receive unwired) + 2 IMPORTANT → fix (45fc4de): all wired end-to-end + reentrancy guard + PROTOCOL.md corrected.
Protocol 94 tests, app 234 tests (concurrency=1; errno-121 = Windows socket flakiness, not real), analyze clean. Release APK produced (Task 10). LICENSE/README/FORKING/HELPER/PROTOCOL.md + docs/share/index.html shipped. AndroidManifest INTERNET fixed.

## Final whole-branch review (aac6e528): 0 CRITICAL, invariants hold, security solid, tests 94+234 green, analyze clean, web build ok.
verdict NEEDS_FIXES — 2 spec-completeness gaps silently dropped across plans + legal disclaimer:
1. §7.2 GPS-taximeter mode for Nostr-matched rides (spec §4 "MVP-д хоёул орно" — only agreed-fixed + offline meter exist).
2. Driver profile kind-0 takhi extension (car/color/plate/km-tariff, spec §6) — only free-text vehicleDescription exists.
3. Legal risk disclaimer in-app (spec §4) — absent.
Minor: bound _seenEventIds (unbounded Set). → completion wave dispatched.

## Completion wave (adc6ff56) COMPLETE: driver profile (kind-0), §7.2 metered-match pricing, legal disclaimer, _seenEventIds cap.
Protocol 102 tests, app 262 tests, analyze clean. Release APK rebuilt: arm64 34MB / universal 93MB / v7a 26MB.

## Navigation-back fix wave (wf_e2cd30d3-241, branch fix/navigation-back)
Trigger: user hit a dead end in the shipped APK -- "yaagaad back khiiideg function baidagguim bee".
Root cause was a SPEC gap, not an implementation slip: the design doc only ever described the
forward path, so all 5 plans built forward-only flows and every per-plan review (which checks
code-vs-spec) passed. Nothing in the pipeline could flag an absence the spec never named.
3 parallel auditors (screen-level nav / in-page step flows / state-loss-on-leave) -> 37 findings,
29 CRITICAL+IMPORTANT -> base layer (l10n keys, go->push, ConfirmLeaveScope) -> 3 page agents ->
2 reviewers -> fix wave. Both reviewers returned NEEDS_FIXES; all confirmed and fixed.

Fixed beyond the original complaint (found by the audit, not by the user):
- HomePage used `context.go` for ride/driver/meter -> stack replaced, no back arrow, hardware back
  exited the app. Now `push`.
- Multi-step flows (passenger pickup->destination->price->offers, meter tariff->idle) had onNext
  only. Step-back added; entered data survives the round trip.
- SeedBackupPage had NO guard at all -- a stray back press dropped the 12 words permanently.
  Uses its own PopScope + `go('/home')`, NOT ConfirmLeaveScope (pop is a no-op on a root route).
- Tapping an offer sent exact pickup + phone immediately, with no confirm step.
- CallScreen dispose sent no hangup -> counterparty saw a silent drop.
- `_guardBack` swapped ConfirmLeaveScope<->PopScope as the top element, remounting ActiveTripView
  and rewinding a settled trip to its first phase (caught by a test the fix agent wrote).

Orchestrator follow-up on the 4 MINOR items the wave left: ConfirmLeaveScope now asserts on a
root route instead of trapping the user in a back->dialog->back loop; sos_button mounted-guard;
`meteredOfferNoTariffHint` was an ORPHAN string -- the metered-offer toggle vanished silently for
a driver with no km-tariff, so the string got wired to the gap it was written for rather than
deleted. Mechanized: l10n_completeness_test now fails on any .arb key no file under lib/ uses
(mn<->en parity alone cannot see an orphan -- it is perfectly translated on both sides).
309 app tests green, analyze clean. Settings sub-routes are still top-level rather than nested
under /settings: harmless today (every caller uses `push`, no deep links registered), latent if
deep links land -- deliberately deferred, not overlooked.

## Design-spec pass (wf_23f5845f-b40) + the code defects it surfaced (wf_80b14b71-98d)
User rejected the built-in UI ("front end taalagdakhgui baigaa") and will design in Google Stitch
instead, so the deliverable became a per-screen spec: docs/design/UI_SURFACES.md (31 surfaces,
priority-tiered) then docs/design/SCREEN_SPECS.md (S1-S31 + S14a, 38 Stitch prompts, mermaid nav
map, 322 KB), plus docs/design/screens/07-dialog-splash.md (S32 dialog standard, S33 splash).
Intake folder for his returning designs: design/stitch/README.md.

Writing the spec turned out to be a better code audit than any review pass, because it forced
someone to state what each screen *is* rather than check that it matches a spec:
- takhi_theme.dart had NO dialogTheme -> M3 defaults + TextButton foreground = primary = gold,
  so every dialog action ("Үлдэх"/"Гарах"/"Цуцлах") rendered gold-on-paper at ~2.28:1, half the
  WCAG AA floor, across 7 dialogs. Now themed, with contrast tests modelled on theme_test.dart's
  existing WCAG checks.
- Button emphasis was inverted: the only FilledButton in the app was the *destructive*
  overwrite-identity confirm; every other risky action was a flat TextButton. Now: intentional
  confirms get filled gold, back-reflex leave guards emphasise staying, key destruction stays red.
- Cyrillic overflows what English fits. Measured at NotoSans SemiBold 16sp: "Цуцлах" +
  "Тийм, үргэлжлүүл" = ~273dp against 264dp of content width on a 360dp phone -- does not fit,
  and "Үлдэх" + "Нүүр хуудас руу" (~264dp) fails on 320dp. New widgets/dialog_action_bar.dart
  stacks vertically when the row will not fit, with the order INVERTED (danger on top, safe
  under the thumb -- the dialog was opened by a downward back gesture that keeps travelling).
  Never ellipsis, never FittedBox, never abbreviate.
- router.dart read `currentIdentityProvider.valueOrNull`, which cannot tell `loading` from
  `data(null)` -- so every returning user saw a flash of the onboarding screen before being
  redirected home. Now a splash continuation: 0ms floor, 3s ceiling (a hung keystore must not
  trap the user), progress indicator only after 600ms.
- flutter_native_splash's `color_dark` (#1C1A16) did not match the app's dark ground (#211E19),
  a visible jump on every dark-mode launch. Corrected and regenerated.
Also corrected in the ledger's own record: UI_SURFACES.md claimed splash was unbuilt Android
default; flutter_native_splash was in fact already configured. The claim was repeated without
being checked.
347 app + 102 protocol tests green, analyze clean.

Finalized (wf_2c9db42a-1db): S32 (dialog standard) + S33 (splash) merged as §4.7 -> 34 screens,
47 prompts, 4488 lines / 422 KB. Two structural lessons got mechanized here:
- The doc referenced code by LINE NUMBER and drifted 4 times in two days (+4, +13, +18, +30),
  each drift costing a manual repair pass. All 401 refs are now SYMBOL anchors
  (`passenger_ride_page.dart` -> `_LocationStep`); names survive edits, line numbers do not.
- The first checker written for this was a hand-maintained list of 69 line/token pairs for a
  single file -- a rot trap that would pass while the doc was wrong. Replaced by
  `tools/check_spec_symbols.py`, which PARSES the doc for (file, symbol) pairs itself and fails
  on any symbol missing from its file, or on any surviving `file:line` / `symbol:line` anchor.
  206 anchors across 85 files, exit 0. (It also caught its own Windows bug: the Mongolian report
  crashed on cp1252 stdout, so it failed even when every anchor was correct.)
Notably the verify agent found §4.7 was describing gaps that the dialog/startup wave had ALREADY
closed -- two agents writing about the same code hours apart. Docs written alongside a moving
codebase need a verify pass against HEAD, not against the state the author remembers.

## Design overhaul + product additions (branch fix/navigation-back, 2026-07-30)
User rejected the built-in UI outright, then supplied UBCab screenshots as the reference. Root
cause of the rejection, found by loading the design skills: the brand palette I had invented
(#F4F1E9 paper / #C99A3C gold / #1C1A16 ink) is almost exactly the palette those skills name as
*the* AI-default -- one hex digit from the listed `#f4f1ea`, with brass and espresso from the same
banned families. It felt generic because it is what every model reaches for.

Rebuilt against the reference: full-bleed map, white bottom sheet, pill fields, coloured category
tiles, chips for metadata, heavy headings. All ~32 screens converted. Then:
- Waiting fare + pause. UB traffic made distance-only pricing wrong: 25 minutes in a jam earned
  0₮. Two tariffs, mode auto-switches at 5 km/h, and the meter is in exactly ONE mode at a time --
  charging distance *and* time together would bill a stationary car twice off GPS jitter.
- Driver family/given name + mandatory face photo, gated in logic (no photo -> cannot offer).
  Face check = tflite_flutter + MediaPipe BlazeFace, both Apache-2.0 (ML Kit rejected: proprietary
  blob, breaks F-Droid). Name and photo travel ONLY in the gift-wrapped offer DM, never in the
  public kind-0 -- a face published to relays is a face anyone can harvest.
  Stated in-app: this is a gate, not proof of identity. No serverless app can verify a face
  belongs to its owner, and pretending otherwise sells a guarantee that does not exist.
- Passenger GPS pin on entering the ride flow; the *published* request stays geohash-6 coarse.

Mechanised guards added, each after the class of bug it prevents bit us:
- design_system_audit_test: raw sizes, raw colours, bare TakhiType in ButtonStyle, route coverage.
- font_coverage_test: reads the bundled font's cmap and checks every character in the .arb files.
  Third time a missing glyph shipped (₮ overlap, «Түр зогсоох» tofu, then `≈`); now impossible.
- 57 golden screenshots, coverage enforced from router.dart in both directions.

The lesson worth keeping: TWO of this wave's bugs were invisible to 565 passing tests and visible
in one glance at a PNG. And a guard is worthless until a mutation probe proves it fails -- the
first size-guard passed its own probe, because its escape hatch let `const _probe = SizedBox(
height: 13)` through. Assume every new guard is hollow until you have watched it go red.

## HANDOFF 2026-07-31 -- what to do next, written before a context compaction
User is away for the evening and asked for work to continue without them. Do these in order.

1. **Finish the map/fare wave** (workflow wf_2853efa4-2b2, running at handoff time): device
   location marker, destination marker, OSRM route line, fit-both-points, fare estimate, and
   re-opening the golden exclusions for map screens. When it lands: full test run, analyze,
   dart format, regenerate goldens, LOOK at the new map pictures (marker actually drawn? line
   drawn? two points distinguishable?), then commit.
   These four gaps came from the user running the real APK -- none were visible in any test.

2. **GitHub release.** Repo is local-only so far. Before publishing:
   - Check `app/android` signing config. If the release APK is signed with a throwaway/debug
     key, a GitHub build will not install over the one already on the user's phone
     ("App not installed"), and every future update breaks the same way. A permanent .jks
     committed to the repo is the fix (see memory: streamflex-signing-key-fix). Verify before
     tagging, and tell the user in the release notes which key it is.
   - Publishing makes the whole history public. That matches the AGPL/open-source intent, but
     scan for anything that should not ship: secrets, absolute paths with the user's name,
     test fixtures with real personal data.
   - Attach the arm64 APK. Release notes in Mongolian, describing what a user can actually do.

3. **Then keep improving.** The user asked for polish and genuinely useful new functions.
   Highest-value candidates, in the order I would take them:
   - **Ride flow end-to-end on two real phones.** Nothing has ever been tested against a real
     relay with two devices. Everything so far is unit/widget/golden. This is the biggest
     unknown in the project.
   - **Offer list ranking is invisible.** offer_ranking.dart sorts, and the screen now says
     "all new drivers -- arrival order", but once real reputation exists the passenger has no
     way to see WHY one offer is above another.
   - **Trip history.** meter_journal stores meter runs; there is no screen to read them. A
     driver cannot see what they earned this week.
   - **Relay health.** If every default relay is unreachable the app degrades silently. The
     home chip shows a count but nothing explains a zero.
   - **Cancellation.** A passenger who publishes a request and changes their mind has a leave
     guard, but there is no explicit "cancel this request" affordance.

4. **Standing rules that earned their place this session** -- do not drop them:
   - A guard is hollow until a mutation probe makes it go red. Two guards passed their own
     probes here before being tightened.
   - Look at the rendered PNG with your own eyes. Three bugs shipped past a fully green suite.
   - `flutter test` never reads AndroidManifest/Gradle. A release build is its own check --
     run it before claiming the app works.

## USER FEEDBACK 2026-08-01, from running v0.2.0 on a real phone -- 6 items, NOT yet done
Ordered by severity. 2 and 3/4 are broken behaviour; 5 and 6 are product changes.

**2. DRIVER PROFILE DOES NOT SAVE (shipped broken).** Photo does not persist or reload;
family/given name fields do not persist either. The whole mandatory-photo gate is therefore
dead in practice. ALSO: profile text fields must accept Mongolian Cyrillic ONLY -- reject
Latin letters.

**3. GPS updates too rarely while driving.** Position lags well behind the car. Check the
LocationSettings distanceFilter/interval in geo/location_source.dart -- likely tuned too coarse.

**4. GPS jitter while STOPPED registers as movement.** A parked car accumulates distance.
This is not cosmetic: it overcharges the passenger on a taximeter, and it is the same class of
bug the one-mode-at-a-time rule was meant to prevent. Needs a real filter -- accuracy gate,
minimum-displacement threshold, speed sanity check, or a short moving average. Do NOT solve it
by widening the waiting-mode threshold alone; that hides it rather than fixing it.

**1. Taximeter pricing gains a third component, and one is renamed.**
   - distance x km-tariff  (unchanged)
   - stopped time x per-minute rate -- RENAME from "хүлээлгэ" to "түгжрэл/зогсолт"
     (traffic jam / stop), because that is what it actually is
   - NEW: total trip duration in minutes x a separate driver-set per-minute rate, added on top
   So the driver sets three rates and the receipt shows three lines.
   DECIDED by the user 2026-08-01, asked and answered -- do not re-litigate: the double count
   is INTENTIONAL. Duration runs over the WHOLE trip, stopped time included, so a driver who
   fills both the jam field and the duration field charges that time twice. That is the
   driver's call to make. Every rate field is OPTIONAL: left empty means that component is
   simply not charged. Whichever field the driver puts a number in is the one that computes.
   So: no validation forcing all three, no warning about overlap, no clever "moving time only"
   reinterpretation. Three independent optional rates, each doing exactly what it says.

**5. The passenger must NOT propose a price.** Remove the price step. Reasoning the user gave:
a passenger who types an unrealistically low number gets no offers and waits for nothing.
Instead the passenger publishes the request, sees each driver's own price, and picks. What the
passenger MAY add is a tip/bonus on top of the chosen driver's price ("I'll pay X extra for
taking this one"). Spec §7.1 assumed passenger-proposed pricing -- update it.

**6. Offers belong on the map, and dispatch should be sequential.** Today offers are a text
list. Wanted: see nearby drivers on the map and pick the car. And a dispatch ladder -- notify
the ~10 nearest drivers by distance; if one does not accept within N seconds, pass to the next;
if all 10 decline, either "no free taxi, try again" or roll to the next 10.
   ⚠️ This is the largest change in the list and it cuts against the current architecture: today
   every driver in the geohash neighbourhood sees every request and offers freely (spec §7.1).
   Sequential dispatch needs an ordering authority -- and there is no server to hold one. Think
   hard about how to do it with each client deciding locally (e.g. distance-derived delay before
   a driver may offer) before writing code, and tell the user honestly if a fully serverless
   version cannot match the behaviour they described.

## STATUS: ALL 5 PLANS + completion COMPLETE. App fully matches spec MVP. Close-out: merge build→main → save memory → deliver.
10 tasks: helper announcement (kind 30178), call signaling payloads, ICE config+helper directory, CallEngine abstraction,
fallback decision+phone exchange, voice-note fallback, CallService+CallScreen+ActiveTripView wiring, trip-share (throwaway key+static page),
SOS (tel:/sms: no new perms), polish+ship (APK release signing, PROTOCOL/FORKING/HELPER/LICENSE/README). Findings: AndroidManifest missing INTERNET (fix Task 4), release debug-signs (fix Task 10).
9 tasks: NIP-17 giftwrap (protocol), ride DM codec, RideDmChannel, RideRequestService, DriverInboxService,
offer+reputation ranking, HandoffService+tripId, map (flutter_map/OSM), ride screens. New kinds: seal=13, giftwrap=1059, rumor kRumorKindRideDm=20179.
Regrouped: Plan 3 = NIP-17 layer + request/offer/match/handoff + map selection.
Plan 4 = active trip (live loc, dual receipt, reputation) + taximeter + payment QR.
Plan 5 = P2P calling + safety (share/SOS) + polish + Android APK.

## 2026-08-01 — item 2 (driver profile) — root cause found, engine built, DEVICE PROOF STILL MISSING

The report was "the profile does not save". It was worse than that, and the
"names do not persist" half turned out to be **wrong**.

**What was actually broken: v0.2.0 could not be used by any driver at all.**
`driverOfferBlock` makes a portrait MANDATORY and `OfferService.sendOffer`
enforces it in the core, not in a disabled button. `faceDetectorProvider`
returned `UnavailableFaceDetector`, which throws for every image. So no
portrait could ever be set, and therefore not one driver anywhere could send
a single offer. This is a total-app-breakage bug, not a persistence annoyance.

**Why 848 tests were green.** Every test that touches the profile overrides
`faceDetectorProvider` with a stub that accepts, and every page test swaps
`SharedPreferencesDriverProfileStore` for `InMemoryDriverProfileStore`.
Between them the suite had substituted the entire production path. A
provider that every test replaces is a provider nothing tests.

**Names persist fine.** `driver_profile_persistence_test.dart` drives the
real store through the real page and the round trip works. The user most
likely never completed a save: `_canSave` also requires car, colour, plate
and km-tariff, and a disabled Save button explains nothing about why.
→ still to do: say why Save is disabled (see the remaining list below).

**What was built.** MediaPipe BlazeFace (Apache-2.0, 224KB) bundled, run
on-device via tflite_flutter. Deliberate split, because the shell cannot be
tested on a desktop VM at all:
  - `blaze_face_anchors.dart` / `blaze_face_decode.dart` /
    `blaze_face_letterbox.dart` — pure Dart, 28 tests, 3 mutation probes
    (NMS removed, /128 scale dropped, anchor x/y transposed → all went red)
  - `tflite_face_detector.dart` — load, resize, call. No policy, no maths.
Guard added so the original bug cannot return: the provider test fails if
`faceDetectorProvider` is ever an `UnavailableFaceDetector` again.

**⚠️ NOT VERIFIED — do this first when a device is available.**
`integration_test/face_detector_device_test.dart` exists and is complete
(loads model, accepts a synthetic portrait, rejects a drawn mountain,
survives compression, handles a landscape photo via the letterbox) but has
NEVER BEEN RUN. The phone was disconnected and the emulator on this machine
would not attach to adb (qemu runs, `adb devices` stays empty; two adb
binaries on PATH, forcing the SDK one got it to `offline` then it vanished).
So the claim "a driver can now set a portrait" is UNPROVEN. Do not tell the
user item 2 is finished until this test has actually passed on hardware:

    flutter test integration_test/face_detector_device_test.dart

Release APK does build with all of this (arm64 70.3MB; model + tflite JNI
confirmed inside, litert-gpu excluded). Gradle needed a JVM-target pin --
three failed approaches are recorded in `android/build.gradle.kts` so they
are not rediscovered.

**Still open on item 2:** Cyrillic-only validation for the name fields
(`driver_name.dart` currently allows `\p{L}`, i.e. Latin too), and telling
the driver WHY Save is disabled.

## 2026-08-01 (cont.) — items 3, 4 done; item 1 half done

**№4 GPS jitter billed as distance — FIXED, and it was real money.**
The waiting threshold is 5 km/h, which over a 5s fix interval is 6.9m. A
parked phone in a street with buildings either side drifts further than that
between fixes, so drift crossed the threshold and registered as travel.
`geo/gps_jitter.dart` now judges displacement against the fixes' OWN reported
accuracy, scaled by 2 (an accuracy figure is a confidence radius, not a
maximum error: two fixes each honestly claiming ±5m routinely land 9-10m
apart parked). Stopped time still accrues on the waiting meter -- only
distance is withheld -- so the driver is still paid for sitting in a jam.
A segment implying >200 km/h is treated as a bad fix and credited to neither
meter. 16 tests, 2 mutation probes (filter removed, scaling removed -> both
red). NOT solved by widening the threshold, as instructed.
Also fixed a fixture that drove 111 km in 60 seconds (6,672 km/h) and had
passed for weeks because nothing checked.

**№3 position lagging the car — FIXED.** `LocationSettings` had no interval
knob at all (the code comment admitted the interval was "only a hint"), so
Android batched fixes at its own discretion. Now `AndroidSettings.
intervalDuration` / `AppleSettings` with automotive activity type and
automatic pausing off. `distanceFilter` stays 0 deliberately: filtering by
distance at the source would suppress the very fixes that prove a car is
stationary, which the waiting meter needs.

**№2 remainder — Cyrillic-only names DONE.** `\p{Script=Cyrillic}`, not a
hand-written class (the Mongolian alphabet is Russian + Ө/Ү, and a hand
list is how `Ё` gets a real name rejected). New `DriverNameProblem.
notCyrillic` so a driver whose keyboard was in the wrong mode is told to
switch rather than sent hunting for a stray symbol; stray characters are
still reported first, so `<b>Бат</b>` does not get keyboard advice.
Dart has no character-class intersection -- `[\p{L}&&[^...]]` throws
FormatException -- so that check is a rune scan.

**№1 third tariff — HALF DONE. Fare math complete, UI not wired.**
Done: `computeDurationFareMnt`, `MeterSession.durationTariffMntPerMinute`
and `.durationFareMnt`, total = distance + stopped + duration, 8 tests
pinning the INTENTIONAL double count so nobody "fixes" it later.
Still to do:
  1. `DriverProfile` needs a `durationTariffMntPerMinute` field (protocol
     `buildDriverProfile` + `SharedPreferencesDriverProfileStore`, with the
     same absent-means-zero migration the wait tariff already has).
  2. A third box on `DriverProfilePage`, and `TaximeterPage` has to pass the
     rate into `MeterSession` and show a third row in the breakdown.
  3. RENAME the stopped-time rate everywhere in the UI from «хүлээлгэ» to
     «түгжрэл/зогсолт» -- l10n keys `driverProfileWaitTariff*`, the meter
     rows, the receipt. The l10n key names can stay; the strings change.

**Still open after that:** №5 (remove the passenger price step, add a
tip/bonus on the chosen driver's price, update spec §7.1) and №6 (offers on
the map + sequential dispatch -- research first, and tell the user honestly
if serverless cannot match it).

**And still unverified:** the face detector on hardware. See the previous
section; that remains the first thing to do when a device is attached.

## 2026-08-01 — №6 шийдвэрлэгдэв (хэрэглэгч сонгов)

Research first, as the ledger demanded: docs/design/SEQUENTIAL_DISPATCH.md.

**Told the user honestly what serverless cannot do**, and they accepted it:
true exclusivity ("only the 10 nearest are notified") is IMPOSSIBLE without a
dispatcher. A Nostr relay broadcasts to every subscriber matching the filter; it
cannot route by computed distance and cannot withhold an event from driver #2.
Clients can be asked to wait, not made to. What IS buildable -- and what the
passenger actually experiences -- is passenger-side sequential presentation: the
acceptance authority genuinely lives on the passenger's phone, so their client
orders the offers, shows them one at a time with a countdown, auto-advances, and
ends with "no free taxi, try again".

**USER DECIDED: option 2 -- only the drivers who OFFERED on this request appear on
the map.** Showing all free drivers up front is CLOSED, do not revive it: it would
require every driver to broadcast position publicly, and their kind-0 already
carries car/colour/plate, so it would let anyone follow a named, plated vehicle all
day and learn where its driver sleeps. Today live location is NIP-44 encrypted to
the matched passenger only -- that danger does not currently exist and must not be
created.

**Spec for the build:**
  - `RideOfferPayload` carries etaMinutes but NO position. Add one, as a geohash.
  - Precision: **geohash-7 (~±76m)**, a deliberate middle tier.
      geohash-6 (±600m, public request) is too coarse -- two drivers in one cell
      would draw on the same pixel and "pick your car" becomes meaningless.
      Exact point is too much -- a driver answering 10 requests would hand their
      exact position to the 9 passengers who did not choose them.
  - Offer stays NIP-17 gift-wrapped to one passenger; name/photo still never reach
    kind-0. The position is something the driver CHOOSES to send.
  - UI: keep the offer list (it carries price/reputation/order better than a map),
    add a map above it with a car marker per offer; tapping either opens the same
    offer card.

Still to do after the duration-tariff workflow lands: this, plus №5 (remove the
passenger price step, add a tip/bonus on the chosen driver's price, update §7.1).

## 2026-08-01 — №1 COMPLETE, and it hid two money bugs

The duration rate is wired end to end: third box on the profile, third row on
the meter and the receipt, recorded in the trip journal, published in kind-0 as
`duration_tariff` (absent-means-zero migration), and the stopped-time rate is
renamed «хүлээлгэ» → «зогсолт/түгжрэл» in 11 strings (keys unchanged).

**Two money bugs found by the adversarial reviewer and confirmed by RUNNING the
meter, not by reading it. Both are fixed and both have mutation-probed guards.**

1. **Pause did not stop the duration rate.** A 3-minute run with 2 minutes
   paused billed 1800₮ at 600₮/мин while the stopped-time meter correctly
   billed 0. `pause()` announced the meter was off and kept charging.
   The first fix -- `durationSeconds - pausedSeconds` -- was ALSO wrong and its
   own test caught it: the segment straddling a `pause()` call is discarded
   rather than counted as paused, so it lands in neither term and subtraction
   bills it anyway. That leaked a whole fix interval per pause, in the one
   direction this class never resolves doubt: against the passenger.
   Now `_billableDurationSeconds` accumulates only in the branches where the
   meter was genuinely live. A second has to be deliberately added to be
   billed, so it cannot leak. `durationSeconds` remains the honest wall clock
   for the receipt -- the two must not be confused.

2. **A negative rate produced a negative fare** (-1000₮). Both rate boxes now
   refuse a minus sign, but a rate reaches the core from places no text field
   guards: a profile cached by an older build, and a kind-0 published by
   somebody else's client. Clamped in `fare_calc`, per this repo's own rule
   that a rule belongs in the core rather than in a disabled button.

Also worth recording: I broke the build myself mid-fix. A scripted rewrite of
meter_session.dart replaced a text span that silently included the `isWaiting`
and `isPaused` getters, deleting them. `flutter test` on the one file I was
working on stayed green; the full suite went red with 30 "loading" failures
that looked exactly like the known Windows socket flake. Two lessons: run
`flutter analyze` after every scripted edit, not just after hand edits; and a
mass of "loading" failures is a COMPILE error until proven otherwise -- open
one and read it rather than counting them.
(The genuine socket flake is real and separate: stale `flutter_tester.exe`
processes from workflow agents accumulate and must be killed between runs.)

975 app + 151 protocol green, 73/73 goldens stable in comparison mode, analyze
clean, release APK builds (arm64 70.3MB).

**Remaining:** №5 (remove the passenger price step, add a tip/bonus on the
chosen driver's price, update spec §7.1), №6 (build what SEQUENTIAL_DISPATCH.md
now specifies), and the face detector still UNVERIFIED on hardware.

## 2026-08-01 — №5 COMPLETE (passenger no longer proposes a price)

`buildRideRequest` lost `offeredMnt`; `RideRequest` has no price field at all.
A `price` tag from an older client is IGNORED rather than parsed -- reading it
would put the removed behaviour back on the driver's screen through the back
door, and a driver who sees "the passenger wants to pay 3000₮" is anchored by
it whoever sent it. Test added for exactly that.

The price STEP survived, renamed `_ReviewStep` / `_PassengerStep.review`.
Asking for a price was never all it did: it draws the route, states distance
and duration, and carries the publish button. Removing the box leaves the last
look at the trip before it goes out to every driver nearby.

The bonus lives on the confirm-offer dialog (`_ConfirmOfferDialog`), travelling
as `RideHandoffPayload.tipMnt` inside the gift wrap. Only ever upwards:
a negative "bonus" would quietly lower a price the driver already accepted --
a counter-offer wearing the wrong name, agreed to by somebody who never saw it.
Guarded in the field AND at decode, because the value arrives from another
person's client. Driver's `agreedPriceMnt` = own quote + tip, so both screens
run the trip on one number. Zero is sent as absent, so no «Нэмэлт 0 ₮» row.

**Looking at the golden caught a bug no test could**: `routePreviewNoQuoteHint`
still read «Үнээ өөрөө нэрлэнэ» (you name your own price) on the very screen
that had just lost the box. Now «Жолооч бүр өөрийн үнээ хэлнэ, та сонгоно».

983 app + 152 protocol green, 73/73 goldens stable in comparison mode, analyze
clean, release APK builds (arm64 70.3MB).

**Known debt, not introduced here:** `tools/check_spec_symbols.py` still reports
10 unresolved anchors (call_screen bodies, sos_button `_openSheet`,
router `_HomePageState`, location_picker `TextField`, passenger
`_BackStepButton`). They pre-date this change -- the duration-tariff verifier
reported the same 10. The checker therefore exits non-zero as a matter of
course, which is a gate nobody can read. Worth one cleanup pass.

**Remaining:** №6 (build what SEQUENTIAL_DISPATCH.md specifies -- offers on the
map at geohash-7, passenger-side sequential presentation), and the face
detector STILL UNVERIFIED on hardware.

## 2026-08-01 — №6 FIRST HALF done (offers on the map). Second half NOT built.

Built: `RideOfferPayload.driverGeohash` (geohash-7, ~±76m), filled from the
driver's GPS fix (not the map centre -- that is where they are LOOKING, not
where they are), drawn by `OfferedDriversLayer` / `OffersMap`, tapping a car
opens the same driver page tapping the row does. Validated on decode: wrong
alphabet or empty is dropped, a finer cell from a future client is truncated
to ours rather than trusted, a non-string throws. A malformed cell costs the
map a car and nothing else -- the offer still arrives and is still choosable.

Two things only LOOKING at the golden could have found:
  1. First build put a 180dp map strip above the list. With the heading, the
     sort control and the strip, exactly ONE offer card was left on screen --
     and the list is where the passenger actually decides. Replaced with a
     «Жагсаалт | Газрын зураг» switch so each view gets the full frame.
  2. The two staged cars drew as one dot. I had TYPED the geohashes instead
     of computing them, and both landed in the Pacific off Palau; the camera
     fitted all three points across 5000km and the cars merged. Now computed
     from the rig's own origin. Lesson: never hand-write a geohash.
My own design-system guard also caught me -- `EdgeInsets.all(56)` as a raw
size. Named constant now.

**NOT BUILT, and it needs a decision rather than an assumption: the
passenger-side sequential presentation.** SEQUENTIAL_DISPATCH.md proposes
showing offers ONE AT A TIME with a countdown, auto-advancing, ending in "no
free taxi". The user confirmed the MAP option in their own words and said
nothing about this half.

It is a product fork, not an implementation detail:
  - The app currently shows a LIST with reputation, price, ETA and a
    three-way sort -- all of it built to let a passenger COMPARE.
  - One-at-a-time removes comparison. It is accept/skip, like Uber.
Both are defensible. The second discards work finished the same day and
changes what the product is, so it must be asked, not inferred.

**Remaining:** that decision, and the face detector STILL UNVERIFIED on
hardware (`integration_test/face_detector_device_test.dart`, never run).

## 2026-08-01 — NEW REQUEST (mid-turn): watch the driver approach, live

User, verbatim: «дуудлага авсан жолоочийн ирэхдээ одоо хаана явж байгааг
зорчигч ирэх хүртэл нь байнга real time хардаг байх».

**The machinery already exists and is simply not connected in this window.**
`LiveLocationChannel` (kind 20178, NIP-44 to the counterparty only) and the
tracking map both work -- but only inside `ActiveTripView`, which neither
side enters until the trip is STARTED. Between "driver chosen" and "trip
started" is exactly the stretch where the car is driving to the passenger,
and it is the stretch with no map at all:
  - passenger: `_DoneStep` shows a static card (name, car, portrait).
  - driver:    `_AwardedHandoffView` shows the pickup point, sends nothing.

To build:
  1. DRIVER: start publishing live location when the handoff arrives, not
     when the trip starts. They are already driving; that is the point.
     Reuse `ActiveTripView`'s existing 2-fix throttle rather than inventing
     a second cadence.
  2. PASSENGER: subscribe on `_DoneStep` (the `tripId` is already in hand
     from `sendHandoff`) and draw the car approaching the pickup pin.
  3. Both must stop when the booking is cancelled (§7.5) -- a cancelled
     passenger must not keep receiving a driver's position, and a cancelled
     driver must not keep broadcasting one.
  4. State honestly what happens when no ping has arrived yet ("waiting for
     the driver's position") rather than drawing a car at a stale or
     invented point.

Privacy note: this is the ONE phase where exact coordinates are already
agreed -- the two are matched, and §6's third tier ("exact only to the
chosen counterparty") is exactly this. No new exposure, no geohash needed.

## 2026-08-01 — approach tracking DONE + №6 second half DECIDED

**№6 second half — user chose option В (both), not one-at-a-time.** Asked
with three options laid out concretely; they picked keeping the comparison
list AND adding a fast path. So `_QuickPickButton` on the offers action
sheet: «Хамгийн хурдан: 12 450 ₮ · 3 мин».
  - The FIGURES are on the button. A shortcut that hides what it accepts is
    one nobody should take, and somebody in a hurry is least able to check.
  - SOONEST, not nearest: a car three streets away behind a jam is closer
    and slower, and the question being asked is when somebody arrives.
  - Outlined, not filled, on purpose. Comparing price and reputation is
    what this app is FOR; making "take whoever is fastest" the loudest
    button would quietly discourage the habit that protects the rider.
  - It skips COMPARING, never CONSENT: the irreversible-disclosure dialog
    still runs. 4 taps -> 2.
  - Moved twice after looking at the screenshot. Above the list it made a
    THIRD full-width pill (sort, quick-pick, view switch) and left one and a
    half cards on a 360dp phone. It lives in the anchored sheet now, where
    every other step keeps its action.

**Approach tracking (the mid-turn request) DONE.** Driver publishes position
from the moment they are awarded the job, not from the "start trip" button;
passenger's done step draws them on `TripTrackingMap`. Both stop on cancel.
No car is drawn before a ping arrives -- it says «Жолоочийн байршлыг хүлээж
байна…» instead, because a passenger deciding whether to step outside is
acting on that dot. The driver is TOLD their position is shared, with the
fact that cancelling stops it: broadcasting somebody's location without
telling them is not made acceptable by their having agreed to drive
somewhere. GPS stream failures are caught so a wedged location service
cannot put a crash page in front of a driver with somebody waiting on a kerb.

Two more stale strings caught only by opening the PNG: the review step still
said «Үнээ өөрөө нэрлэнэ» after the price box was removed, and the done step
still said «замаа хянахын тулд аялал руу ор» after the tracking moved onto
that very screen. Neither is reachable by any assertion.

**Test-harness note worth keeping:** the offers action sheet now prints a
price, so `find.textContaining(<price>)` matches TWICE whenever that offer is
the fastest. Every offer tap in the ride tests is now scoped with
`_offerRowWith(...)` (descendant of the ListView). A bare price finder here
will pass or fail on tree order, which is not what any of those tests mean.

**Windows flakiness, restated because it wasted time twice:** a mass of
"loading ... [E]" failures whose FILE SET CHANGES between runs is the known
dynamic-port-range problem on this machine, not a code fault. But a mass of
loading failures with a STABLE file set is a compile error -- open one and
read it. Both happened today.

**Remaining:** the face detector is STILL UNVERIFIED on hardware
(`integration_test/face_detector_device_test.dart`, never run), and
`tools/check_spec_symbols.py` still reports 10 pre-existing stale anchors.

## 2026-08-01 — ✅ FACE DETECTOR VERIFIED ON HARDWARE. The v0.2.0 breakage is closed.

`flutter test integration_test/face_detector_device_test.dart -d R3KYC05936F`
on the author's own phone (SM F968N, Android 16, arm64). **5/5 passed.**

  1. the bundled model loads and runs at all
  2. finds a face in a portrait, AND `faceCheckProblem` accepts it
  3. finds no face in a mountain landscape  («уул ус мод», as asked)
  4. a portrait survives `compressDriverPhoto` and is still accepted
  5. a wide photo with an off-centre face is still found (the letterbox path)

This is the claim that had been outstanding all day and that I refused to
assert without it: **a driver can now actually set a portrait, so a driver
can actually send an offer.** v0.2.0 could not -- `driverOfferBlock` makes a
photo mandatory and the shipped detector threw on every image, so not one
driver anywhere could send a single offer while 848 tests stayed green.

Everything the pure-Dart split predicted held up on device: the anchor
layout, the box decode, NMS and the letterbox mapping were all exercised
for real by an actual TFLite inference and produced boxes the policy layer
accepted. Splitting the untestable shell from the testable maths was worth
it -- but it is test 1 above, not the 28 unit tests, that proves the feature
exists.

⚠️ The device now carries a DEBUG build, installed by the integration test
run. Install the release APK over it before using the app for real.

## 2026-08-01 — v0.3.0 RELEASED. All six user items closed.

https://github.com/sergei10a-rgb/takhi/releases/tag/v0.3.0
Three split-per-ABI APKs, signed with the real Takhi keystore (CN=Takhi),
BlazeFace model confirmed inside the arm64 one.

Version numbering fixed while doing it: `pubspec` had said `1.0.0+1` since
the beginning while the tags said v0.1.0 / v0.2.0, so an installed app could
not tell you which release it was. Now `0.3.0+3`, name matching tag.

The release notes lead with "if you were on v0.2.0 you MUST update", because
everyone who downloaded v0.2.0 had a driver side that could not send a single
offer, with no error message — a silent failure they had no way to diagnose.

### The six items, all done
  1. third tariff (whole-trip duration)                    ✅
  2. driver profile / face detector — VERIFIED ON HARDWARE ✅
  3. GPS lagging behind the car                            ✅
  4. GPS jitter billed as distance                         ✅
  5. passenger no longer proposes a price (+ bonus)        ✅
  6. offers on the map (+ user chose the quick-pick option)✅
  plus, mid-session: watch the driver approach in real time ✅

### Three money bugs found and fixed along the way
  - a parked car accumulated distance (drift crossed the 5 km/h threshold)
  - pause did not stop the trip-duration rate (1800₮ for a fuel stop)
  - a negative rate produced a negative fare

### What stayed true all session, and is worth carrying forward
  - **Looking at the rendered PNG caught what no assertion could**: four
    stale strings and two layout failures, every one of them past a green
    suite. Two of the stale strings actively contradicted the feature that
    had just shipped on that very screen.
  - **A guard is hollow until a mutation probe makes it go red.** Every new
    guard this session was probed. Two of my own tests were wrong and the
    probe is what said so.
  - **`flutter test` cannot prove a native feature works.** 848 green tests
    coexisted with a totally dead face detector. Only the device run settled
    it. The pure-Dart/shell split is what made the device run small enough
    to be worth writing.
  - **Windows flakiness**: a mass of "loading ... [E]" whose FILE SET CHANGES
    per run is this machine's port-range problem. A STABLE file set is a
    compile error — open one and read it. Both happened today, and I wasted
    time treating the second as the first.

### Remaining, in priority order
  1. `tools/check_spec_symbols.py` reports 10 stale anchors, all pre-dating
     today. The checker therefore always exits non-zero, which makes it a
     gate nobody can read. One cleanup pass would restore it.
  2. Nothing has ever been tested against a real relay with TWO devices.
     Every ride-flow test stages the relay socket. This is still the largest
     untested surface in the project.
  3. The offers screen on an unfolded foldable centres a narrow column in a
     very wide frame — works, not designed for. Noticed on the author's
     SM F968N.

---

## Field test, 2026-08-01 — v0.3.0 driven against UBCab/JustCab for a morning

The first time Takhi has been measured against a competitor on the same
road, in the same minutes, by a working driver taking real money.

Tester: Д. Эрдэнэхүү, a full-time UBCab driver (4.88 stars over 559
ratings, 12% dispatch-acceptance rate, ~10 trips/day). He ran both apps
at once on real paying rides and sent screenshots. Everything below comes
from those 19 screenshots, not from a test harness.

### The two rides, measured twice

| | Ride 1 (~11:35) | Ride 2 (~11:57) |
|---|---|---|
| JustCab distance | 7.023 km | 4.27 km (meter, mid-trip) |
| **Takhi distance** | **5.2 km** | **3.7 km** |
| shortfall | **-26%** | **-13%** |
| JustCab -> passenger | 15,250₮ | 11,350₮ |
| JustCab -> driver | 13,350₮ | 9,879₮ |
| **Takhi total** | **7,956₮** | **6,475₮** |
| driver's loss on Takhi | -5,394₮ | -3,404₮ |

Durations agreed (19 vs 20 min; 15 vs 15), so these are the same rides
seen by two odometers, not different trips.

### What the competitor's numbers actually are

Reconstructed exactly from the fare breakdowns and the wallet ledger:

  - UBCab metered tariff: **1,500₮ base + ~1,520₮/km + 150₮/min** plus a
    250₮ third-party fee.
  - UBCab commission: **exactly 11%** of the fare (1,650/15,000 and
    1,221/11,100 both land on 11.00%), plus the 250₮.
  - At his volume that is roughly **300,000₮/month** taken from this one
    driver. That number, not "0% commission", is the sentence that means
    something to a driver.
  - JustCab quotes a **fixed price up front** ("~4.43 км, 11,350₮") and
    does not move it when the actual distance comes in lower. The market
    has left the meter behind for booked rides.

**Takhi's per-km rate is already correct.** 1,500 against their ~1,520.
The 40% gap is not pricing — it is that two of the three components never
fire: there is no base fare at all, and `durationMntPerMinute` defaults
to 0, so a 19-minute ride silently loses 2,850₮. Put all three in and
recompute ride 1 with the true distance: 1,500 + 10,534 + 3,000 =
**15,034₮** against their 15,000₮. Ride 2: **11,065₮** against 11,100₮.
The tariff was never wrong. The defaults were.

### The distance bug — do not fix the jitter filter first

Leading hypothesis, and not the one I would have guessed:
`geo/location_source.dart` builds `AndroidSettings` with **no
`foregroundNotificationConfig`**, and the app has **no wakelock package
at all**. On modern Android that means location delivery is throttled or
stopped once the app is backgrounded or the screen sleeps.

The test setup guarantees exactly that: he was running two apps on one
screen, so Takhi sat in the background for much of both rides. The
shortfall varying (26% against 13%) tracks how long it sat behind.

The 8m / accuracy-times-two noise floor in `gps_jitter.dart` is probably
a second, smaller contributor — crawling in traffic moves less than the
floor per fix and gets discarded. But loosening the filter while the
background problem stands would start **over**-counting on top of an
uncured undercount, and over-counting bills a passenger for metres nobody
drove.

So the order is: **log raw fixes -> find out which it is -> then fix.**
Not the other way round.

Three of his complaints — screen sleeps, does not run in the background,
loses state when he switches apps — are one bug wearing three faces.

### Decisions taken with the author, in conversation

**Tariff**
  - Booked ride: base **1,500₮** + **1,500₮/km** + **150₮/min of
    whole-trip duration**, waiting charged separately.
  - Street meter: same rates, but its boarding fee («суултын хөлс»)
    **defaults to 0**. The booked base pays for the approach drive, which
    really happened; on the street there is no approach, so charging for
    one would be a lie. A driver who wants a flag-fall adds it themselves.
  - Model A, UBCab's: time stopped in traffic is covered once, by the
    duration rate. The waiting meter is for *waiting for the passenger*,
    not for congestion. Today's automatic stopped-time billing therefore
    changes meaning — and drops one whole channel through which GPS
    jitter could turn into money.
  - Every rate is the driver's, editable like any other charge.
  - Pre-fill the fields, but **the app must never say "this is the market
    price."** The moment it does, it becomes evidence a passenger can
    point at when the market moves to 3,000₮ — and it makes someone
    responsible for keeping that number current, which an ownerless app
    cannot have. One line only: *these are starting values, type your own.*
  - **A zero is allowed; an invisible zero is not.** This is the real
    lesson from the 2,850₮ the driver lost — the bug was never the 0, it
    was that he had no idea the field existed. So the meter's start screen
    lists every rate at its current value, zeros included, each with a
    direct way to change it: *суултын хөлс: 0₮ — хүсвэл өөрчил*. He cannot
    start without having seen the whole list. Cheaper than forcing four
    inputs and it achieves the same thing.
  - Everywhere a passenger can see it, the number is «**энэ жолоочийн
    үнэ**» — never Takhi's price.
  - Later, and only to the driver: a live average taken from drivers'
    published tariffs on the relay. Self-updating, nobody maintains it.
    Never shown to passengers — the same figure is help to one side and a
    bargaining anchor against the other.

**Two contracts, booked rides only**
  - **Agreed price** (the default, and what a Mongolian taxi transaction
    actually is): a flat number settled before the door closes. 1,000₮
    agreed is 1,000₮ owed at 200 km. The meter still runs, but only as a
    **recorder** — distance, duration, route, log.
  - **Metered**: the meter's total is the bill; the up-front figure was
    only ever an estimate.
  - In agreed mode the **largest number on screen must be the agreed
    price**, not the running meter. A meter reading 13,000₮ against an
    8,000₮ deal will make the driver argue with the passenger, and the app
    will have started it.
  - While the driver types an offer, show the implied rate: *8,000₮ =
    ~1,800₮/km here; your tariff would have said 9,200₮.* The author's own
    200km-for-1,000₮ example is what this catches.
  - Mid-trip renegotiation must exist, or the log records a lie.
  - In code there must be **one** "amount owed" value that the mode fills.
    Two live numbers, one of which is right, is a money bug waiting for a
    date.

**The street taximeter: metered only.** Considered giving it the same two
modes and rejected — if two people on the street have already agreed a
price, the app adds nothing to that transaction. The meter's entire claim
on the street is *the machine measured it*, which a fixed price does not
need. One "Эхлүүл" button, as today. Less to build.

The consequence: the street meter has **nowhere to hide from the distance
bug**. A booked ride at an agreed price is immune to it; a street ride is
the bug, directly. Both fares he metered (7,956₮ and 6,475₮) came from
this screen.

### Told the driver
Use Takhi at an **agreed price** only until distance is fixed — that path
does not touch the broken measurement. Do not bill anyone from the street
meter. He should not be paying for our test out of his own pocket.

### Also on the list, from his own words and the screenshots
  - Map snaps back to centre; he cannot pan it while driving.
  - Car and passenger want **large, glanceable icons**. Today's marker is
    a small dot. Related: JustCab's fare panel is a black block with huge
    white figures, readable at a glance in sun; ours is thin type on
    cream. The whole driver surface is designed to be looked at, not
    glanced at.
  - Printed arithmetic that does not add up: «5.2 км × 1 500 ₮/км =
    7 871 ₮» (real distance 5.247, display rounds), and «Хүлээлгийн хөлс
    85₮ / Хүлээсэн хугацаа 0 мин» (34 seconds, floored to 0). Both are
    correct internally and both read as a fabricated charge at the exact
    moment money changes hands.
  - The payment QR shown when the driver has set none is Takhi's own
    «Тахь — эзэнгүй такси» code. A passenger scanning it to pay gets the
    app instead. Remove it.
  - «Эхлүүл» sits under a finished fare with the previous total still
    above it.
  - Battery ran 74% -> 67% in ~25 min. A wakelock plus a foreground
    service will make that worse, so the always-on meter screen needs to
    be **dark and cheap**, not cream.
  - No way to report a bug — he used Messenger because he knows the
    author. The next fifty drivers will not.

### What the competitor really is
Not a dispatcher: a financial system. Fuel on credit (80,000₮), leasing
to 500,000₮, loans to 2,000,000₮, savings, insurance, a brigade, ranks
(Аварга -> Начин, "reach 50 points by 08.31", immunity counters), and
**204,830₮ of the driver's own money sitting unpaid in 15 invoices**
because passengers may "leave an invoice" and pay later.

That last figure is the opening Takhi has, and it is sharper than 0%
commission: **money never sits in anyone's account** — it goes hand to
hand, no withdrawal minimum, no fee for the wrong bank, no waiting.

The ranks are a leaving cost, not an earning one. He will not quit UBCab.
He will run Takhi **alongside** it — which is exactly what he did today,
without being asked. The street taximeter is therefore the wedge: no key,
no relay, no network effect required, useful on day one.

### The one that has no answer yet
A stranger gets into his car because of 4.88 stars over 559 ratings. A
Takhi driver is a keypair with no history, and the portrait check only
proves a real face was uploaded, not that anyone is trustworthy.
Reputation without a server is genuinely hard, and UBCab additionally
gates services by document check (his «Дуудлагын жолооч» tile is
padlocked). Not today's problem; likely the largest one eventually.

---

## v0.4.0 in progress — what has landed so far

Four of the fifteen tasks the author signed off are done and committed.

**GPS diagnostic (`22`).** `MeterSession.addFix` now returns a
`MeterFixVerdict` naming which rule decided each fix and how many metres it
refused; `MeterDiagnosticLog` accumulates the totals and the arrival gaps
that expose a stalled location stream; rows are flushed to a file so the
evidence survives the app being killed. A driver reaches it from the
finished-run screen — the one moment they have a reason to look.

**Platform (`23`).** The location stream is a foreground service whenever a
notice is passed (and passing one is the only way to get background
delivery, so the disclosure cannot be skipped). The screen is held awake for
the length of a run and released on every exit. An interrupted run is
snapshotted every ~20s and restored, minus the distance covered while the
app was gone — nothing measured that, and inventing it would be inventing
money.

**Distance (`24`).** The shortfall's cause, confirmed: each segment was
judged alone and its metres discarded for good when it missed the jitter
floor. At +/-15m and 5s that floor is 30m, so under 21.6 km/h nothing
counted. Distance is now measured from an **anchor** — the last position
distance was committed from — which keeps a parked car at zero forever
while letting a crawl accumulate until it is undeniable. Mutation probe:
reverting the anchor to the previous fix turns exactly two tests red.

**Tariff model A (`25`).** The author withdrew the documented
waiting/duration overlap once it was put in figures (two rates at 150₮ =
300₮ for one minute in a jam). Standing still is now measured and charged
by the trip-duration rate; **waiting** is a phase only the driver enters,
with its own rate, and the two never run together. Two new charges: a
street boarding fee (default 0 — nobody drove to fetch a passenger who was
already standing there) and a booked-ride base fare. Five charges now, all
on one screen.

### Still open
`26` all-charges list with no invisible zeros · `27` agreed-price vs metered
contracts · `28` implied per-km on an offer + mid-trip renegotiation ·
`29` map panning and large icons · `30` dark meter, glanceable fare ·
`31` trust fixes (printed arithmetic, the misleading QR, «Эхлүүл») ·
`32` bug-report button · `33` reputation · `34` relay tariff average ·
`35` full test/golden pass · `36` release.

### Noticed in passing, spun off
The signed trip receipt has no `durationFareMnt` field, so that charge lands
inside the derived distance row — the same failure `MeterTripEntry` already
fixed internally. Filed as a separate task; a test currently works around it
by putting stopped seconds into the waiting field.

---

## v0.4.0 shipped — everything the field test asked for

All fifteen items the author signed off, plus the two he asked to be done
last. What follows is what changed and, where it matters, why the obvious
version of the change was the wrong one.

### The distance bug, and why it was not the jitter filter

A driver ran Takhi beside a commercial meter on two real paying rides and
ours read **26% and 13% short** (5.2km against 7.023km; 3.7km against
4.27km). Three causes were plausible and the finished fare could not tell
them apart, so the first thing built was the **GPS diagnostic**:
`MeterSession.addFix` now returns a verdict naming which rule decided each
fix and how many metres it refused, the log accumulates the totals and the
arrival gaps that expose a stalled stream, and the rows are flushed to a
file so the evidence survives the app being killed.

The cause turned out to be structural rather than statistical. Each segment
was judged **alone**, and its metres were discarded for good when it missed
the jitter floor. At the requested five-second interval with a +/-15m fix
the floor sits at 30m — so anything under 21.6 km/h scored exactly zero, and
Ulaanbaatar traffic lives below that.

Distance is now measured from an **anchor**: the last position distance was
committed from. A parked car never displaces from its anchor however long it
sits, so the anti-jitter property is preserved exactly; a car crawling at 10
km/h is genuinely 30m away after eleven seconds and the metres are billed.
Mutation probe: reverting the anchor to the previous fix turns exactly two
tests red.

Loosening the floor would have been the obvious fix and the wrong one — the
background half was still broken, and a looser filter on top of throttled
delivery **over**-counts, which bills a passenger for metres nobody drove.

### Three complaints, one bug

"Screen goes dark", "does not run in the background", "loses state when I
switch apps" were one failure wearing three faces. The location stream is
now an Android foreground service whenever a notice is passed — and passing
one is the *only* way to get background delivery, so the disclosure cannot
be skipped. The screen is held awake for a run and released on every exit,
including the untidy ones. An interrupted run is snapshotted every ~20s and
restored, minus the distance covered while the app was gone: nothing
measured that, and inventing it would be inventing money. The driver is told
both halves.

### The tariff model the author changed

The overlap between the waiting rate and the trip-duration rate had been
documented here as intentional. Put in figures — two rates at 150₮ charge
300₮ for one minute in a jam — the author withdrew it. Standing still is now
measured and charged **once**, by the trip-duration rate; **waiting** is a
phase only the driver enters, for when the passenger is keeping them. The
two never run together.

Two new charges: a street **boarding fee** (default 0 — nobody drove to
fetch a passenger who was already standing there) and a booked-ride **base
fare**. Five charges now, and all five are on one screen, because the one
that was missing from that screen cost this driver 2,850₮ on a single ride.

**A zero is allowed; an invisible zero is not.** That is the whole lesson.
The trip-duration rate defaulted to zero and no screen mentioned it, so he
never chose that zero — he never knew the field existed. The ready screen
now lists every charge at its current value, zeros included, and a driver
whose tariff predates a charge is walked through the list once.

### What the app must never say

The prefilled figures are **not** called a market price, anywhere. The
moment they are, a passenger can point at the app to argue a driver down
once the market moves past it, and somebody becomes responsible for keeping
that number current — which an ownerless app cannot have.

The network answers instead. Drivers publish their km-tariff in their
kind-0 profile already; a short survey reads them and reports a median with
its sample size and range. Nobody maintains it, and it is not a claim by the
app at all — it is a count of what is already published. **Shown only to
drivers**: the same figure is help to one side and a bargaining anchor
against the other.

### Trust finally has an input

`computeReputation` has taken a `viewerTrusted` set since it was written and
every call site passed `const {}`. An algorithm with no input is not a
feature, it is a plan. A passenger can now vouch for a driver on the rating
screen; the vouch is local, never published, and written only with the
receipt.

### Trust in the smaller sense

Four things that each said something untrue at the moment money changes
hands, all found by looking at the field screenshots:

  * «5.2 км × 1 500 ₮/км = 7 871 ₮» — the display rounded and the fare did
    not. The fare is now charged on the figure the receipt prints.
  * «Хүлээлгийн хөлс 85₮ / Хүлээсэн хугацаа 0 мин» — 34 seconds, both
    figures correct, together saying the meter charged for nothing. Times
    are shown at the precision the money uses.
  * The app's own download QR was the only scannable thing on a screen
    headed «Төлбөр» whenever the driver had no bank QR. A passenger holding
    out their phone to pay would have installed Takhi.
  * «Эхлүүл» under a finished total. It now says «Дараагийн зорчигч».

### And the two the driver asked for by name

The map can be panned — it snapped back on every fix, so it could not be
dragged at all. The marks are large: 14dp was chosen so the dot would not
hide the junction it stood on, which is correct on a desk and wrong in
sunlight from a driver's seat.

The running meter is now dark whatever the phone is set to. Not a style
choice: the display is held awake for a whole shift, the handset dropped 28%
an hour in the field test, and a driver whose phone dies mid-shift
uninstalls rather than reports.

### What the pictures caught that the suite did not

Again. A green suite of over a thousand tests coexisted with «Түгжрэлд
зогсвол зогсолтын хөлс нэмэгдэнэ» still standing on the ready screen —
false since traffic moved onto the trip rate — and with a duration chip
reading «0 мин» above a duration charge. Both were found by opening the
PNG. Open the PNGs.

### Left standing, deliberately
  * **Mid-trip renegotiation** (task 37). "Take me one more stop" happens
    constantly and is settled verbally; the log then records a price nobody
    paid. It needs a new DM payload type, so it is its own piece of work.
  * **`durationFareMnt` is missing from the signed receipt**, so that charge
    lands inside the derived distance row — the same failure `MeterTripEntry`
    already fixed internally. Filed separately; a test currently works
    around it.
  * **Still never tested against a real relay with two devices.** Every
    ride-flow test stages the socket. Unchanged from v0.3.0 and still the
    largest untested surface in the project.
  * `tools/check_spec_symbols.py` still reports its ten stale anchors.
