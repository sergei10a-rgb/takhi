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

## Plan 5 — P2P calling + safety + polish + Android APK (docs/.../2026-07-22-takhi-calling-safety-ship.md) — AUTHORED, building next
10 tasks: helper announcement (kind 30178), call signaling payloads, ICE config+helper directory, CallEngine abstraction,
fallback decision+phone exchange, voice-note fallback, CallService+CallScreen+ActiveTripView wiring, trip-share (throwaway key+static page),
SOS (tel:/sms: no new perms), polish+ship (APK release signing, PROTOCOL/FORKING/HELPER/LICENSE/README). Findings: AndroidManifest missing INTERNET (fix Task 4), release debug-signs (fix Task 10).
9 tasks: NIP-17 giftwrap (protocol), ride DM codec, RideDmChannel, RideRequestService, DriverInboxService,
offer+reputation ranking, HandoffService+tripId, map (flutter_map/OSM), ride screens. New kinds: seal=13, giftwrap=1059, rumor kRumorKindRideDm=20179.
Regrouped: Plan 3 = NIP-17 layer + request/offer/match/handoff + map selection.
Plan 4 = active trip (live loc, dual receipt, reputation) + taximeter + payment QR.
Plan 5 = P2P calling + safety (share/SOS) + polish + Android APK.
