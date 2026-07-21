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

## Plan 3 — NIP-17 + ride matching + map (docs/.../2026-07-21-takhi-ride-matching.md) — AUTHORING
Regrouped: Plan 3 = NIP-17 layer + request/offer/match/handoff + map selection.
Plan 4 = active trip (live loc, dual receipt, reputation) + taximeter + payment QR.
Plan 5 = P2P calling + safety (share/SOS) + polish + Android APK.
