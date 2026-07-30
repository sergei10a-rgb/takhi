// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:share_plus/share_plus.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../call/call_providers.dart';
import '../call/call_screen.dart';
import '../call/voice_note_service.dart' show ReceivedVoiceNote;
import '../config/city_config.dart';
import '../geo/geo_providers.dart';
import '../geo/gps_fix.dart';
import '../identity/identity_service.dart' show Identity;
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/ride_map.dart';
import '../meter/meter_session.dart';
import '../meter/money_format.dart';
import '../nostr/relay_pool_provider.dart' show defaultRelayUrls;
import '../payment/driver_qr_display.dart';
import '../safety/share_session.dart';
import '../safety/sos_button.dart';
import '../theme/takhi_theme.dart';
import '../widgets/location_permission_denied_view.dart';
import '../widgets/primary_button.dart';
import 'ride_providers.dart';
import 'trip_phase.dart';
import 'trip_role.dart';
import 'trip_status_service.dart' show ReceivedTripStatus;

/// Throttle for `LiveLocationChannel.send`: only every 2nd fix is forwarded
/// to the counterparty (spec §6's 5-10s cadence hint; `LocationSource`
/// itself has no fixed interval guarantee, so counting fixes here is a
/// simpler, deterministic-in-tests substitute for a wall-clock `Timer`).
const _sendEveryNthFix = 2;

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
    this.kmTariffMnt,
    this.waitTariffMntPerMinute,
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

    _gpsSubscription = ref
        .read(locationSourceProvider)
        .watch()
        .listen((fix) => _onOwnFix(identity, fix));

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
    if (finalFareMnt != null) {
      _finalFareMnt = finalFareMnt;
      _finalWaitingFareMnt = finalWaitingFareMnt;
      _finalWaitingSeconds = finalWaitingSeconds;
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
                  selfPosition: _selfPosition,
                  counterpartyPosition: _counterpartyPosition,
                  lastFix: _meter.fixes.isEmpty ? null : _meter.fixes.last,
                  // Spec §7.2: both sides show their own running fare, from
                  // their own GPS track -- `null` in fixed-price mode.
                  liveFareMnt: widget.kmTariffMnt == null
                      ? null
                      : _meter.fareMnt,
                  // Spec §7.4: only ever one meter is running, so the screen
                  // names which one. Non-null exactly while the waiting one
                  // is -- without it a stalled distance figure in traffic is
                  // indistinguishable from a broken meter, and the waiting
                  // charge appears only at the end, unexplained.
                  liveWaitingFareMnt:
                      widget.kmTariffMnt == null || !_meter.isWaiting
                      ? null
                      : _meter.waitingFareMnt,
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
        onConfirm: _confirmFare,
        onDecline: _declineFare,
      ),
      _ActiveTripStep.rating => _RatingView(
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

class _TrackingView extends StatelessWidget {
  final TripPhase phase;
  final TripRole role;
  final ll.LatLng? selfPosition;
  final ll.LatLng? counterpartyPosition;
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
    final phaseLabel = switch (phase) {
      TripPhase.enRouteToPickup => l.tripPhaseEnRouteToPickup,
      TripPhase.tripInProgress => l.tripPhaseInProgress,
      TripPhase.arrived => l.tripPhaseArrived,
    };
    final markers = <Marker>[
      if (selfPosition != null)
        Marker(
          point: selfPosition!,
          child: const Icon(Icons.my_location, color: TakhiColors.gold),
        ),
      if (counterpartyPosition != null)
        Marker(
          point: counterpartyPosition!,
          child: const Icon(Icons.directions_car, color: TakhiColors.ink),
        ),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(TakhiSpace.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  phaseLabel,
                  style: const TextStyle(
                    color: TakhiColors.gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.share, color: TakhiColors.gold),
                tooltip: l.shareTripAction,
                onPressed: onShareTrip,
              ),
              IconButton(
                icon: const Icon(Icons.call, color: TakhiColors.gold),
                tooltip: AppLocalizations.of(context)!.startCallAction,
                onPressed: onStartCall,
              ),
              SosButton(lastFix: lastFix),
            ],
          ),
        ),
        if (liveFareMnt != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TakhiSpace.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.meteredLiveFareLabel(groupedMnt(liveFareMnt!)),
                    // `numeric` rather than a hand-set size: its tabular
                    // figures are what stop a fare that reprices on every
                    // GPS fix from re-flowing under the reader's eye.
                    style: TakhiType.numeric.copyWith(color: TakhiColors.gold),
                  ),
                  if (liveWaitingFareMnt != null)
                    Text(
                      l.meteredLiveWaitingLabel(
                        groupedMnt(liveWaitingFareMnt!),
                      ),
                      style: TakhiType.support.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (receivedVoiceNotes.isNotEmpty)
          _VoiceNoteBanner(
            notes: receivedVoiceNotes,
            playingIndex: playingVoiceNoteIndex,
            onPlay: onPlayVoiceNote,
          ),
        Expanded(
          child: RideMap(
            initialCenter:
                selfPosition ??
                ll.LatLng(
                  defaultCityConfig.centerLat,
                  defaultCityConfig.centerLon,
                ),
            layers: [MarkerLayer(markers: markers)],
          ),
        ),
        if (role == TripRole.driver)
          Padding(
            padding: const EdgeInsets.all(TakhiSpace.md),
            child: switch (phase) {
              TripPhase.enRouteToPickup => PrimaryButton(
                label: l.markPassengerBoardedAction,
                onPressed: onMarkPassengerBoarded,
              ),
              TripPhase.tripInProgress => PrimaryButton(
                label: l.endTripAction,
                onPressed: onEndTrip,
              ),
              TripPhase.arrived => const SizedBox.shrink(),
            },
          ),
      ],
    );
  }
}

class _RatingView extends StatelessWidget {
  final int selectedStars;
  final ValueChanged<int> onStarSelected;
  final TextEditingController commentController;
  final bool submitting;
  final VoidCallback onSubmit;

  const _RatingView({
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
    return Padding(
      padding: const EdgeInsets.all(TakhiSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.rateTripTitle,
            style: const TextStyle(
              color: TakhiColors.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: TakhiSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_starCount, (i) {
              final filled = i < selectedStars;
              return IconButton(
                icon: Icon(filled ? Icons.star : Icons.star_border),
                color: TakhiColors.gold,
                onPressed: () => onStarSelected(i + 1),
              );
            }),
          ),
          const SizedBox(height: TakhiSpace.sm),
          TextField(
            controller: commentController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: TakhiSpace.md),
          PrimaryButton(
            label: l.submitRatingAction,
            loading: submitting,
            // `buildTripReceipt` (takhi_events.dart) throws `ArgumentError`
            // for `ratingStars` outside 1..5, and `_selectedStars` starts
            // at 0 -- disable the button (rather than leaving it tappable
            // and crashing `_submitRating`) until a star is picked, per
            // `PrimaryButton`'s own documented "pass null for nothing to
            // do yet" convention (mirrors `_OfferDialog._submit`'s guard
            // against a bogus zero-value publish in driver_inbox_page.dart).
            onPressed: selectedStars > 0 ? onSubmit : null,
          ),
        ],
      ),
    );
  }
}

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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fareDeclined ? l.meteredFareDeclinedHint : l.tripReceiptPublished,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TakhiColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!fareDeclined) ...[
              const SizedBox(height: TakhiSpace.xs),
              Text(l.agreedPriceLabel(groupedMnt(agreedPriceMnt))),
              const SizedBox(height: TakhiSpace.md),
              if (role == TripRole.driver)
                const DriverQrDisplay()
              else
                Text(l.payWithQrOrCashHint),
            ],
            if (onFinished != null) ...[
              const SizedBox(height: TakhiSpace.xl),
              PrimaryButton(label: l.finishTripAction, onPressed: onFinished),
            ],
          ],
        ),
      ),
    );
  }
}

/// Spec §7.2's passenger-only gate between the metered trip ending and the
/// rating step: shows the driver-reported, GPS-computed final fare and
/// requires an explicit confirm before a trip receipt is ever published
/// (declining routes straight to [_DoneView] with [_DoneView.fareDeclined],
/// publishing nothing).
class _FareConfirmView extends StatelessWidget {
  final int finalFareMnt;

  /// The waiting half of [finalFareMnt] and the time behind it, as the
  /// driver measured them (spec §7.4). Zero means the trip never stood
  /// still long enough to be billed for it -- or that the driver charges
  /// nothing for waiting -- and in both cases there is nothing to break
  /// down, so this view stays the single figure it was before §7.4.
  final int waitingFareMnt;
  final int waitingSeconds;

  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  const _FareConfirmView({
    required this.finalFareMnt,
    required this.waitingFareMnt,
    required this.waitingSeconds,
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
    final distanceFareMnt = finalFareMnt - waitingFareMnt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.meteredFareConfirmTitle,
              style: const TextStyle(
                color: TakhiColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: TakhiSpace.sm),
            Text(
              l.agreedPriceLabel(groupedMnt(finalFareMnt)),
              // The same money role `TaximeterPage`'s own summary total
              // uses, so the figure the driver reads at the end of the
              // trip and the one the passenger is asked to sign are set
              // identically. Stays a step above the `title`-sized
              // breakdown rows below it.
              style: TakhiType.numeric.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (waitingFareMnt > 0) ...[
              const SizedBox(height: TakhiSpace.md),
              _FareBreakdownRow(
                label: l.meterSummaryDistanceFareRow,
                amountMnt: distanceFareMnt,
              ),
              const SizedBox(height: TakhiSpace.xs),
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
            const SizedBox(height: TakhiSpace.xl),
            PrimaryButton(
              label: l.meteredFareConfirmAction,
              onPressed: onConfirm,
            ),
            const SizedBox(height: TakhiSpace.sm),
            OutlinedButton(
              onPressed: onDecline,
              child: Text(l.meteredFareDeclineAction),
            ),
          ],
        ),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TakhiType.body.copyWith(color: onSurface)),
        ),
        const SizedBox(width: TakhiSpace.sm),
        Text(
          l.meterFareLabel(groupedMnt(amountMnt)),
          style: TakhiType.title.copyWith(color: onSurface),
        ),
      ],
    );
  }
}

/// One tappable chip per received voice note (spec §7.3-③), shown above
/// the map for as long as `_receivedVoiceNotes` is non-empty -- the
/// persistent play-back UI half of Plan 5 review CRITICAL-3's fix (the
/// transient half is the `SnackBar` `ActiveTripView._startTracking`'s
/// voice-note listener already shows the moment one arrives).
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TakhiSpace.sm,
        vertical: TakhiSpace.xxs,
      ),
      child: Wrap(
        spacing: TakhiSpace.xs,
        runSpacing: TakhiSpace.xxs,
        children: [
          for (var i = 0; i < notes.length; i++)
            ActionChip(
              avatar: Icon(
                playingIndex == i ? Icons.stop : Icons.play_arrow,
                color: TakhiColors.ink,
              ),
              backgroundColor: TakhiColors.gold,
              label: Text(
                '${l.playVoiceNoteAction} '
                '(${notes[i].payload.durationSeconds}s)',
                style: const TextStyle(color: TakhiColors.ink),
              ),
              onPressed: () => onPlay(i),
            ),
        ],
      ),
    );
  }
}
