// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../geo/geo_providers.dart';
import '../geo/gps_fix.dart';
import '../geo/gps_track.dart';
import '../identity/identity_service.dart' show Identity;
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/default_city_center.dart';
import '../map/ride_map.dart';
import '../payment/driver_qr_display.dart';
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

enum _ActiveTripStep { tracking, rating, done }

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

  const ActiveTripView({
    super.key,
    required this.role,
    required this.tripId,
    required this.counterpartyPubHex,
    required this.agreedPriceMnt,
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

  ll.LatLng? _selfPosition;
  ll.LatLng? _counterpartyPosition;

  StreamSubscription<GpsFix>? _gpsSubscription;
  StreamSubscription<LiveLocation>? _liveLocationSubscription;
  StreamSubscription<ReceivedTripStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
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

    // Only the passenger side listens for phase transitions -- the driver
    // side is the one calling `sendStatus` (spec §7.1 steps 5-6).
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
              _stopTrackingAndMoveToRating();
            }
          });
    }
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
    await ref
        .read(tripStatusServiceProvider)
        .sendStatus(
          driverPrivHex: identity.privHex,
          passengerPubHex: widget.counterpartyPubHex,
          tripId: widget.tripId,
          phase: TripPhase.arrived,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
    _stopTrackingAndMoveToRating();
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
    if (!mounted) return;
    setState(() => _step = _ActiveTripStep.rating);
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
            distanceMeters: _track.distanceMeters,
            durationSeconds: _track.durationSeconds,
            priceMnt: widget.agreedPriceMnt,
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
            : _TrackingView(
                phase: _phase,
                role: widget.role,
                selfPosition: _selfPosition,
                counterpartyPosition: _counterpartyPosition,
                onMarkPassengerBoarded: _markPassengerBoarded,
                onEndTrip: _endTrip,
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
        agreedPriceMnt: widget.agreedPriceMnt,
      ),
    };
  }
}

class _TrackingView extends StatelessWidget {
  final TripPhase phase;
  final TripRole role;
  final ll.LatLng? selfPosition;
  final ll.LatLng? counterpartyPosition;
  final VoidCallback onMarkPassengerBoarded;
  final VoidCallback onEndTrip;

  const _TrackingView({
    required this.phase,
    required this.role,
    required this.selfPosition,
    required this.counterpartyPosition,
    required this.onMarkPassengerBoarded,
    required this.onEndTrip,
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
          child: Text(
            phaseLabel,
            style: const TextStyle(
              color: TakhiColors.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: RideMap(
            initialCenter: selfPosition ?? defaultCityCenter,
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
  const _DoneView({required this.role, required this.agreedPriceMnt});

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
              l.tripReceiptPublished,
              style: const TextStyle(
                color: TakhiColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(l.agreedPriceLabel(agreedPriceMnt)),
            const SizedBox(height: 16),
            if (role == TripRole.driver)
              const DriverQrDisplay()
            else
              Text(l.payWithQrOrCashHint),
          ],
        ),
      ),
    );
  }
}
