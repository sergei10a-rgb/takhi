// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../call/call_providers.dart';
import '../config/city_config.dart';
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/location_picker.dart';
import '../theme/takhi_theme.dart';
import '../widgets/confirm_leave_scope.dart';
import '../widgets/primary_button.dart';
import 'active_trip_view.dart';
import 'offer_ranking.dart';
import 'offer_service.dart';
import 'ride_providers.dart';
import 'trip_role.dart';

enum _PassengerStep { pickup, destination, price, offers, done, activeTrip }

/// The passenger's full "call a ride" flow (spec §7.1): pick pickup, pick
/// destination, optionally name a price, publish, watch reputation-ranked
/// offers arrive live, select one. Ends once the exact-location handoff
/// is sent -- the trip itself (in-progress tracking, fare settlement) is
/// Plan 4.
class PassengerRidePage extends ConsumerStatefulWidget {
  const PassengerRidePage({super.key});

  @override
  ConsumerState<PassengerRidePage> createState() => _PassengerRidePageState();
}

class _PassengerRidePageState extends ConsumerState<PassengerRidePage> {
  _PassengerStep _step = _PassengerStep.pickup;
  PickedLocation _pickup = PickedLocation(
    lat: defaultCityConfig.centerLat,
    lon: defaultCityConfig.centerLon,
  );
  PickedLocation _destination = PickedLocation(
    lat: defaultCityConfig.centerLat,
    lon: defaultCityConfig.centerLon,
  );
  final _priceController = TextEditingController();
  String? _rideRequestId;
  String? _tripId;
  final List<RideOffer> _offers = [];
  final Map<String, List<TripReceipt>> _receiptsCache = {};
  RankedRideOffer? _selected;
  StreamSubscription<RideOffer>? _offersSubscription;

  /// Whether the active trip still holds work a back gesture would
  /// destroy -- true from the moment `ActiveTripView` is mounted until it
  /// reports (through `onTripSettled`) that the receipt is published or
  /// the fare declined. Mirrors `DriverInboxPage._tripInFlight` exactly:
  /// leaving mid-trip is unrecoverable and must be confirmed, but leaving
  /// the *finished* screen costs nothing -- and, crucially, must not send
  /// the driver a cancellation for a trip that already ended (see
  /// [_abandonRequest] and [_isRequestLive]).
  bool _tripInFlight = true;

  @override
  void dispose() {
    _priceController.dispose();
    // Without this, `RelayPool.subscribe`'s `StreamController.onCancel`
    // (relay_pool.dart) never fires -- the relay subscription this page
    // opened in `_publish` stays open for the app's remaining lifetime.
    unawaited(_offersSubscription?.cancel());
    super.dispose();
  }

  Future<void> _publish() async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (identity == null) return;
    final priceMnt = int.tryParse(_priceController.text);
    final event = await ref
        .read(rideRequestServiceProvider)
        .publishRequest(
          privHex: identity.privHex,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          pickupLat: _pickup.lat,
          pickupLon: _pickup.lon,
          destLat: _destination.lat,
          destLon: _destination.lon,
          offeredMnt: priceMnt,
        );
    if (!mounted) return;
    setState(() {
      _rideRequestId = event.id;
      _step = _PassengerStep.offers;
    });
    _offersSubscription = ref
        .read(offerServiceProvider)
        .receiveOffers(identity.pubHex, identity.privHex)
        .listen((offer) async {
          if (offer.payload.rideRequestId != _rideRequestId) return;
          if (!mounted) return;
          setState(() => _offers.add(offer));
          if (!_receiptsCache.containsKey(offer.driverPubkey)) {
            final receipts = await ref
                .read(tripReceiptRepositoryProvider)
                .receiptsAbout(offer.driverPubkey);
            if (!mounted) return;
            setState(() => _receiptsCache[offer.driverPubkey] = receipts);
          }
        });
  }

  /// Whether the current step has already told the outside world about
  /// this ride: from [_PassengerStep.offers] on, drivers are watching the
  /// published request (and past [_select], one of them is driving over),
  /// so a stray back gesture has to be confirmed and cleaned up rather
  /// than silently dropping the page.
  ///
  /// The active-trip step is the one arm that can flip back off: once the
  /// receipt is published (or declined) there is nothing left to lose, so
  /// back must neither prompt nor -- far worse -- tell the driver a
  /// finished ride was cancelled.
  bool get _isRequestLive => switch (_step) {
    _PassengerStep.pickup ||
    _PassengerStep.destination ||
    _PassengerStep.price => false,
    _PassengerStep.offers || _PassengerStep.done => true,
    _PassengerStep.activeTrip => _tripInFlight,
  };

  /// Walks one step back. Nothing the passenger entered is cleared --
  /// `_pickup`, `_destination` and `_priceController` all survive, so the
  /// earlier step comes back showing the point they picked and the price
  /// they typed rather than a blank map.
  void _goBackTo(_PassengerStep step) => setState(() => _step = step);

  /// Backs out of a request that is already on the relays and returns to
  /// the price step. There is nothing to retract -- the public kind-20177
  /// event is ephemeral and simply expires (spec §7.1) -- so this only
  /// tears down the local subscription and the offers collected so far.
  /// Republishing therefore leaves the old request visible to drivers
  /// until its expiry, which is the lesser evil against a passenger stuck
  /// staring at an offer list they cannot escape or reprice.
  void _withdrawRequest() {
    unawaited(_offersSubscription?.cancel());
    _offersSubscription = null;
    setState(() {
      _offers.clear();
      _receiptsCache.clear();
      _rideRequestId = null;
      _step = _PassengerStep.price;
    });
  }

  /// Runs while the leave dialog's answer is still on the stack, just
  /// before the route pops -- late enough to be sure the passenger meant
  /// it, early enough to still read the state it is tearing down. If a
  /// driver was already chosen they are told the ride is off (spec §7.5)
  /// instead of driving to a pickup nobody is waiting at.
  void _abandonRequest() {
    unawaited(_offersSubscription?.cancel());
    _offersSubscription = null;
    final selected = _selected;
    final rideRequestId = _rideRequestId;
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (selected == null || rideRequestId == null || identity == null) return;
    // Deliberately not awaited: the send outlives this page, and the
    // relay pool it publishes through is app-scoped, not page-scoped.
    unawaited(
      ref
          .read(rideRequestServiceProvider)
          .cancelWithDriver(
            privHex: identity.privHex,
            driverPubHex: selected.offer.driverPubkey,
            rideRequestId: rideRequestId,
            now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
    );
  }

  /// Puts this page back into its between-rides state -- the pickup
  /// picker -- once the passenger taps "finish trip" on `ActiveTripView`'s
  /// final screen, mirroring `DriverInboxPage._finishTrip`. Without it the
  /// finished-trip screen had no control at all and the only way out was
  /// the guarded back gesture.
  void _finishTrip() {
    // The offers subscription outlives `_select`, so a second ride
    // published from the reset page would otherwise overwrite (and leak)
    // this handle -- same reasoning as [_withdrawRequest].
    unawaited(_offersSubscription?.cancel());
    _offersSubscription = null;
    setState(() {
      _offers.clear();
      _receiptsCache.clear();
      _rideRequestId = null;
      _tripId = null;
      _selected = null;
      _tripInFlight = true;
      _step = _PassengerStep.pickup;
    });
  }

  /// Last stop before [_select] hands a driver the passenger's exact
  /// pickup coordinates, landmark text and -- if sharing is on -- their
  /// phone number. A single stray tap on a scrolling offer list would
  /// otherwise leak all of that irreversibly, so the offer being accepted
  /// is spelled out and has to be confirmed first.
  Future<bool> _confirmSelect(RankedRideOffer ranked) async {
    final l = AppLocalizations.of(context)!;
    final payload = ranked.offer.payload;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.confirmSelectOfferTitle),
        content: Text(
          l.confirmSelectOfferMessage(
            payload.vehicleDescription,
            payload.priceMnt,
            payload.etaMinutes,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.confirmSelectOfferAction),
          ),
        ],
      ),
    );
    // `null` is a barrier tap or a back press on the dialog itself --
    // treated as "no", the safe answer for an irreversible disclosure.
    return confirmed ?? false;
  }

  Future<void> _select(RankedRideOffer ranked) async {
    if (!await _confirmSelect(ranked) || !mounted) return;
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    // Read into a local rather than banging `_rideRequestId` below: the
    // awaits in between give `_withdrawRequest` a chance to null the
    // field, and the handoff must name the request the offer was made
    // against either way.
    final rideRequestId = _rideRequestId;
    if (identity == null || rideRequestId == null) return;
    final phoneShareEnabled = await ref
        .read(phoneShareSettingsStoreProvider)
        .isEnabled();
    final ownPhone = phoneShareEnabled
        ? await ref.read(phoneShareSettingsStoreProvider).loadOwnPhone()
        : null;
    final tripId = await ref
        .read(handoffServiceProvider)
        .sendHandoff(
          passengerPrivHex: identity.privHex,
          driverPubHex: ranked.offer.driverPubkey,
          rideRequestId: rideRequestId,
          lat: _pickup.lat,
          lon: _pickup.lon,
          landmarkText: _pickup.landmarkText,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          phone: ownPhone,
        );
    if (!mounted) return;
    setState(() {
      _selected = ranked;
      _tripId = tripId;
      _step = _PassengerStep.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Warms up `currentIdentityProvider` (start its future resolving) on
    // first build, rather than only reading it inside `_publish`/`_select`
    // -- those use `ref.read`, which would otherwise create the provider
    // lazily right when it's needed and see it still `AsyncLoading` the
    // first time this page is reached without HomePage (which already
    // `ref.watch`es it) having warmed it up first, e.g. a standalone
    // widget test.
    ref.watch(currentIdentityProvider);
    final selected = _selected;
    final tripId = _tripId;
    return _guardBack(
      l,
      Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(title: Text(l.appName)),
        body: SafeArea(
          child: switch (_step) {
            // Keyed per step so returning to one rebuilds its picker from
            // the point stored here rather than reusing the other step's
            // live state -- which is also what kept the destination step
            // from inheriting the pickup's pin and landmark text.
            _PassengerStep.pickup => _LocationStep(
              key: const ValueKey(_PassengerStep.pickup),
              initialCenter: ll.LatLng(_pickup.lat, _pickup.lon),
              initialLandmarkText: _pickup.landmarkText,
              onChanged: (p) => _pickup = p,
              onNext: () => setState(() => _step = _PassengerStep.destination),
            ),
            _PassengerStep.destination => _LocationStep(
              key: const ValueKey(_PassengerStep.destination),
              initialCenter: ll.LatLng(_destination.lat, _destination.lon),
              initialLandmarkText: _destination.landmarkText,
              onChanged: (p) => _destination = p,
              onNext: () => setState(() => _step = _PassengerStep.price),
              onBack: () => _goBackTo(_PassengerStep.pickup),
            ),
            _PassengerStep.price => _PriceStep(
              controller: _priceController,
              onPublish: _publish,
              onBack: () => _goBackTo(_PassengerStep.destination),
            ),
            _PassengerStep.offers => _OffersStep(
              offers: _offers,
              receiptsFor: (pk) => _receiptsCache[pk] ?? const [],
              onSelect: _select,
              onBack: _withdrawRequest,
            ),
            // No in-body back past this point: a driver is committed, so
            // the only way out is the guarded route-level one, which
            // confirms first and then tells them (see [_abandonRequest]).
            _PassengerStep.done => _DoneStep(
              selected: selected,
              onStartTrip: () =>
                  setState(() => _step = _PassengerStep.activeTrip),
            ),
            _PassengerStep.activeTrip when tripId != null && selected != null =>
              ActiveTripView(
                role: TripRole.passenger,
                tripId: tripId,
                counterpartyPubHex: selected.offer.driverPubkey,
                agreedPriceMnt: selected.offer.payload.priceMnt,
                kmTariffMnt: selected.offer.payload.kmTariffMnt,
                // Both wired for the same reason the driver side wires
                // them: without `onTripSettled` the leave guard never
                // drops (so a finished ride still raises the dialog, and
                // confirming it would DM the driver a bogus cancellation),
                // and without `onFinished` the final screen renders no
                // button at all -- a dead end with no way back to the
                // start of the flow.
                onTripSettled: () => setState(() => _tripInFlight = false),
                onFinished: _finishTrip,
              ),
            // Unreachable: `_DoneStep.onStartTrip` is the only way into
            // this step and it only renders once `_select` has set both
            // fields. Kept as an arm rather than a `!` so that a future
            // teardown path clearing them cannot turn into a crash.
            _PassengerStep.activeTrip => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  /// Gives the route-level back gesture (the `AppBar` arrow, Android's
  /// hardware back, iOS' back swipe) the meaning the current step needs:
  /// leave the page on the first step, walk one step back while nothing
  /// has been published, and ask first once it has.
  ///
  /// Both guards are always present, exactly one of them live at a time --
  /// rather than swapping one for the other per step. A guard that comes
  /// and goes is a *changing ancestor*, and changing an ancestor remounts
  /// the whole subtree under it: when `onTripSettled` dropped the
  /// confirmation guard, `ActiveTripView` was rebuilt from scratch and the
  /// just-finished trip reappeared at its first phase.
  ///
  /// They never both refuse a pop: a step with somewhere to walk back to
  /// has nothing published yet, and a published step has no earlier step
  /// left to return to. The one case they do overlap on -- an inert
  /// [ConfirmLeaveScope] over a `PopScope` that refuses -- is why
  /// [ConfirmLeaveScope] checks `enabled` inside its callback too.
  Widget _guardBack(AppLocalizations l, Widget child) {
    final leavingRequest = _step == _PassengerStep.offers;
    final previous = switch (_step) {
      _PassengerStep.destination => _PassengerStep.pickup,
      _PassengerStep.price => _PassengerStep.destination,
      // Every other step either is the first one -- where back means
      // leaving and nothing is at stake yet -- or has already published,
      // where the only way out is the confirmed one above.
      _ => null,
    };
    return ConfirmLeaveScope(
      enabled: _isRequestLive,
      title: leavingRequest ? l.leaveRideRequestTitle : l.leaveTripTitle,
      message: leavingRequest ? l.leaveRideRequestMessage : l.leaveTripMessage,
      onConfirmedLeave: _abandonRequest,
      child: PopScope(
        canPop: previous == null,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || previous == null) return;
          _goBackTo(previous);
        },
        child: child,
      ),
    );
  }
}

class _LocationStep extends StatelessWidget {
  final ll.LatLng initialCenter;
  final String initialLandmarkText;
  final ValueChanged<PickedLocation> onChanged;
  final VoidCallback onNext;

  /// `null` on the first step, which has no earlier step to return to --
  /// there back simply leaves the page.
  final VoidCallback? onBack;

  const _LocationStep({
    super.key,
    required this.initialCenter,
    required this.initialLandmarkText,
    required this.onChanged,
    required this.onNext,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LocationPickerField(
            initialCenter: initialCenter,
            initialLandmarkText: initialLandmarkText,
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l.nextStep, onPressed: onNext),
          if (onBack != null) ...[
            const SizedBox(height: 12),
            _BackStepButton(onPressed: onBack!),
          ],
        ],
      ),
    );
  }
}

class _PriceStep extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onPublish;
  final VoidCallback onBack;
  const _PriceStep({
    required this.controller,
    required this.onPublish,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l.priceLabel,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l.publishRide, onPressed: onPublish),
          const SizedBox(height: 12),
          _BackStepButton(onPressed: onBack),
        ],
      ),
    );
  }
}

/// The wizard's secondary "one step back" action, matching the outlined
/// style the rest of the app uses under a [PrimaryButton]. Separate from
/// the route-level back gesture on purpose: this one always means "back
/// to the previous step", never "leave the page".
class _BackStepButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _BackStepButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      child: Text(AppLocalizations.of(context)!.backAction),
    ),
  );
}

class _OffersStep extends StatelessWidget {
  final List<RideOffer> offers;
  final List<TripReceipt> Function(String driverPubkey) receiptsFor;
  final ValueChanged<RankedRideOffer> onSelect;

  /// Withdraws the published request and returns to the price step --
  /// the way out when no offer arrives, or every one of them is too
  /// expensive.
  final VoidCallback onBack;

  const _OffersStep({
    required this.offers,
    required this.receiptsFor,
    required this.onSelect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ranked = rankRideOffers(offers, receiptsFor: receiptsFor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l.offersWaitingTitle,
            style: const TextStyle(
              color: TakhiColors.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: ranked.length,
            itemBuilder: (context, i) {
              final r = ranked[i];
              return ListTile(
                title: Text(
                  l.offerSummary(
                    r.offer.payload.priceMnt,
                    r.offer.payload.etaMinutes,
                  ),
                ),
                subtitle: Text(r.offer.payload.vehicleDescription),
                onTap: () => onSelect(r),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _BackStepButton(onPressed: onBack),
        ),
      ],
    );
  }
}

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
