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
import '../geo/gps_track.dart';
import '../identity/identity_service.dart' show Identity;
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/ride_map.dart';
import '../meter/fare_calc.dart';
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

  const ActiveTripView({
    super.key,
    required this.role,
    required this.tripId,
    required this.counterpartyPubHex,
    required this.agreedPriceMnt,
    this.counterpartyPhone,
    this.kmTariffMnt,
  });

  @override
  ConsumerState<ActiveTripView> createState() => _ActiveTripViewState();
}

class _ActiveTripViewState extends ConsumerState<ActiveTripView> {
  _ActiveTripStep _step = _ActiveTripStep.tracking;
  TripPhase _phase = TripPhase.enRouteToPickup;
  final GpsTrackAccumulator _track = GpsTrackAccumulator();
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
    _track.addFix(fix);
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
    final kmTariffMnt = widget.kmTariffMnt;
    final finalFareMnt = kmTariffMnt == null
        ? null
        : computeFareMnt(
            mntPerKm: kmTariffMnt,
            distanceMeters: _track.distanceMeters,
          );
    if (finalFareMnt != null) _finalFareMnt = finalFareMnt;
    await ref
        .read(tripStatusServiceProvider)
        .sendStatus(
          driverPrivHex: identity.privHex,
          passengerPubHex: widget.counterpartyPubHex,
          tripId: widget.tripId,
          phase: TripPhase.arrived,
          finalFareMnt: finalFareMnt,
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

  void _stopTrackingAndMoveToRating() {
    // Without cancelling these, `RelayPool.subscribe`'s
    // `StreamController.onCancel` (relay_pool.dart) never fires for either
    // subscription -- mirrors `PassengerRidePage`/`DriverInboxPage`'s own
    // `dispose()` reasoning, just triggered by a phase transition instead
    // of the widget itself being torn down.
    unawaited(_gpsSubscription?.cancel());
    unawaited(_liveLocationSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_voiceNoteSubscription?.cancel());
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
  void _declineFare() => setState(() {
    _fareDeclined = true;
    _step = _ActiveTripStep.done;
  });

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
            distanceMeters: _track.distanceMeters,
            durationSeconds: _track.durationSeconds,
            priceMnt: _finalFareMnt ?? widget.agreedPriceMnt,
            comment: _commentController.text,
          );
      if (!mounted) return;
      setState(() => _step = _ActiveTripStep.done);
    } finally {
      if (mounted) setState(() => _submittingRating = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    unawaited(_gpsSubscription?.cancel());
    unawaited(_liveLocationSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_voiceNoteSubscription?.cancel());
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
                  lastFix: _track.fixes.isEmpty ? null : _track.fixes.last,
                  // Spec §7.2: both sides show their own running fare, from
                  // their own GPS track -- `null` in fixed-price mode.
                  liveFareMnt: widget.kmTariffMnt == null
                      ? null
                      : computeFareMnt(
                          mntPerKm: widget.kmTariffMnt!,
                          distanceMeters: _track.distanceMeters,
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
          padding: const EdgeInsets.all(12),
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l.meteredLiveFareLabel(liveFareMnt!),
                style: const TextStyle(
                  color: TakhiColors.gold,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
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
            padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          TextField(
            controller: commentController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
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

  const _DoneView({
    required this.role,
    required this.agreedPriceMnt,
    this.fareDeclined = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 8),
              Text(l.agreedPriceLabel(agreedPriceMnt)),
              const SizedBox(height: 16),
              if (role == TripRole.driver)
                const DriverQrDisplay()
              else
                Text(l.payWithQrOrCashHint),
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
  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  const _FareConfirmView({
    required this.finalFareMnt,
    required this.onConfirm,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 12),
            Text(
              l.agreedPriceLabel(finalFareMnt),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: l.meteredFareConfirmAction,
              onPressed: onConfirm,
            ),
            const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
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
