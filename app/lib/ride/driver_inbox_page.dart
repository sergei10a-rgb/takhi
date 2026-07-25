// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../config/city_config.dart';
import '../identity/identity_service.dart' show Identity;
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/nearby_requests_layer.dart';
import '../map/ride_map.dart';
import '../payment/driver_qr_capture_page.dart';
import '../profile/profile_providers.dart';
import '../widgets/confirm_leave_scope.dart';
import '../widgets/primary_button.dart';
import 'active_trip_view.dart';
import 'driver_inbox_service.dart';
import 'handoff_service.dart';
import 'ride_dm_payload.dart';
import 'ride_providers.dart';
import 'trip_phase.dart';
import 'trip_role.dart';

/// The driver's "listen for nearby calls" flow (spec §7.1 steps 2-4): see
/// requests within a 9-cell geohash neighborhood on a map, tap one to
/// send an offer, then wait -- if the passenger picks this driver, their
/// exact pickup point arrives here as a handoff.
///
/// Simplification: this MVP screen tracks at most one active engagement
/// -- the first handoff it receives is shown as "awarded", regardless of
/// how many concurrent offers were sent. A driver dashboard tracking
/// several simultaneous pending offers is a reasonable follow-up, not
/// required for Plan 3 (see Self-Review).
class DriverInboxPage extends ConsumerStatefulWidget {
  const DriverInboxPage({super.key});

  @override
  ConsumerState<DriverInboxPage> createState() => _DriverInboxPageState();
}

class _DriverInboxPageState extends ConsumerState<DriverInboxPage> {
  ll.LatLng _myLocation = ll.LatLng(
    defaultCityConfig.centerLat,
    defaultCityConfig.centerLon,
  );
  final List<RideRequestListing> _listings = [];
  ReceivedHandoff? _awardedHandoff;
  StreamSubscription<RideRequestListing>? _listingsSubscription;
  StreamSubscription<ReceivedHandoff>? _handoffSubscription;
  int? _lastOfferedPriceMnt;

  /// Spec §7.2: the km-tariff this driver actually attached to the offer
  /// the passenger selected, if any -- `null` for a plain fixed-price
  /// offer. Threaded into `ActiveTripView.kmTariffMnt` alongside
  /// `_lastOfferedPriceMnt` below, mirroring that field's exact reasoning.
  int? _lastOfferedKmTariffMnt;
  bool _activeTrip = false;

  /// Whether the active trip still holds work a back gesture would
  /// destroy -- true from the moment `ActiveTripView` is mounted until it
  /// reports (through `onTripSettled`) that the receipt is published or
  /// declined. Drives `ConfirmLeaveScope.enabled` below: everything this
  /// screen knows about a live trip (the passenger's exact pickup point,
  /// the price this driver offered, the GPS track behind the receipt)
  /// exists only in memory, so leaving mid-trip is unrecoverable -- while
  /// leaving the *finished* screen costs nothing and must not prompt.
  bool _tripInFlight = true;

  @override
  void initState() {
    super.initState();
    // `currentIdentityProvider` is a `FutureProvider` -- `.future` awaits
    // its creation/resolution regardless of whether anything has already
    // `ref.watch`ed it (unlike `ref.read(...).valueOrNull`, which would
    // see it still `AsyncLoading` and silently no-op the very first time
    // this page is reached, since `initState` always runs before this
    // widget's own `build`).
    ref.read(currentIdentityProvider.future).then((identity) {
      if (identity == null || !mounted) return;
      _wireStreams(identity);
    });
  }

  void _wireStreams(Identity identity) {
    _listingsSubscription = ref
        .read(driverInboxServiceProvider)
        .nearbyRequests(
          driverLat: _myLocation.latitude,
          driverLon: _myLocation.longitude,
          nowSeconds: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
        )
        .listen((listing) {
          if (!mounted) return;
          setState(() => _listings.add(listing));
        });
    _handoffSubscription = ref
        .read(handoffServiceProvider)
        .receiveHandoffs(identity.pubHex, identity.privHex)
        .listen((handoff) {
          if (!mounted) return;
          setState(() => _awardedHandoff = handoff);
        });
  }

  @override
  void dispose() {
    // Without cancelling both, `RelayPool.subscribe`'s
    // `StreamController.onCancel` (relay_pool.dart) never fires -- every
    // visit to this screen would otherwise leak two open relay
    // subscriptions for the app's remaining lifetime.
    unawaited(_listingsSubscription?.cancel());
    unawaited(_handoffSubscription?.cancel());
    super.dispose();
  }

  Future<void> _sendOffer(RideRequestListing listing) async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (identity == null) return;
    // Spec §7.2: the metered-pricing toggle only ever appears when this
    // driver actually has a published/saved km-tariff to offer -- read it
    // once, before the dialog opens, rather than inside `_OfferDialog`
    // itself, so that widget stays a plain `StatefulWidget` with no
    // provider dependency of its own.
    final driverProfile = await ref
        .read(driverProfileServiceProvider)
        .loadLocalProfile();
    final driverKmTariffMnt = driverProfile?.kmTariffMnt;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _OfferDialog(
        driverKmTariffMnt: driverKmTariffMnt,
        onSubmit: (priceMnt, etaMinutes, vehicle, kmTariffMnt) async {
          setState(() {
            _lastOfferedPriceMnt = priceMnt;
            _lastOfferedKmTariffMnt = kmTariffMnt;
          });
          await ref
              .read(offerServiceProvider)
              .sendOffer(
                driverPrivHex: identity.privHex,
                passengerPubHex: listing.event.pubkey,
                offer: RideOfferPayload(
                  rideRequestId: listing.rideRequestId,
                  priceMnt: priceMnt,
                  etaMinutes: etaMinutes,
                  vehicleDescription: vehicle,
                  kmTariffMnt: kmTariffMnt,
                ),
                now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              );
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  /// Puts this page back into its between-trips state -- the
  /// nearby-requests map -- once the driver taps "finish trip" on
  /// `ActiveTripView`'s final screen. Without it `_awardedHandoff` and
  /// `_activeTrip` were set once and never cleared, so a shift ended with
  /// its first passenger: the finished-trip screen had no control, and no
  /// route back to listening for calls.
  void _finishTrip() => setState(() {
    _awardedHandoff = null;
    _activeTrip = false;
    _tripInFlight = true;
    _lastOfferedPriceMnt = null;
    _lastOfferedKmTariffMnt = null;
  });

  /// Runs while the leave dialog's answer is still on the stack, just
  /// before the route pops. `leaveTripMessage` promises the other side is
  /// told, and until this existed only the passenger side kept that
  /// promise: a driver who walked out mid-trip left the passenger's
  /// `ActiveTripView` waiting forever on a phase transition that would
  /// never come, burning GPS and relay traffic on a "driver is on the way"
  /// screen with no driver.
  ///
  /// The signal is a `TripPhase.arrived` status rather than a
  /// `RideCancelPayload` because that is the one message the passenger's
  /// screen actually listens for (`ActiveTripView._startTracking`): it
  /// stops their tracking and moves them to the rating step, exactly as a
  /// real trip end would. This driver publishes no receipt of their own,
  /// so the pair stays unpaired -- which is precisely what walking out
  /// deserves under `reputation.dart`'s pairing rule.
  void _abandonTrip() {
    final handoff = _awardedHandoff;
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (handoff == null || identity == null) return;
    // Deliberately not awaited: the send outlives this page, and the relay
    // pool it publishes through is app-scoped, not page-scoped (mirrors
    // `PassengerRidePage._abandonRequest`).
    unawaited(
      ref
          .read(tripStatusServiceProvider)
          .sendStatus(
            driverPrivHex: identity.privHex,
            passengerPubHex: handoff.senderPubkey,
            tripId: handoff.payload.tripId,
            phase: TripPhase.arrived,
            now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // `initState` already awaits `currentIdentityProvider.future` to wire
    // the streams (see below); this `ref.watch` just keeps this widget
    // subscribed for rebuilds if identity state ever changes later (e.g.
    // sign-out), matching the pattern in `PassengerRidePage`.
    ref.watch(currentIdentityProvider);
    // One guard for the whole page rather than one per branch: only a
    // running trip has anything to lose, and the map/awarded screens hold
    // nothing a re-entry could not rebuild. Wrapping the `Scaffold` (never
    // the whole page) keeps the dialog under a `MaterialLocalizations`
    // ancestor -- see `ConfirmLeaveScope`'s own doc comment.
    return ConfirmLeaveScope(
      enabled: _activeTrip && _tripInFlight,
      title: l.leaveTripTitle,
      message: l.leaveTripMessage,
      onConfirmedLeave: _abandonTrip,
      child: _buildScaffold(l),
    );
  }

  Widget _buildScaffold(AppLocalizations l) {
    final handoff = _awardedHandoff;
    if (_activeTrip && handoff != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l.appName),
          // Kept here too, not just on the two screens before it: the
          // driver's payment QR is what the passenger scans at the *end*
          // of the trip, so dropping this action mid-trip left the one
          // moment it is actually needed with no way to reach it.
          actions: [_QrSettingsAction(tooltip: l.qrCaptureTitle)],
        ),
        body: ActiveTripView(
          role: TripRole.driver,
          tripId: handoff.payload.tripId,
          counterpartyPubHex: handoff.senderPubkey,
          agreedPriceMnt: _lastOfferedPriceMnt ?? 0,
          counterpartyPhone: handoff.payload.phone,
          kmTariffMnt: _lastOfferedKmTariffMnt,
          onTripSettled: () => setState(() => _tripInFlight = false),
          onFinished: _finishTrip,
        ),
      );
    }
    if (handoff != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l.appName),
          actions: [_QrSettingsAction(tooltip: l.qrCaptureTitle)],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.handoffReceivedTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(handoff.payload.plusCode),
                Text(handoff.payload.landmarkText, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: l.viewActiveTripAction,
                  onPressed: () => setState(() {
                    _activeTrip = true;
                    _tripInFlight = true;
                  }),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appName),
        actions: [_QrSettingsAction(tooltip: l.qrCaptureTitle)],
      ),
      body: RideMap(
        initialCenter: _myLocation,
        onCenterChanged: (c) => setState(() => _myLocation = c),
        layers: [NearbyRequestsLayer(listings: _listings, onTap: _sendOffer)],
      ),
    );
  }
}

class _OfferDialog extends StatefulWidget {
  final Future<void> Function(
    int priceMnt,
    int etaMinutes,
    String vehicle,
    int? kmTariffMnt,
  )
  onSubmit;

  /// See `_DriverInboxPageState._sendOffer`'s doc comment -- `null` means
  /// this driver has no saved km-tariff, so the metered-pricing toggle
  /// (spec §7.2) is not offered at all.
  final int? driverKmTariffMnt;

  const _OfferDialog({required this.onSubmit, this.driverKmTariffMnt});

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  final _price = TextEditingController();
  final _eta = TextEditingController();
  final _vehicle = TextEditingController();
  bool _submitting = false;
  bool _metered = false;

  @override
  void dispose() {
    _price.dispose();
    _eta.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final price = int.tryParse(_price.text);
    final eta = int.tryParse(_eta.text);
    // A blank or non-numeric field used to silently fall back to `0` via
    // `?? 0`, sending a bogus zero-price/zero-ETA offer with no feedback.
    // No-op instead until both fields actually parse.
    if (price == null || eta == null) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        price,
        eta,
        _vehicle.text,
        _metered ? widget.driverKmTariffMnt : null,
      );
    } finally {
      // `widget.onSubmit` pops the surrounding dialog on success, which
      // disposes this state before we get back here -- guard the
      // post-await `setState` (dart/coding-style.md's `context.mounted`
      // rule, applied to widget state instead of `BuildContext`).
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final driverKmTariffMnt = widget.driverKmTariffMnt;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.offerPriceFieldLabel),
          ),
          TextField(
            controller: _eta,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.offerEtaFieldLabel),
          ),
          TextField(
            controller: _vehicle,
            decoration: InputDecoration(labelText: l.offerVehicleFieldLabel),
          ),
          // Spec §7.2: only offered when this driver actually has a
          // km-tariff to attach -- there is deliberately no "set a tariff
          // right here" shortcut; that belongs to `DriverProfilePage`
          // alone (single source of truth for the published profile).
          // Without the `else` the option did not merely disappear, it
          // disappeared *silently*: a driver who meant to offer a metered
          // price saw a dialog with no such choice and no reason given.
          // The hint says where the tariff lives without becoming the
          // shortcut this comment rules out.
          if (driverKmTariffMnt != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _metered,
              onChanged: (v) => setState(() => _metered = v ?? false),
              title: Text(l.meteredOfferToggleLabel),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                l.meteredOfferNoTariffHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      actions: [
        // Until this existed the only ways out of this dialog were a
        // barrier tap and the hardware back button -- neither of them
        // visible, so a driver who tapped the wrong request on the map had
        // no on-screen way back and could easily send an offer just to be
        // rid of it. Disabled mid-publish so a stray tap cannot tear the
        // dialog down while `sendOffer` is still in flight.
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancelAction),
        ),
        PrimaryButton(
          label: l.sendOfferAction,
          loading: _submitting,
          // `_submit` is `Future<void>`, but `PrimaryButton.onPressed` is
          // a `VoidCallback` -- `unawaited()` makes the fire-and-forget
          // explicit (dart/coding-style.md), instead of the Future (and
          // any error `sendOffer` throws) being silently dropped.
          onPressed: () => unawaited(_submit()),
        ),
      ],
    );
  }
}

/// Reaches [DriverQrCapturePage] (Task 5) from the driver's inbox AppBar so
/// they can set or update their locally stored bank QR without leaving the
/// listen-for-calls flow.
class _QrSettingsAction extends StatelessWidget {
  final String tooltip;

  const _QrSettingsAction({required this.tooltip});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.qr_code),
    tooltip: tooltip,
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DriverQrCapturePage())),
  );
}
