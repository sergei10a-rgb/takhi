// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:share_plus/share_plus.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../call/call_providers.dart';
import '../call/call_screen.dart';
import '../call/voice_note_service.dart' show ReceivedVoiceNote;
import '../config/city_config.dart';
import '../device/screen_awake.dart';
import '../geo/geo_providers.dart';
import '../geo/location_source.dart';
import '../meter/fare_calc.dart';
import '../meter/meter_providers.dart';
import '../geo/gps_fix.dart';
import '../identity/identity_service.dart' show Identity;
import '../identity/identity_state.dart';
import '../identity/short_pubkey.dart';
import '../l10n/app_localizations.dart';
import '../map/trip_tracking_map.dart';
import '../meter/meter_session.dart';
import '../meter/money_format.dart';
import '../nostr/relay_pool_provider.dart' show defaultRelayUrls;
import '../payment/driver_qr_display.dart';
import '../safety/share_session.dart';
import '../safety/sos_button.dart';
import '../theme/takhi_theme.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/driver_portrait.dart';
import '../widgets/info_chip.dart';
import '../widgets/labeled_field.dart';
import '../widgets/location_permission_denied_view.dart';
import '../widgets/menu_row.dart';
import '../widgets/notice_card.dart';
import '../widgets/person_row.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'ride_providers.dart';
import 'trip_phase.dart';
import 'trip_role.dart';
import 'trip_status_service.dart' show ReceivedTripStatus;

/// Throttle for `LiveLocationChannel.send`: only every 2nd fix is forwarded
/// to the counterparty (spec §6's 5-10s cadence hint; `LocationSource`
/// itself has no fixed interval guarantee, so counting fixes here is a
/// simpler, deterministic-in-tests substitute for a wall-clock `Timer`).
const _sendEveryNthFix = 2;

/// Ceiling on the tracking sheet's *content*, as a fraction of the screen.
///
/// The sheet hugs its content and its content is a short fixed list, so at
/// the default text scale it never comes near this. At 1.5x-2x scale it
/// would otherwise grow past the top of the screen and take the map with it;
/// past this fraction the content scrolls inside the sheet instead, which is
/// the bounded-scrollable shape [TakhiSheet] documents. Same value home uses,
/// so the two sheets behave identically under accessibility text sizes.
const _kSheetContentMaxFraction = 0.72;

/// Glyph size of one rating star.
///
/// Far larger than an ordinary icon on purpose: this row is the entire
/// control on its screen, it is tapped once and never again, and a rating
/// nobody can hit accurately is reputation data nobody can trust. The
/// `IconButton` around each one still pads out to [TakhiTouch.minTarget].
const _kStarGlyphSize = 32.0;

/// Glyph inside a voice-note chip. Matched to [TakhiType.label]'s cap
/// height so the play mark and the duration sit on one optical line.
const _kVoiceNoteGlyphSize = 15.0;

enum _ActiveTripStep { tracking, fareConfirm, rating, done }

/// The shared in-trip screen (spec §7.1 steps 5-6): live position sharing,
/// driver-initiated phase signaling, then a rating step that publishes
/// this device's own trip receipt. Composed as a step inside
/// `PassengerRidePage`/`DriverInboxPage`'s own state machines (Task 9) --
/// this widget owns no go_router route of its own.
class ActiveTripView extends ConsumerStatefulWidget {
  final TripRole role;
  final String tripId;
  final String counterpartyPubHex;
  final int agreedPriceMnt;

  /// The counterparty's phone number, when known -- only the driver side
  /// ever has this (it arrives on `RideHandoffPayload.phone`, Plan 5 Task
  /// 5); `PassengerRidePage` never passes it, since the handoff is not
  /// symmetric (Task 5's "Deliberate scope boundary"). Feeds both the
  /// call button's phone-fallback offer and `IncomingCallListener`.
  final String? counterpartyPhone;

  /// The other person's овог and нэр, and their face.
  ///
  /// Asymmetric for the same reason [counterpartyPhone] is, only the other
  /// way round: these ride on the driver's *offer*
  /// (`RideOfferPayload.driverFamilyName`/`driverPhotoJpegBase64`), so the
  /// passenger side has them for the whole trip and the driver side never
  /// does. `null` on both counts is what every trip looked like before this
  /// existed, and is still what a driver's screen shows -- the row then falls
  /// back to naming which *side* the other person is.
  ///
  /// The photograph is **not proof of identity** (see [DriverPortrait]): the
  /// sending device checked only that a human face is in it. That is why the
  /// enlarged view carries the caveat in words rather than this screen
  /// implying a verified driver.
  final String? counterpartyName;
  final Uint8List? counterpartyPhotoJpeg;

  /// The driver's own km-tariff (spec §7.2 "GPS таксиметр горим"),
  /// present only when the selected `RideOfferPayload` carried one --
  /// `null` (the default) is a plain fixed-price trip, using
  /// [agreedPriceMnt] throughout exactly as before this field existed.
  /// Non-null switches this whole view into metered mode: both sides show
  /// a live running fare computed from their own GPS track, the driver
  /// reports the GPS-computed final fare on "Аялал дууслаа" (`_endTrip`),
  /// and the passenger must explicitly confirm that fare (`fareConfirm`
  /// step) before a trip receipt is published -- declining leaves the
  /// receipt unpaired, same as never tapping submit. There is
  /// deliberately no separate "pricing mode" enum: see
  /// `RideOfferPayload.kmTariffMnt`'s doc comment for why its nullability
  /// alone carries this decision end to end.
  final int? kmTariffMnt;

  /// The driver's waiting rate (spec §7.4), carried on the same selected
  /// offer as [kmTariffMnt]. `null`/absent means waiting costs nothing —
  /// what a fixed-price trip, and any trip agreed with a client built
  /// before waiting fares existed, both amount to. Only meaningful
  /// alongside a non-null [kmTariffMnt]: a fixed price is a fixed price
  /// however long the trip sits in traffic.
  final int? waitTariffMntPerMinute;

  /// The driver's trip-duration rate, carried on the same selected offer as
  /// [kmTariffMnt]: every minute between the first GPS fix and the last is
  /// billed at it, moving or stopped. `null`/absent means the trip's
  /// duration costs nothing -- a fixed-price trip, or one agreed with a
  /// client built before this rate existed.
  ///
  /// Overlaps [waitTariffMntPerMinute] deliberately where a driver set both
  /// (author's ruling, 2026-08-01): the seconds the car stood still are
  /// inside the duration too, and get charged under both rates. Nothing here
  /// reconciles them -- which combination to offer is the driver's own
  /// commercial decision, and the passenger saw both figures on the offer
  /// they picked.
  final int? durationTariffMntPerMinute;

  /// Fires the moment this trip has nothing left to lose by being left:
  /// its receipt is published (or was explicitly declined) and this view
  /// has reached its final step. Host pages guard the back gesture for as
  /// long as a trip is in flight -- they own the route, this widget does
  /// not -- and use this to drop that guard again, since confirming an
  /// exit from a "trip finished" screen would be pure noise. A host that
  /// passes nothing simply keeps whatever guard it started with.
  final VoidCallback? onTripSettled;

  /// Invoked by the final screen's "finish trip" button. Host pages use it
  /// to clear their own per-trip state and go back to whatever they show
  /// between trips. Without it that screen has no control at all -- the
  /// end of one trip became the end of the session -- so every host should
  /// pass one; the button is simply not rendered when none is given.
  final VoidCallback? onFinished;

  const ActiveTripView({
    super.key,
    required this.role,
    required this.tripId,
    required this.counterpartyPubHex,
    required this.agreedPriceMnt,
    this.counterpartyPhone,
    this.counterpartyName,
    this.counterpartyPhotoJpeg,
    this.kmTariffMnt,
    this.waitTariffMntPerMinute,
    this.durationTariffMntPerMinute,
    this.onTripSettled,
    this.onFinished,
  });

  @override
  ConsumerState<ActiveTripView> createState() => _ActiveTripViewState();
}

class _ActiveTripViewState extends ConsumerState<ActiveTripView> {
  _ActiveTripStep _step = _ActiveTripStep.tracking;
  TripPhase _phase = TripPhase.enRouteToPickup;

  /// The trip's own meter. A `MeterSession` rather than a bare
  /// `GpsTrackAccumulator` even in fixed-price mode, because its
  /// travelling/waiting split is what keeps a parked car's GPS jitter out
  /// of the distance this side records on its receipt — true whether or not
  /// anyone is billing by the kilometre. Created in [initState] because
  /// `widget` is not readable from a field initialiser.
  late final MeterSession _meter;

  final _commentController = TextEditingController();

  Identity? _identity;
  bool _locationPermissionDenied = false;
  int _fixCount = 0;
  int _selectedStars = 0;
  bool _submittingRating = false;

  /// The metered fare (spec §7.2), once known: set directly by [_endTrip]
  /// on the driver side (computed from this device's own GPS track), or
  /// copied from an incoming `ReceivedTripStatus.finalFareMnt` on the
  /// passenger side. Stays `null` for the entire trip in fixed-price mode
  /// (`widget.kmTariffMnt == null`) -- [_submitRating] falls back to
  /// `widget.agreedPriceMnt` whenever this is still null.
  int? _finalFareMnt;

  /// The waiting half of [_finalFareMnt] and the time behind it (spec
  /// §7.4), set from the same source on each side: measured here on the
  /// driver's, received on the passenger's. Both sides put these on their
  /// trip receipt, so the pair states one agreed breakdown rather than two
  /// nearly-equal ones. Null whenever [_finalFareMnt] is.
  int? _finalWaitingFareMnt;
  int? _finalWaitingSeconds;

  /// The trip-duration share of [_finalFareMnt] and the seconds behind it,
  /// travelling by the same route as the waiting pair above and kept apart
  /// from it for the reason `ActiveTripView.durationTariffMntPerMinute`
  /// gives: the two overlap, so adding them together would show a passenger
  /// a "time charge" that matches neither rate they were quoted.
  int? _finalDurationFareMnt;
  int? _finalDurationSeconds;

  /// Set only by [_declineFare] -- the passenger explicitly rejected the
  /// metered final fare (spec §7.2 "Татгалзвал баримт хосгүй үлдэнэ"), so
  /// [_DoneView] must show that outcome instead of the usual "receipt
  /// published" message, and no receipt is ever published for this side.
  bool _fareDeclined = false;

  /// See [ActiveTripView.counterpartyPhone]'s doc comment -- only
  /// non-null on the driver side, and only when the passenger actually
  /// shared a number at handoff time.
  String? _counterpartyPhone;

  /// Set the moment the user first taps the share button (Task 8) --
  /// null until then, since sharing is opt-in per trip, never automatic.
  ShareSession? _shareSession;

  ll.LatLng? _selfPosition;
  ll.LatLng? _counterpartyPosition;

  /// Every voice note received for this trip (spec §7.3-③, the calling
  /// fallback chain's last rung) -- Plan 5 review CRITICAL-3 fix: before
  /// this, `VoiceNoteService.watchVoiceNotes`/`VoiceNotePlayer` were never
  /// wired into any screen, so sending worked but the recipient had no
  /// way to know a note had arrived, let alone play it back.
  final List<ReceivedVoiceNote> _receivedVoiceNotes = [];

  /// The index into [_receivedVoiceNotes] currently playing, or `null`
  /// when nothing is -- drives the play/stop icon per note in
  /// [_VoiceNoteBanner].
  int? _playingVoiceNoteIndex;

  /// The wakelock this view took, held rather than re-read — see
  /// `_cancelSubscriptions`, which runs from `dispose`.
  ScreenAwake? _heldScreen;

  StreamSubscription<GpsFix>? _gpsSubscription;
  StreamSubscription<LiveLocation>? _liveLocationSubscription;
  StreamSubscription<ReceivedTripStatus>? _statusSubscription;
  StreamSubscription<ReceivedVoiceNote>? _voiceNoteSubscription;

  @override
  void initState() {
    super.initState();
    _meter = MeterSession(
      // Zero in fixed-price mode: nothing reads the meter's fare there, and
      // a rate of zero is the honest stand-in for "this trip is not billed
      // by the meter" -- see `ActiveTripView.kmTariffMnt`.
      mntPerKm: widget.kmTariffMnt ?? 0,
      waitTariffMntPerMinute: widget.waitTariffMntPerMinute ?? 0,
      durationTariffMntPerMinute: widget.durationTariffMntPerMinute ?? 0,
    );
    // Warms up the live helper-TURN accumulator (`helperDirectoryProvider`,
    // Plan 5 Task 3/7's fallback-chain fix) the moment a trip goes active
    // -- `CallScreen._startCall` only ever reads whatever it has already
    // accumulated by call time (ICE servers are fixed at `CallEngine`
    // construction, see `ice_servers.dart`'s doc comment), so starting the
    // relay subscription here, rather than lazily the moment the call
    // button is tapped, gives real kind-30178 announcements time to
    // actually arrive over the network first. Independent of identity/
    // location permission, so it needs none of the `.then()` chaining
    // below.
    ref.read(helperDirectoryProvider);
    _counterpartyPhone = widget.role == TripRole.driver
        ? widget.counterpartyPhone
        : null;
    // `currentIdentityProvider` is a `FutureProvider` -- `.future` awaits
    // its creation/resolution regardless of whether anything has already
    // `ref.watch`ed it, mirroring `DriverInboxPage._DriverInboxPageState
    // .initState`'s exact reasoning.
    ref.read(currentIdentityProvider.future).then((identity) {
      if (identity == null || !mounted) return;
      _identity = identity;
      unawaited(_startTracking(identity));
    });
  }

  Future<void> _startTracking(Identity identity) async {
    // `LocationPermissionDeniedView`'s retry runs this method again, and
    // every assignment below overwrites its field -- so without cancelling
    // first, each retry stranded the previous set: `RelayPool.subscribe`'s
    // `StreamController.onCancel` never fires for a handle nobody holds
    // anymore, leaving an open relay `REQ` (and a second GPS listener,
    // double-counting distance into `_track`) for the app's remaining
    // lifetime.
    _cancelSubscriptions();
    // Only the passenger side listens for phase transitions -- the driver
    // side is the one calling `sendStatus` (spec §7.1 steps 5-6). Wired
    // before the location-permission `await` below (rather than after, as
    // in earlier revisions of this method) deliberately: phase-transition
    // delivery has nothing to do with location permission, and setting it
    // up synchronously -- in the same microtask as `initState`'s identity
    // resolution, before any `await` yields control -- guarantees this
    // subscription's relay `REQ` for kind 1059 (gift wrap), and the
    // voice-note subscription right after it below, are always sent
    // before `IncomingCallListener`'s own kind-1059 subscription (Plan 5
    // Task 7), which is wired from a sibling widget chained onto the same
    // identity future but with no internal `await` of its own. Without
    // this ordering, which subscription's `REQ` reaches the relay first
    // is a microtask race, and `active_trip_view_test.dart`'s existing
    // "grab the first/last kind-1059 subscription id" tests would flake.
    if (widget.role == TripRole.passenger) {
      _statusSubscription = ref
          .read(tripStatusServiceProvider)
          .watchStatus(identity.pubHex, identity.privHex)
          .where(
            (status) =>
                status.tripId == widget.tripId &&
                status.senderPubkey == widget.counterpartyPubHex,
          )
          .listen((status) {
            if (!mounted) return;
            setState(() => _phase = status.phase);
            if (status.phase == TripPhase.arrived) {
              if (status.finalFareMnt != null) {
                _finalFareMnt = status.finalFareMnt;
                // Taken together with the total, never independently: a
                // breakdown assembled half from the driver and half from
                // this device's own track would not be the breakdown either
                // side agreed to. Absent from an older client's status,
                // which simply means nothing was billed for waiting.
                _finalWaitingFareMnt = status.finalWaitingFareMnt ?? 0;
                _finalWaitingSeconds = status.finalWaitingSeconds ?? 0;
                // Same rule, same reason, for the third rate: absent from a
                // client built before trip-duration fares existed, and
                // absent is exactly zero there -- those trips charged
                // nothing for their duration.
                _finalDurationFareMnt = status.finalDurationFareMnt ?? 0;
                _finalDurationSeconds = status.finalDurationSeconds ?? 0;
              }
              _stopTrackingAndMoveToRating();
            }
          });
    }

    // Both roles can receive a voice note -- whichever side's WebRTC
    // attempt failed decides to record one (`CallScreen`'s fallback UI),
    // and the other side needs to see it regardless of whether they
    // currently have `CallScreen` open at all (that is the whole point of
    // this being the *last* rung of the fallback chain, spec §7.3-③).
    _voiceNoteSubscription = ref
        .read(voiceNoteServiceProvider)
        .watchVoiceNotes(identity.pubHex, identity.privHex)
        .where((received) => received.payload.tripId == widget.tripId)
        .listen((received) {
          if (!mounted) return;
          setState(() => _receivedVoiceNotes.add(received));
          final l = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.voiceNoteReceivedLabel)));
        });

    final granted = await ref.read(locationPermissionCheckProvider)();
    if (!mounted) return;
    if (!granted) {
      setState(() => _locationPermissionDenied = true);
      return;
    }
    setState(() => _locationPermissionDenied = false);

    final l = AppLocalizations.of(context)!;
    // Same reasoning as the taximeter's own subscription: a trip that is
    // being metered and shared has to keep measuring when the driver is in
    // the map app or the passenger has locked their phone. Without the
    // notice Android stops delivering fixes and the recorded distance
    // silently comes up short.
    _gpsSubscription = ref
        .read(locationSourceProvider)
        .watch(
          backgroundNotice: LocationBackgroundNotice(
            title: l.tripForegroundNoticeTitle,
            text: l.tripForegroundNoticeText,
            channelName: l.locationNoticeChannelName,
          ),
        )
        .listen((fix) => _onOwnFix(identity, fix));

    // A trip in progress is the other place a dark screen costs something:
    // the passenger is watching the car approach and the driver is watching
    // the route. Released in `_cancelSubscriptions`, which both the phase
    // transition and `dispose` funnel through.
    //
    // The instance is captured rather than re-read at release time: the
    // release path runs from `dispose`, where `ref` has already been torn
    // down and reading a provider throws.
    final screen = ref.read(screenAwakeProvider);
    _heldScreen = screen;
    unawaited(screen.keepOn());

    _liveLocationSubscription = ref
        .read(liveLocationChannelProvider)
        .watch(identity.pubHex, identity.privHex, widget.tripId)
        .listen((loc) {
          if (!mounted) return;
          setState(() => _counterpartyPosition = ll.LatLng(loc.lat, loc.lon));
        });
  }

  void _onOwnFix(Identity identity, GpsFix fix) {
    _meter.addFix(fix);
    _fixCount++;
    if (mounted) {
      setState(() => _selfPosition = ll.LatLng(fix.lat, fix.lon));
    }
    if (_fixCount % _sendEveryNthFix != 0) return;
    unawaited(
      ref
          .read(liveLocationChannelProvider)
          .send(
            senderPrivHex: identity.privHex,
            recipientPubHex: widget.counterpartyPubHex,
            tripId: widget.tripId,
            lat: fix.lat,
            lon: fix.lon,
            now: fix.timestampSeconds,
          ),
    );
    // Task 8: a second, identical copy addressed to the throwaway
    // share-session key, only once the user has actually tapped "share"
    // (see `_shareTrip` below) -- this is the entire mechanism by which
    // `docs/share/index.html` sees live position with no author server
    // in the loop (this task's own "How this stays server-less" note).
    final shareSession = _shareSession;
    if (shareSession != null) {
      unawaited(
        ref
            .read(liveLocationChannelProvider)
            .send(
              senderPrivHex: identity.privHex,
              recipientPubHex: shareSession.shareKeyPair.publicHex,
              tripId: widget.tripId,
              lat: fix.lat,
              lon: fix.lon,
              now: fix.timestampSeconds,
            ),
      );
    }
  }

  void _shareTrip() {
    final session = _shareSession ??= ShareSession();
    unawaited(Share.share(session.urlFor(widget.tripId, defaultRelayUrls)));
  }

  Future<void> _markPassengerBoarded() async {
    final identity = _identity;
    if (identity == null) return;
    setState(() => _phase = TripPhase.tripInProgress);
    await ref
        .read(tripStatusServiceProvider)
        .sendStatus(
          driverPrivHex: identity.privHex,
          passengerPubHex: widget.counterpartyPubHex,
          tripId: widget.tripId,
          phase: TripPhase.tripInProgress,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
  }

  Future<void> _endTrip() async {
    final identity = _identity;
    if (identity == null) return;
    setState(() => _phase = TripPhase.arrived);
    // Metered mode (spec §7.2): the fare is computed once, here, from this
    // device's -- the driver's -- own GPS track, and carried to the
    // passenger on the same status DM. `null` in fixed-price mode
    // (`widget.kmTariffMnt == null`), matching every trip built before
    // this field existed.
    final metered = widget.kmTariffMnt != null;
    final finalFareMnt = metered ? _meter.fareMnt : null;
    // The waiting half travels with the total so the passenger signs this
    // device's breakdown rather than deriving one from their own track,
    // which never agrees with the driver's to the second.
    final finalWaitingFareMnt = metered ? _meter.waitingFareMnt : null;
    final finalWaitingSeconds = metered ? _meter.waitingSeconds : null;
    // And the duration half, measured over the same track. Sent even when
    // the driver set no duration rate -- it is then a `0`, which is a
    // statement ("this trip's duration cost nothing") rather than the
    // silence an omitted field would be, and the confirm screen suppresses
    // the row on the figure, not on the field's presence.
    final finalDurationFareMnt = metered ? _meter.durationFareMnt : null;
    final finalDurationSeconds = metered ? _meter.durationSeconds : null;
    if (finalFareMnt != null) {
      _finalFareMnt = finalFareMnt;
      _finalWaitingFareMnt = finalWaitingFareMnt;
      _finalWaitingSeconds = finalWaitingSeconds;
      _finalDurationFareMnt = finalDurationFareMnt;
      _finalDurationSeconds = finalDurationSeconds;
    }
    await ref
        .read(tripStatusServiceProvider)
        .sendStatus(
          driverPrivHex: identity.privHex,
          passengerPubHex: widget.counterpartyPubHex,
          tripId: widget.tripId,
          phase: TripPhase.arrived,
          finalFareMnt: finalFareMnt,
          finalWaitingFareMnt: finalWaitingFareMnt,
          finalWaitingSeconds: finalWaitingSeconds,
          finalDurationFareMnt: finalDurationFareMnt,
          finalDurationSeconds: finalDurationSeconds,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
    _stopTrackingAndMoveToRating();
  }

  void _startCall() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          tripId: widget.tripId,
          counterpartyPubHex: widget.counterpartyPubHex,
          isCaller: true,
          counterpartyPhone: _counterpartyPhone,
        ),
      ),
    );
  }

  /// Toggles playback for `_receivedVoiceNotes[index]` through
  /// `voiceNotePlayerProvider` -- tapping the same note again while it is
  /// playing stops it instead of restarting it.
  Future<void> _togglePlayVoiceNote(int index) async {
    final player = ref.read(voiceNotePlayerProvider);
    if (_playingVoiceNoteIndex == index) {
      await player.stop();
      if (mounted) setState(() => _playingVoiceNoteIndex = null);
      return;
    }
    setState(() => _playingVoiceNoteIndex = index);
    await player.playBase64(_receivedVoiceNotes[index].payload.audioBase64);
  }

  /// Cancels every relay/GPS subscription this view owns and forgets the
  /// handles, so a later [_startTracking] can re-open them from scratch.
  /// Mirrors `PassengerRidePage`/`DriverInboxPage`'s own `dispose()`
  /// reasoning: `RelayPool.subscribe`'s `StreamController.onCancel`
  /// (relay_pool.dart) is what sends the relay its `CLOSE` frame, and it
  /// only ever fires through one of these handles.
  void _cancelSubscriptions() {
    unawaited(_gpsSubscription?.cancel());
    unawaited(_liveLocationSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_voiceNoteSubscription?.cancel());
    _gpsSubscription = null;
    _liveLocationSubscription = null;
    _statusSubscription = null;
    _voiceNoteSubscription = null;
    // Released here rather than only in `dispose`, because this is also the
    // teardown a phase transition uses: a trip that has reached its rating
    // step is over, and the screen should go dark on its own timetable from
    // that moment, not whenever the widget happens to be torn down.
    final screen = _heldScreen;
    if (screen != null) {
      _heldScreen = null;
      unawaited(screen.release());
    }
  }

  void _stopTrackingAndMoveToRating() {
    // Same teardown as `dispose`, just triggered by a phase transition
    // instead of the widget itself being torn down.
    _cancelSubscriptions();
    if (!mounted) return;
    // Only the passenger side gates on an explicit confirm (spec §7.2 "
    // Зорчигч дүнг баталж гарын үсэглэнэ") -- the driver already computed
    // and committed to `_finalFareMnt` themselves the moment they tapped
    // "Аялал дууслаа" (`_endTrip`), so they go straight to rating exactly
    // like fixed-price mode.
    final needsFareConfirm =
        widget.role == TripRole.passenger && _finalFareMnt != null;
    setState(
      () => _step = needsFareConfirm
          ? _ActiveTripStep.fareConfirm
          : _ActiveTripStep.rating,
    );
  }

  void _confirmFare() => setState(() => _step = _ActiveTripStep.rating);

  /// Spec §7.2 "Татгалзвал баримт хосгүй үлдэнэ": skips the rating step
  /// entirely, so no `tripReceiptRepositoryProvider.publish` call ever
  /// happens for this side -- the pairing check in
  /// `packages/takhi_protocol/lib/src/reputation.dart` already treats a
  /// missing receipt as unpaired, so declining needs no other special
  /// handling beyond simply never publishing one.
  void _declineFare() {
    setState(() {
      _fareDeclined = true;
      _step = _ActiveTripStep.done;
    });
    // Declining is as final as publishing: nothing more will be sent for
    // this trip, so the host's leave guard has nothing left to protect.
    widget.onTripSettled?.call();
  }

  Future<void> _submitRating() async {
    final identity = _identity;
    if (identity == null) return;
    setState(() => _submittingRating = true);
    try {
      await ref
          .read(tripReceiptRepositoryProvider)
          .publish(
            privHex: identity.privHex,
            now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            tripId: widget.tripId,
            counterpartyPubkey: widget.counterpartyPubHex,
            role: widget.role.wireValue,
            ratingStars: _selectedStars,
            distanceMeters: _meter.distanceMeters,
            durationSeconds: _meter.durationSeconds,
            priceMnt: _finalFareMnt ?? widget.agreedPriceMnt,
            // Zero on a fixed-price trip, which is the truth about it: the
            // agreed price covered however long the trip stood still.
            waitingSeconds: _finalWaitingSeconds ?? 0,
            waitingFareMnt: _finalWaitingFareMnt ?? 0,
            comment: _commentController.text,
          );
      if (!mounted) return;
      setState(() => _step = _ActiveTripStep.done);
      widget.onTripSettled?.call();
    } finally {
      if (mounted) setState(() => _submittingRating = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _cancelSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps this widget subscribed for rebuilds if identity state ever
    // changes later, matching `PassengerRidePage`/`DriverInboxPage`'s
    // pattern -- `initState` already awaits `.future` to start tracking.
    ref.watch(currentIdentityProvider);
    return switch (_step) {
      _ActiveTripStep.tracking =>
        _locationPermissionDenied
            ? LocationPermissionDeniedView(
                onRetry: () {
                  final identity = _identity;
                  if (identity != null) unawaited(_startTracking(identity));
                },
              )
            : IncomingCallListener(
                tripId: widget.tripId,
                counterpartyPubHex: widget.counterpartyPubHex,
                counterpartyPhone: _counterpartyPhone,
                child: _TrackingView(
                  phase: _phase,
                  role: widget.role,
                  counterpartyPubHex: widget.counterpartyPubHex,
                  counterpartyName: widget.counterpartyName,
                  counterpartyPhotoJpeg: widget.counterpartyPhotoJpeg,
                  selfPosition: _selfPosition,
                  counterpartyPosition: _counterpartyPosition,
                  lastFix: _meter.fixes.isEmpty ? null : _meter.fixes.last,
                  // Spec §7.2: both sides show their own running fare, from
                  // their own GPS track -- `null` in fixed-price mode.
                  liveFareMnt: widget.kmTariffMnt == null
                      ? null
                      : _meter.fareMnt,
                  // Spec §7.4: only ever one meter is running, so the screen
                  // names which one. Without it a stalled distance figure in
                  // traffic is indistinguishable from a broken meter.
                  //
                  // Driven by `isStopped` since v0.4.0, and showing the
                  // trip-duration charge rather than a waiting one: sitting
                  // in traffic is part of the trip and is billed by the
                  // trip rate. The waiting rate is a phase the driver
                  // enters when the passenger is keeping them, which is not
                  // what a red light is.
                  //
                  // The figure is what THIS STOP has cost, not the whole
                  // trip's duration charge: the question the chip answers
                  // is "the kilometres have stopped moving — is the meter
                  // broken?", and the answer is the money the standstill
                  // has earned so far.
                  //
                  // Absent when no trip rate is set, because then nothing
                  // is in fact accruing and a «· 0 ₮» would say otherwise.
                  liveWaitingFareMnt:
                      widget.kmTariffMnt == null ||
                          !_meter.isStopped ||
                          _meter.durationTariffMntPerMinute <= 0
                      ? null
                      : computeDurationFareMnt(
                          mntPerMinute: _meter.durationTariffMntPerMinute,
                          durationSeconds: _meter.stoppedSeconds,
                        ),
                  receivedVoiceNotes: _receivedVoiceNotes,
                  playingVoiceNoteIndex: _playingVoiceNoteIndex,
                  onMarkPassengerBoarded: _markPassengerBoarded,
                  onEndTrip: _endTrip,
                  onStartCall: _startCall,
                  onShareTrip: _shareTrip,
                  onPlayVoiceNote: _togglePlayVoiceNote,
                ),
              ),
      _ActiveTripStep.fareConfirm => _FareConfirmView(
        finalFareMnt: _finalFareMnt!,
        // Both come off the same status DM as the total (see
        // [_finalWaitingFareMnt]) -- never recomputed here, so the rows the
        // passenger signs are the rows the driver measured. Zero for a
        // client that predates waiting fares, which showed no breakdown
        // then and shows none now.
        waitingFareMnt: _finalWaitingFareMnt ?? 0,
        waitingSeconds: _finalWaitingSeconds ?? 0,
        durationFareMnt: _finalDurationFareMnt ?? 0,
        durationSeconds: _finalDurationSeconds ?? 0,
        onConfirm: _confirmFare,
        onDecline: _declineFare,
      ),
      _ActiveTripStep.rating => _RatingView(
        role: widget.role,
        counterpartyPubHex: widget.counterpartyPubHex,
        counterpartyName: widget.counterpartyName,
        counterpartyPhotoJpeg: widget.counterpartyPhotoJpeg,
        // The same figure the receipt is about to carry (see
        // [_submitRating]) -- a rating screen that cannot say what was paid
        // is asking the user to score a trip it has already forgotten.
        priceMnt: _finalFareMnt ?? widget.agreedPriceMnt,
        selectedStars: _selectedStars,
        onStarSelected: (stars) => setState(() => _selectedStars = stars),
        commentController: _commentController,
        submitting: _submittingRating,
        onSubmit: _submitRating,
      ),
      _ActiveTripStep.done => _DoneView(
        role: widget.role,
        agreedPriceMnt: _finalFareMnt ?? widget.agreedPriceMnt,
        fareDeclined: _fareDeclined,
        onFinished: widget.onFinished,
      ),
    };
  }
}

/// The screen a rider and a driver spend the whole trip looking at.
///
/// Structurally it is the same object home is: a full-bleed map with a sheet
/// floating on it. Everything the trip *is* -- which phase it is in, what the
/// meter says, who the other person is, how to reach them -- lives on that
/// sheet, in rows, because the previous shape (a strip of gold text and three
/// identical icons above a boxed map) answered none of those questions and
/// made the one urgent control look like the two beside it.
///
/// The map is [TripTrackingMap] rather than a bare `RideMap` with two
/// markers on it, and that is the third safety decision on this screen: it
/// is the widget that keeps both people in frame as they move, and that
/// draws "where am I" as the same mark every other map in this app draws it
/// as. The version it replaced centred once, on the frame before the first
/// GPS fix existed, and then never moved again.
///
/// Two placement decisions are safety decisions rather than layout ones:
///
/// * **SOS floats at the top corner of the map**, alone, tinted, and is the
///   only red thing on screen. It has to be found in a second by someone who
///   has never gone looking for it, and it must not be what a thumb reaching
///   for the primary button at the bottom lands on. Distance is the guard.
/// * **Call sits on the counterparty's own row**, because that is what it
///   calls. It used to be an anonymous handset glyph in a row of three.
class _TrackingView extends StatelessWidget {
  final TripPhase phase;
  final TripRole role;

  /// The other person's public key -- the only thing *either* side can check
  /// the other against, and on the driver's screen still the only thing it
  /// knows about them at all.
  final String counterpartyPubHex;

  /// See `ActiveTripView.counterpartyName` -- the passenger's side of the
  /// trip carries both; the driver's side carries neither.
  final String? counterpartyName;
  final Uint8List? counterpartyPhotoJpeg;

  final ll.LatLng? selfPosition;
  final ll.LatLng? counterpartyPosition;

  /// The newest reading behind [selfPosition]. Two things read it: the SOS
  /// message, which sends the coordinate, and the map, which draws the
  /// accuracy that coordinate came with.
  final GpsFix? lastFix;

  /// See `ActiveTripView.kmTariffMnt`'s doc comment -- `null` in
  /// fixed-price mode, the live running fare (this device's own GPS
  /// track) in metered mode.
  final int? liveFareMnt;

  /// What the waiting meter has accrued so far -- non-null only while that
  /// is the meter currently running (spec §7.4). See
  /// `MeterSession`'s "exactly one meter runs at a time".
  final int? liveWaitingFareMnt;
  final List<ReceivedVoiceNote> receivedVoiceNotes;
  final int? playingVoiceNoteIndex;
  final VoidCallback onMarkPassengerBoarded;
  final VoidCallback onEndTrip;
  final VoidCallback onStartCall;
  final VoidCallback onShareTrip;
  final ValueChanged<int> onPlayVoiceNote;

  const _TrackingView({
    required this.phase,
    required this.role,
    required this.counterpartyPubHex,
    required this.counterpartyName,
    required this.counterpartyPhotoJpeg,
    required this.selfPosition,
    required this.counterpartyPosition,
    required this.lastFix,
    required this.liveFareMnt,
    required this.liveWaitingFareMnt,
    required this.receivedVoiceNotes,
    required this.playingVoiceNoteIndex,
    required this.onMarkPassengerBoarded,
    required this.onEndTrip,
    required this.onStartCall,
    required this.onShareTrip,
    required this.onPlayVoiceNote,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Stack(
      children: [
        Positioned.fill(
          child: TripTrackingMap(
            selfPosition: selfPosition,
            // The ring the dot is allowed to be wrong inside. Read off the
            // same fix the mark itself comes from, so the two can never
            // disagree, and `null` (which is what a platform that did not
            // say looks like) draws no ring at all rather than an invented
            // radius -- see `DeviceLocationLayer`.
            selfAccuracyMeters: lastFix?.accuracyMeters,
            counterpartyPosition: counterpartyPosition,
            counterpartyIsDriver: role == TripRole.passenger,
            fallbackCenter: ll.LatLng(
              defaultCityConfig.centerLat,
              defaultCityConfig.centerLon,
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(TakhiSpace.md),
              child: _SosBadge(lastFix: lastFix),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sharing belongs to the map, not to the person: it hands out
              // a link to where this trip is going, which is why it floats
              // over the thing it is about rather than sitting on the sheet.
              Padding(
                padding: const EdgeInsets.only(
                  right: TakhiSpace.md,
                  bottom: TakhiSpace.sm,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: CircleIconButton(
                    icon: Icons.share,
                    semanticLabel: l.shareTripAction,
                    onPressed: onShareTrip,
                  ),
                ),
              ),
              _TrackingSheet(
                phase: phase,
                role: role,
                counterpartyPubHex: counterpartyPubHex,
                counterpartyName: counterpartyName,
                counterpartyPhotoJpeg: counterpartyPhotoJpeg,
                liveFareMnt: liveFareMnt,
                liveWaitingFareMnt: liveWaitingFareMnt,
                receivedVoiceNotes: receivedVoiceNotes,
                playingVoiceNoteIndex: playingVoiceNoteIndex,
                onMarkPassengerBoarded: onMarkPassengerBoarded,
                onEndTrip: onEndTrip,
                onStartCall: onStartCall,
                onPlayVoiceNote: onPlayVoiceNote,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Everything the trip is, as rows on one sheet.
class _TrackingSheet extends StatelessWidget {
  final TripPhase phase;
  final TripRole role;
  final String counterpartyPubHex;
  final String? counterpartyName;
  final Uint8List? counterpartyPhotoJpeg;
  final int? liveFareMnt;
  final int? liveWaitingFareMnt;
  final List<ReceivedVoiceNote> receivedVoiceNotes;
  final int? playingVoiceNoteIndex;
  final VoidCallback onMarkPassengerBoarded;
  final VoidCallback onEndTrip;
  final VoidCallback onStartCall;
  final ValueChanged<int> onPlayVoiceNote;

  const _TrackingSheet({
    required this.phase,
    required this.role,
    required this.counterpartyPubHex,
    required this.counterpartyName,
    required this.counterpartyPhotoJpeg,
    required this.liveFareMnt,
    required this.liveWaitingFareMnt,
    required this.receivedVoiceNotes,
    required this.playingVoiceNoteIndex,
    required this.onMarkPassengerBoarded,
    required this.onEndTrip,
    required this.onStartCall,
    required this.onPlayVoiceNote,
  });

  /// The driver's one action for the phase the trip is in, or `null` once
  /// there is nothing left for them to press (arrived, and on the passenger
  /// side throughout -- the passenger never drives the phase, spec §7.1).
  ({String label, VoidCallback onPressed})? _phaseAction(AppLocalizations l) {
    if (role != TripRole.driver) return null;
    return switch (phase) {
      TripPhase.enRouteToPickup => (
        label: l.markPassengerBoardedAction,
        onPressed: onMarkPassengerBoarded,
      ),
      TripPhase.tripInProgress => (
        label: l.endTripAction,
        onPressed: onEndTrip,
      ),
      TripPhase.arrived => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final fare = liveFareMnt;
    final waiting = liveWaitingFareMnt;
    final action = _phaseAction(l);
    final maxContentHeight =
        MediaQuery.sizeOf(context).height * _kSheetContentMaxFraction;

    // Opaque so a drag that starts on the sheet stays on the sheet: a
    // painted surface is transparent to hit-testing in Flutter, so without
    // this every swipe across the sheet would pan the map underneath it
    // (the same guard `HomePage._HomeSheet` documents).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: TakhiSheet(
        showHandle: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxContentHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: TakhiSpace.xs,
                    runSpacing: TakhiSpace.xs,
                    children: [
                      _PhaseChip(phase: phase),
                      // Spec §7.4: only ever one meter runs, so the screen
                      // names which one. Without it a stalled distance
                      // figure in traffic is indistinguishable from a broken
                      // meter, and the waiting charge turns up at the end
                      // unexplained.
                      if (waiting != null)
                        InfoChip(
                          icon: Icons.hourglass_bottom_outlined,
                          label: l.meteredLiveWaitingLabel(groupedMnt(waiting)),
                          accent: TakhiAccent.gold,
                        ),
                    ],
                  ),
                ),
                if (fare != null) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  _AmountCard(
                    label: l.meteredLiveFareTitle,
                    amountMnt: fare,
                    semanticsLabel: l.meteredLiveFareLabel(groupedMnt(fare)),
                  ),
                ],
                const SizedBox(height: TakhiSpace.sm),
                _CounterpartyRow(
                  role: role,
                  counterpartyPubHex: counterpartyPubHex,
                  counterpartyName: counterpartyName,
                  counterpartyPhotoJpeg: counterpartyPhotoJpeg,
                  trailing: CircleIconButton(
                    icon: Icons.call,
                    accent: TakhiAccent.steppe,
                    semanticLabel: l.startCallAction,
                    onPressed: onStartCall,
                  ),
                ),
                if (receivedVoiceNotes.isNotEmpty) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  _VoiceNoteBanner(
                    notes: receivedVoiceNotes,
                    playingIndex: playingVoiceNoteIndex,
                    onPlay: onPlayVoiceNote,
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: TakhiSpace.md),
                  PrimaryButton(
                    label: action.label,
                    onPressed: action.onPressed,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which phase the trip is in, as one chip.
///
/// A chip rather than a coloured line of text, for the same two reasons the
/// taximeter's own mode badge is one: it has to be readable at a glance, and
/// it has to be *readable* -- a colour code nobody has memorised still owes
/// the reader a word. The accents follow the app's own vocabulary: sky for
/// something on its way, steppe for something live, gold for the moment it
/// lands.
class _PhaseChip extends StatelessWidget {
  final TripPhase phase;

  const _PhaseChip({required this.phase});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (label, icon, accent) = switch (phase) {
      TripPhase.enRouteToPickup => (
        l.tripPhaseEnRouteToPickup,
        Icons.directions_car_outlined,
        TakhiAccent.sky,
      ),
      TripPhase.tripInProgress => (
        l.tripPhaseInProgress,
        Icons.navigation_outlined,
        TakhiAccent.steppe,
      ),
      TripPhase.arrived => (
        l.tripPhaseArrived,
        Icons.flag_outlined,
        TakhiAccent.gold,
      ),
    };
    return InfoChip(icon: icon, label: label, accent: accent);
  }
}

/// The other person in this trip, as a row.
///
/// On the passenger's side the row leads with the driver's овог and нэр and
/// their face -- both of which arrived inside the gift-wrapped offer this
/// rider accepted, and neither of which is on any public relay. This is the
/// screen where that matters most: a rider standing at a kerb watching a car
/// pull up is comparing a face, and until now the only thing this row could
/// offer them was the word "Жолооч".
///
/// On the driver's side neither exists -- the handoff carries a pickup point
/// and, optionally, a phone number, never a passenger's name -- so the row
/// falls back to what it has always said: *which side* the other person is,
/// over the abbreviated key. That key stays visible on both sides, because
/// it is the one thing either party can check the other against.
///
/// Tapping the row opens the photograph full screen when there is one, and
/// does nothing when there is not. A face compared at 44dp is not compared;
/// the portrait itself is far below [TakhiTouch.minTarget], so the gesture
/// belongs to the row rather than to the circle.
class _CounterpartyRow extends StatelessWidget {
  /// *This* device's role. The counterparty is the other one.
  final TripRole role;
  final String counterpartyPubHex;

  /// See `ActiveTripView.counterpartyName`. Both null on the driver's side.
  final String? counterpartyName;
  final Uint8List? counterpartyPhotoJpeg;

  /// The action that belongs to this person -- the call button on the
  /// tracking sheet, a fare chip on the rating screen.
  final Widget? trailing;

  const _CounterpartyRow({
    required this.role,
    required this.counterpartyPubHex,
    this.counterpartyName,
    this.counterpartyPhotoJpeg,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final counterpartyIsDriver = role == TripRole.passenger;
    final name = counterpartyName;
    final photo = counterpartyPhotoJpeg;
    return PersonRow(
      name: name ?? (counterpartyIsDriver ? l.driverMode : l.passengerMode),
      avatar: photo == null ? null : MemoryImage(photo),
      subtitle: shortPubkeyLabel(counterpartyPubHex),
      // Steppe is the app's "driving" colour throughout (the home tile, the
      // live phase chip), gold is the rider's own family -- so the mark in
      // front of the row says which side is sitting opposite before the
      // word under it is read.
      accent: counterpartyIsDriver ? TakhiAccent.steppe : TakhiAccent.gold,
      trailing: trailing,
      onTap: photo == null
          ? null
          : () => unawaited(showDriverPhoto(context, photo)),
    );
  }
}

/// The SOS control, given a plane and a colour of its own.
///
/// [SosButton] itself is shared with the home sheet and stays exactly as it
/// is; what this adds is separation. On a screen that also carries a call
/// button, a share button and a primary action, an unframed red glyph in a
/// row of gold ones is neither findable in a second nor safe from a stray
/// thumb. Framed, tinted and parked at the far corner from the sheet, it is
/// both.
class _SosBadge extends StatelessWidget {
  final GpsFix? lastFix;

  const _SosBadge({required this.lastFix});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final colors = takhiAccentColors(
      TakhiAccent.clay,
      Theme.of(context).brightness,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tint,
        shape: BoxShape.circle,
        border: Border.all(color: surfaces.hairline),
        boxShadow: surfaces.floatShadow,
      ),
      // `SosButton` is an `IconButton`, which already occupies
      // `TakhiTouch.minTarget` in both axes -- the disc is drawn around that
      // target rather than the target being shrunk to a disc.
      child: SosButton(lastFix: lastFix),
    );
  }
}

/// A money figure, the small label that says what it is, and -- when there
/// is one -- the arithmetic behind it.
///
/// One component for every amount in the trip flow: the fare while it is
/// still running, the fare a passenger is asked to sign, and the settled
/// total afterwards. Having one means the same number is set the same way at
/// every moment of the trip, and the driver's screen and the passenger's
/// screen cannot end up stating it in two different sizes.
///
/// [semanticsLabel] is the whole card as one sentence. Two lines is right
/// for the eye and wrong for a screen reader, which would otherwise announce
/// «Нийт» and then, separately, a bare number.
class _AmountCard extends StatelessWidget {
  /// The small standing label. User-visible: pass a localised string.
  final String label;
  final int amountMnt;

  /// What a screen reader hears instead of [label] plus the figure.
  final String semanticsLabel;

  /// The rows [amountMnt] is made of, drawn above it inside the same card
  /// and separated from it by a rule. Empty when there is nothing to
  /// itemise -- a fixed-price trip, or a metered one that never waited.
  final List<Widget> breakdown;

  const _AmountCard({
    required this.label,
    required this.amountMnt,
    required this.semanticsLabel,
    this.breakdown = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surfaces.field,
            borderRadius: TakhiRadius.cardAll,
            border: Border.all(color: surfaces.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TakhiSpace.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (breakdown.isNotEmpty) ...[
                  ...breakdown,
                  const SizedBox(height: TakhiSpace.sm),
                  Divider(height: 1, thickness: 1, color: surfaces.hairline),
                  const SizedBox(height: TakhiSpace.sm),
                ],
                Text(
                  label,
                  style: TakhiType.micro.copyWith(color: surfaces.muted),
                ),
                const SizedBox(height: TakhiSpace.xxs),
                // Scaled down rather than clipped once a fare runs past five
                // figures: the ₮ mark is at the end, so clipping would take
                // the currency off the number.
                //
                // It joins the money column when there is a column to join:
                // with a breakdown above it the three figures share one right
                // edge, which is what lets the reader check the addition down
                // a straight line. Standing alone there is nothing to line up
                // with, and a figure hard against the right of an otherwise
                // left-aligned card reads as drift.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: breakdown.isEmpty
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Text(
                    l.meterFareLabel(groupedMnt(amountMnt)),
                    style: TakhiType.numericDisplay.copyWith(
                      color: surfaces.onSheet,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The scrolling half of a step, with its action anchored on a sheet below.
///
/// Every non-map step of this flow has the same two-part shape -- something
/// to read, and the one or two buttons that answer it -- and the buttons are
/// anchored so they never scroll out of reach on a small screen or at a
/// large text scale. It is the shape `TaximeterPage` already uses, so the
/// two halves of the app that settle money look like one app.
class _StepScaffold extends StatelessWidget {
  final Widget child;

  /// Laid out inside a [TakhiSheet] at the bottom. `null` for a step with
  /// nothing to press (a finished trip whose host wired no callback).
  final Widget? action;

  const _StepScaffold({required this.child, this.action});

  @override
  Widget build(BuildContext context) {
    final anchored = action;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              TakhiSpace.md,
              TakhiSpace.lg,
              TakhiSpace.md,
              TakhiSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [child],
            ),
          ),
        ),
        if (anchored != null) TakhiSheet(showHandle: false, child: anchored),
      ],
    );
  }
}

/// The step that turns a finished trip into reputation.
///
/// It used to be a gold line, five small stars and an unlabelled empty box
/// stacked at the top of a blank screen -- with nothing on it saying *whom*
/// or *what* was being rated, which is the one thing a rating needs in order
/// to mean anything. Now the trip is stated first (who was on the other
/// side, what it cost), the stars are large enough to hit once and correctly,
/// and the comment box says what it is for.
class _RatingView extends StatelessWidget {
  /// This device's own role -- [_CounterpartyRow] turns it into the other
  /// side's.
  final TripRole role;
  final String counterpartyPubHex;

  /// See `ActiveTripView.counterpartyName` -- a rating screen that can name
  /// the person being rated is asking a far more answerable question than
  /// one that can only name their key.
  final String? counterpartyName;
  final Uint8List? counterpartyPhotoJpeg;

  /// What the trip actually cost: the metered final fare when there was one,
  /// the agreed price otherwise. The same figure the receipt carries.
  final int priceMnt;

  final int selectedStars;
  final ValueChanged<int> onStarSelected;
  final TextEditingController commentController;
  final bool submitting;
  final VoidCallback onSubmit;

  const _RatingView({
    required this.role,
    required this.counterpartyPubHex,
    required this.counterpartyName,
    required this.counterpartyPhotoJpeg,
    required this.priceMnt,
    required this.selectedStars,
    required this.onStarSelected,
    required this.commentController,
    required this.submitting,
    required this.onSubmit,
  });

  static const _starCount = 5;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return _StepScaffold(
      action: PrimaryButton(
        label: l.submitRatingAction,
        loading: submitting,
        // `buildTripReceipt` (takhi_events.dart) throws `ArgumentError`
        // for `ratingStars` outside 1..5, and `selectedStars` starts at 0
        // -- disable the button (rather than leaving it tappable and
        // crashing `_submitRating`) until a star is picked, per
        // `PrimaryButton`'s own documented "pass null for nothing to do
        // yet" convention.
        onPressed: selectedStars > 0 ? onSubmit : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(title: l.rateTripTitle, subtitle: l.rateTripStarsHint),
          const SizedBox(height: TakhiSpace.lg),
          // What is being rated, in the two facts that identify it. The
          // fare rides as a chip on the row rather than as a line of its
          // own: it qualifies the trip, it is not the subject of the screen.
          _CounterpartyRow(
            role: role,
            counterpartyPubHex: counterpartyPubHex,
            counterpartyName: counterpartyName,
            counterpartyPhotoJpeg: counterpartyPhotoJpeg,
            trailing: InfoChip(
              icon: Icons.payments_outlined,
              label: l.meterFareLabel(groupedMnt(priceMnt)),
              accent: TakhiAccent.gold,
            ),
          ),
          const SizedBox(height: TakhiSpace.lg),
          _StarRow(
            selectedStars: selectedStars,
            onStarSelected: onStarSelected,
          ),
          const SizedBox(height: TakhiSpace.lg),
          LabeledField(
            label: l.rateTripCommentPlaceholder,
            icon: Icons.chat_bubble_outline,
            controller: commentController,
            // Three lines rather than one: a comment is the part of a
            // receipt that explains the stars, and a single-line capsule
            // says "one phrase" to anyone who has something longer to say.
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

/// Five stars, sized to be hit once and correctly.
///
/// Empty stars take the supporting colour rather than gold: an unfilled gold
/// outline beside a filled gold star is a difference nobody sees at arm's
/// length, and "nothing picked yet" then looks like "five picked".
class _StarRow extends StatelessWidget {
  final int selectedStars;
  final ValueChanged<int> onStarSelected;

  const _StarRow({required this.selectedStars, required this.onStarSelected});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_RatingView._starCount, (i) {
        final filled = i < selectedStars;
        return IconButton(
          iconSize: _kStarGlyphSize,
          // The one place flat brand gold is correct as a foreground: a
          // star is a shape read as a symbol, not text (the same exception
          // `PersonRow` documents for its rating mark).
          color: filled ? TakhiColors.gold : surfaces.muted,
          icon: Icon(filled ? Icons.star : Icons.star_border),
          onPressed: () => onStarSelected(i + 1),
        );
      }),
    );
  }
}

/// What the trip settled at, and how it gets paid.
class _DoneView extends StatelessWidget {
  final TripRole role;
  final int agreedPriceMnt;

  /// Set only via `_ActiveTripViewState._declineFare` (spec §7.2 "Татгалзвал
  /// баримт хосгүй үлдэнэ") -- when true, no receipt was ever published for
  /// this side, so this view shows that outcome instead of
  /// `l.tripReceiptPublished`/the QR-or-cash hint, which would otherwise
  /// misleadingly imply a receipt exists.
  final bool fareDeclined;

  /// See [ActiveTripView.onFinished] -- `null` renders no button at all,
  /// which is the pre-existing (dead-end) behaviour for any host that has
  /// not wired one yet.
  final VoidCallback? onFinished;

  const _DoneView({
    required this.role,
    required this.agreedPriceMnt,
    this.fareDeclined = false,
    this.onFinished,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Local copy: a public instance field is not promoted by a null check
    // (dart/coding-style.md's "avoid `!`").
    final onFinished = this.onFinished;
    final finish = onFinished == null
        ? null
        : PrimaryButton(label: l.finishTripAction, onPressed: onFinished);

    if (fareDeclined) {
      return _StepScaffold(
        action: finish,
        child: NoticeCard(
          icon: Icons.receipt_long_outlined,
          text: l.meteredFareDeclinedHint,
          accent: TakhiAccent.clay,
        ),
      );
    }

    return _StepScaffold(
      action: finish,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(title: l.tripReceiptPublished),
          const SizedBox(height: TakhiSpace.lg),
          _AmountCard(
            label: l.meterSummaryTotalRow,
            amountMnt: agreedPriceMnt,
            semanticsLabel: l.agreedPriceLabel(groupedMnt(agreedPriceMnt)),
          ),
          const SizedBox(height: TakhiSpace.xxl),
          SectionHeading(compact: true, title: l.meterPaymentTitle),
          const SizedBox(height: TakhiSpace.md),
          // The driver's own plate answers "how do I get paid" by itself.
          // The passenger has no code of their own to show, and their half
          // of this screen used to stop at the heading -- a title, one grey
          // sentence, and then half a metre of blank paper above the finish
          // button. The two ways to settle are rows now, for the same
          // reason every other list in this app is: a statement laid out as
          // a marked row is read, a sentence floating under a heading is
          // not. Untappable by construction -- both happen in the car, not
          // in the app -- so [MenuRow] renders them without a fill or a
          // chevron and they cannot look like controls that do nothing.
          if (role == TripRole.driver)
            const Center(child: DriverQrDisplay())
          else ...[
            MenuRow(
              icon: Icons.qr_code_2,
              label: l.payWithQrOptionLabel,
              accent: TakhiAccent.gold,
            ),
            const SizedBox(height: TakhiSpace.xs),
            MenuRow(
              icon: Icons.payments_outlined,
              label: l.payWithCashOptionLabel,
              accent: TakhiAccent.sky,
            ),
          ],
        ],
      ),
    );
  }
}

/// Spec §7.2's passenger-only gate between the metered trip ending and the
/// rating step: shows the driver-reported, GPS-computed final fare and
/// requires an explicit confirm before a trip receipt is ever published
/// (declining routes straight to [_DoneView] with [_DoneView.fareDeclined],
/// publishing nothing).
///
/// The breakdown is the whole point of the screen, so it is laid out as an
/// addition the reader can follow: the two parts, a rule, then the total in
/// the largest figure on screen. Both sides see the same rows in the same
/// wording -- the labels are the taximeter summary's own
/// (`meterSummaryDistanceFareRow`, `meterSummaryTotalRow`), so the driver
/// reading their meter and the passenger signing for it are not being shown
/// two differently-worded versions of one sum.
class _FareConfirmView extends StatelessWidget {
  final int finalFareMnt;

  /// The waiting half of [finalFareMnt] and the time behind it, as the
  /// driver measured them (spec §7.4). Zero means the trip never stood
  /// still long enough to be billed for it -- or that the driver charges
  /// nothing for waiting -- and in both cases there is nothing to break
  /// down, so this view stays the single figure it was before §7.4.
  final int waitingFareMnt;
  final int waitingSeconds;

  /// The trip-duration share of [finalFareMnt] and the seconds behind it.
  /// Its own row rather than folded into [waitingFareMnt]: the two rates
  /// overlap where the driver set both, so the stopped minutes are counted
  /// in this figure as well. Showing one merged "time" line would present a
  /// number matching neither of the two rates the passenger was quoted, and
  /// would quietly hide the overlap they agreed to.
  final int durationFareMnt;
  final int durationSeconds;

  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  const _FareConfirmView({
    required this.finalFareMnt,
    required this.waitingFareMnt,
    required this.waitingSeconds,
    required this.durationFareMnt,
    required this.durationSeconds,
    required this.onConfirm,
    required this.onDecline,
  });

  static const _secondsPerMinute = 60;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Derived, never carried on the wire: a distance figure sent alongside
    // the total could disagree with it by a tögrög, and then the passenger
    // is being asked to sign two different prices at once.
    //
    // Every time charge has to come off it, not just the waiting one. While
    // trip-duration fares existed only on the offline meter this line was
    // still arithmetically right -- `durationFareMnt` was always 0 here --
    // but the moment the rate started travelling on an offer, subtracting
    // one of two time charges would have reported the duration fare to the
    // passenger as distance: a row claiming the car drove further than it
    // did, in a screen whose whole job is that the rows add up.
    final distanceFareMnt = finalFareMnt - waitingFareMnt - durationFareMnt;
    // The distance row exists to explain the time rows beside it, so it
    // appears exactly when at least one of them does. On a trip billed by
    // distance alone the total above it already is the distance fare, and
    // repeating it as its own row underneath says nothing.
    final hasTimeCharge = waitingFareMnt > 0 || durationFareMnt > 0;

    return _StepScaffold(
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            label: l.meteredFareConfirmAction,
            onPressed: onConfirm,
          ),
          const SizedBox(height: TakhiSpace.xs),
          SecondaryButton(
            label: l.meteredFareDeclineAction,
            onPressed: onDecline,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: l.meteredFareConfirmTitle,
            subtitle: l.meteredFareConfirmSubtitle,
          ),
          const SizedBox(height: TakhiSpace.lg),
          _AmountCard(
            label: l.meterSummaryTotalRow,
            amountMnt: finalFareMnt,
            semanticsLabel: l.agreedPriceLabel(groupedMnt(finalFareMnt)),
            breakdown: [
              if (hasTimeCharge) ...[
                _FareBreakdownRow(
                  label: l.meterSummaryDistanceFareRow,
                  amountMnt: distanceFareMnt,
                ),
                if (waitingFareMnt > 0) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  _FareBreakdownRow(
                    // The minutes are the check on the money: a passenger who
                    // disagrees with the charge is really disagreeing with how
                    // long the car stood still, so the two are shown together.
                    label: l.meteredFareConfirmWaitingRow(
                      (waitingSeconds / _secondsPerMinute).round(),
                    ),
                    amountMnt: waitingFareMnt,
                  ),
                ],
                if (durationFareMnt > 0) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  _FareBreakdownRow(
                    // Same check against the same kind of clock, for the
                    // rate that runs the whole trip. Where the driver set
                    // both time rates these minutes include the stopped ones
                    // above -- the rows are the two rates as offered, not a
                    // partition of the trip, and a passenger comparing them
                    // against the offer they accepted is comparing like with
                    // like.
                    label: l.meteredFareConfirmDurationRow(
                      (durationSeconds / _secondsPerMinute).round(),
                    ),
                    amountMnt: durationFareMnt,
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One "what this part cost" line of [_FareConfirmView]'s breakdown: the
/// name of the charge on the left, its ₮ figure hard against the right, so
/// the two amounts sit in a column the eye can add up.
class _FareBreakdownRow extends StatelessWidget {
  final String label;
  final int amountMnt;

  const _FareBreakdownRow({required this.label, required this.amountMnt});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: TakhiType.body.copyWith(color: surfaces.muted),
          ),
        ),
        const SizedBox(width: TakhiSpace.sm),
        Text(
          l.meterFareLabel(groupedMnt(amountMnt)),
          style: TakhiType.numeric.copyWith(color: surfaces.onSheet),
        ),
      ],
    );
  }
}

/// The voice notes that have arrived for this trip (spec §7.3-③, the calling
/// fallback chain's last rung) -- the persistent play-back UI half of Plan 5
/// review CRITICAL-3's fix (the transient half is the `SnackBar`
/// `ActiveTripView._startTracking`'s voice-note listener already shows the
/// moment one arrives).
///
/// Headed, because two unlabelled capsules on a trip screen say nothing
/// about where they came from. The chip itself carries only how long the
/// note runs -- the play/stop glyph says what tapping does, and the duration
/// is the one fact that tells two notes apart.
class _VoiceNoteBanner extends StatelessWidget {
  final List<ReceivedVoiceNote> notes;
  final int? playingIndex;
  final ValueChanged<int> onPlay;

  const _VoiceNoteBanner({
    required this.notes,
    required this.playingIndex,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final colors = takhiAccentColors(
      TakhiAccent.gold,
      Theme.of(context).brightness,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.voiceNotesTitle,
          style: TakhiType.micro.copyWith(color: surfaces.muted),
        ),
        const SizedBox(height: TakhiSpace.xs),
        Wrap(
          spacing: TakhiSpace.xs,
          runSpacing: TakhiSpace.xs,
          children: [
            for (var i = 0; i < notes.length; i++)
              ActionChip(
                avatar: Icon(
                  playingIndex == i ? Icons.stop : Icons.play_arrow,
                  size: _kVoiceNoteGlyphSize,
                  color: colors.onTint,
                ),
                label: Text(
                  l.voiceNoteDurationLabel(notes[i].payload.durationSeconds),
                  style: TakhiType.label.copyWith(color: colors.onTint),
                ),
                // The action's name lives here rather than in the label: the
                // chip is read as "a voice note, this long", and repeating
                // «Тоглуулах» on every one of them is noise. A long press --
                // and every screen reader -- still gets the verb.
                tooltip: l.playVoiceNoteAction,
                backgroundColor: colors.tint,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onPressed: () => onPlay(i),
              ),
          ],
        ),
      ],
    );
  }
}
