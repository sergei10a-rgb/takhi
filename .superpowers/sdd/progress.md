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

## STATUS: ALL 5 PLANS + completion COMPLETE. App fully matches spec MVP. Close-out: merge build→main → save memory → deliver.
10 tasks: helper announcement (kind 30178), call signaling payloads, ICE config+helper directory, CallEngine abstraction,
fallback decision+phone exchange, voice-note fallback, CallService+CallScreen+ActiveTripView wiring, trip-share (throwaway key+static page),
SOS (tel:/sms: no new perms), polish+ship (APK release signing, PROTOCOL/FORKING/HELPER/LICENSE/README). Findings: AndroidManifest missing INTERNET (fix Task 4), release debug-signs (fix Task 10).
9 tasks: NIP-17 giftwrap (protocol), ride DM codec, RideDmChannel, RideRequestService, DriverInboxService,
offer+reputation ranking, HandoffService+tripId, map (flutter_map/OSM), ride screens. New kinds: seal=13, giftwrap=1059, rumor kRumorKindRideDm=20179.
Regrouped: Plan 3 = NIP-17 layer + request/offer/match/handoff + map selection.
Plan 4 = active trip (live loc, dual receipt, reputation) + taximeter + payment QR.
Plan 5 = P2P calling + safety (share/SOS) + polish + Android APK.
