// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../call/call_providers.dart';
import '../config/city_config.dart';
import '../geo/geo_providers.dart';
import '../geo/gps_fix.dart';
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/location_picker.dart';
import '../map/map_card.dart';
import '../map/trip_route_map.dart';
import '../map/trip_route_preview.dart';
import '../meter/meter_providers.dart';
import '../meter/money_format.dart';
import '../theme/takhi_theme.dart';
import '../widgets/accent_dot.dart';
import '../widgets/address_row.dart';
import '../widgets/confirm_leave_scope.dart';
import '../widgets/dialog_action_bar.dart';
import '../widgets/driver_portrait.dart';
import '../widgets/info_chip.dart';
import '../widgets/labeled_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'active_trip_view.dart';
import 'driver_offer_view.dart';
import 'offer_ranking.dart';
import 'offer_service.dart';
import 'ride_providers.dart';
import 'trip_role.dart';

/// Diameter of the mark that stands for the whole waiting state while no
/// offer has arrived. Large enough to be the thing the eye lands on -- the
/// step is otherwise a title over an empty half-screen, which reads as a
/// screen that failed to load rather than as one that is working.
const _kWaitingMarkSize = 72.0;

/// Height of the map on the price step.
///
/// Map geometry rather than a spacing token -- it is measured against how
/// much of a trip has to be legible at once. Shorter than the pickers'
/// window rather than taller, which is the opposite of the first instinct
/// and the thing a screenshot settled: a picker has to show the streets
/// AROUND one pin, while this map is fitted to two points and can say what
/// it needs to in a wider, shallower frame. At 300 the price field -- the
/// one thing this step asks for -- started below the fold.
const _kRouteMapHeight = 180.0;

/// Unit conversions for the two measured facts the price step states. Named
/// rather than inline so the arithmetic reads as what it is and cannot be
/// mistyped by an order of magnitude.
const _kMetresPerKm = 1000;
const _kSecondsPerMinute = 60;

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

  /// Where the device says it is, once a fix has arrived. Null until then,
  /// and null forever if location was refused -- in which case this flow
  /// behaves exactly as it did before GPS was wired in, with the map on the
  /// configured city and the rider panning to their own corner.
  ///
  /// The whole fix rather than just its coordinates: the map draws the
  /// reported accuracy as a ring around the dot, and dropping the accuracy
  /// here would leave the layer with no honest way to say how sure the
  /// phone actually is (`map/device_location_layer.dart`).
  GpsFix? _deviceFix;

  ll.LatLng? get _devicePosition {
    final fix = _deviceFix;
    return fix == null ? null : ll.LatLng(fix.lat, fix.lon);
  }

  /// The route between the two picked points and what it is likely to cost,
  /// once the routing service has answered (or failed, which is also an
  /// answer -- see [TripRoutePreview.isApproximate]). Null while in flight.
  TripRoutePreview? _routePreview;

  /// Bumped every time the price step is entered afresh, so a slow reply for
  /// a trip the rider has already walked back and re-picked cannot land on
  /// top of the current one. Same guard, and the same reasoning, as
  /// `taximeter_page.dart`'s `_destinationRequestSeq`.
  int _routeRequestSeq = 0;

  /// Held so the one-shot locate can be cancelled: [LocationSource.watch] is
  /// a *continuous* stream, and dropping the reference after the first fix
  /// would leave the GPS radio running behind a screen nobody is looking at.
  /// Same reasoning, and the same shape, as `HomePage._fixSubscription`.
  StreamSubscription<GpsFix>? _fixSubscription;

  @override
  void initState() {
    super.initState();
    // Asked for on arrival here, unlike on home, and the difference is the
    // whole justification: home is the screen a rider lands on after
    // onboarding without having asked for anything, whereas opening this
    // page *is* the request "find me a ride from where I am". A permission
    // prompt at that moment answers a question the rider just asked.
    unawaited(_locate());
  }

  /// Asks for location, then takes the first fix that arrives and starts the
  /// pickup map on it.
  Future<void> _locate() async {
    bool granted;
    try {
      granted = await ref.read(locationPermissionCheckProvider)();
    } on Exception {
      // The permission check reaches a platform channel, which is absent
      // under `flutter_test` and can fail on a device whose location
      // services are in a bad state. Neither is worth taking this flow down
      // for: treat it exactly like a refusal, which is what it amounts to.
      granted = false;
    }
    if (!mounted || !granted) return;

    await _fixSubscription?.cancel();
    _fixSubscription = ref.read(locationSourceProvider).watch().listen((fix) {
      unawaited(_fixSubscription?.cancel());
      _fixSubscription = null;
      if (!mounted) return;
      _adoptFix(fix);
    });
  }

  /// Whether the pickup point is still the untouched city-centre default.
  ///
  /// Compared against the configured centre rather than tracked with a
  /// "has the rider typed anything yet" flag, and deliberately: the landmark
  /// field also reports through `onChanged`, so a flag would treat a rider
  /// who typed «цагаан хаалга» while waiting for a fix as having placed
  /// their pin, and leave the map on the middle of the city.
  bool get _pickupIsCityDefault =>
      _pickup.lat == defaultCityConfig.centerLat &&
      _pickup.lon == defaultCityConfig.centerLon;

  /// Adopts the device's first fix.
  ///
  /// The marker is set unconditionally -- knowing where the phone is never
  /// hurts, and after a pan it is the only way back. Moving the *points* is
  /// gated on the rider not having started yet, on either step: a fix that
  /// lands while somebody is already dragging the destination map must not
  /// silently rewrite what they picked. `LocationPickerField` holds the
  /// matching half of that rule for the camera.
  void _adoptFix(GpsFix fix) {
    final seedsPoints = _step == _PassengerStep.pickup && _pickupIsCityDefault;
    setState(() {
      _deviceFix = fix;
      if (!seedsPoints) return;
      _pickup = PickedLocation(
        lat: fix.lat,
        lon: fix.lon,
        landmarkText: _pickup.landmarkText,
      );
      // The destination map opens where the rider is standing rather than
      // on the city centre, which is the one place they are demonstrably
      // not. It is still theirs to move, and the step's own heading says
      // which point it is asking for.
      _destination = PickedLocation(
        lat: fix.lat,
        lon: fix.lon,
        landmarkText: _destination.landmarkText,
      );
    });
  }

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
    // Same for the GPS radio, which keeps running behind a closed page if
    // the first fix never arrived to cancel this itself.
    unawaited(_fixSubscription?.cancel());
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

  /// Opens the price step and starts fetching the route it draws.
  ///
  /// The fetch is kicked off from here -- the transition -- rather than from
  /// the step widget's own lifecycle, so that walking back to the map,
  /// moving a pin and coming forward again re-asks. A step that fetched once
  /// on mount would show the rider the road to the place they had just
  /// stopped choosing.
  ///
  /// [_routePreview] is cleared first, on purpose: the map has to say "no
  /// route yet" for the second or two the request takes rather than keep
  /// drawing the previous trip's line, which would be a picture of somewhere
  /// the rider is no longer going.
  void _enterPriceStep() {
    final seq = ++_routeRequestSeq;
    setState(() {
      _routePreview = null;
      _step = _PassengerStep.price;
    });
    unawaited(_loadRoutePreview(seq));
  }

  Future<void> _loadRoutePreview(int seq) async {
    final preview = await loadTripRoutePreview(
      pathClient: ref.read(routePathClientProvider),
      pickup: ll.LatLng(_pickup.lat, _pickup.lon),
      destination: ll.LatLng(_destination.lat, _destination.lon),
    );
    // `loadTripRoutePreview` never throws -- every failure is already a
    // labelled approximate answer -- so there is nothing to catch here, only
    // a stale reply to drop.
    if (!mounted || seq != _routeRequestSeq) return;
    setState(() => _routePreview = preview);
  }

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
    });
    // Through the same door the destination step uses, so a rider who backs
    // out of a published request lands on a price step showing their trip
    // rather than on one showing an empty map.
    _enterPriceStep();
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
            groupedMnt(payload.priceMnt),
            payload.etaMinutes,
          ),
        ),
        actions: [
          // The one confirmation in this file the rider *sought out* --
          // they tapped an offer -- so unlike the back-guard dialogs the
          // emphasis belongs on going forward, not on backing out.
          DialogActionBar(
            dismiss: DialogAction(
              label: l.cancelAction,
              tone: DialogActionTone.neutral,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            proceed: DialogAction(
              label: l.confirmSelectOfferAction,
              tone: DialogActionTone.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ),
        ],
      ),
    );
    // `null` is a barrier tap or a back press on the dialog itself --
    // treated as "no", the safe answer for an irreversible disclosure.
    return confirmed ?? false;
  }

  /// Opens the driver behind an offer, and selects them only if the rider
  /// says so on that page.
  ///
  /// The tap on the list no longer *is* the choice. A rider was being asked
  /// to hand a stranger their exact address off a face the size of a
  /// thumbnail; now the face, the name, the car, both tariffs, the key and
  /// the plain statement that none of it is verified come first, and the
  /// irreversible confirmation still comes after (see [_select]). Anything
  /// other than the page's own "choose this driver" -- the back gesture,
  /// the back button, a barrier -- answers `null` and nothing is sent.
  Future<void> _openDriver(RankedRideOffer ranked) async {
    final chosen = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => DriverOfferPage(ranked: ranked)),
    );
    if (chosen != true || !mounted) return;
    await _select(ranked);
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
    final surfaces = TakhiSurfaces.of(context);
    final selected = _selected;
    final tripId = _tripId;
    return _guardBack(
      l,
      Scaffold(
        backgroundColor: surfaces.canvas,
        appBar: AppBar(
          // Flat in both senses, matching the taximeter's: no tint, and no
          // colour change when content scrolls under it. Every step below
          // supplies its own planes -- a second, automatic one at the top
          // would compete with the sheet carrying the action.
          backgroundColor: surfaces.canvas,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            l.appName,
            style: TakhiType.title.copyWith(color: surfaces.onSheet),
          ),
        ),
        body: SafeArea(
          // Every wizard step ends in a `TakhiSheet`, which adds the system
          // gesture inset itself; consuming it here as well would pad it
          // twice. `ActiveTripView` owns no sheet, so it still gets one.
          bottom: _step == _PassengerStep.activeTrip,
          child: switch (_step) {
            // Keyed per step so returning to one rebuilds its picker from
            // the point stored here rather than reusing the other step's
            // live state -- which is also what kept the destination step
            // from inheriting the pickup's pin and landmark text.
            _PassengerStep.pickup => _LocationStep(
              key: const ValueKey(_PassengerStep.pickup),
              title: l.passengerPickupStepTitle,
              subtitle: l.passengerPickupStepSubtitle,
              initialCenter: ll.LatLng(_pickup.lat, _pickup.lon),
              initialLandmarkText: _pickup.landmarkText,
              devicePosition: _devicePosition,
              deviceAccuracyMeters: _deviceFix?.accuracyMeters,
              onChanged: (p) => _pickup = p,
              onNext: () => setState(() => _step = _PassengerStep.destination),
            ),
            _PassengerStep.destination => _LocationStep(
              key: const ValueKey(_PassengerStep.destination),
              title: l.passengerDestinationStepTitle,
              subtitle: l.passengerDestinationStepSubtitle,
              initialCenter: ll.LatLng(_destination.lat, _destination.lon),
              initialLandmarkText: _destination.landmarkText,
              devicePosition: _devicePosition,
              deviceAccuracyMeters: _deviceFix?.accuracyMeters,
              // The end already chosen, drawn on the map the other end is
              // being chosen on. Without it this step asks "where to?" over
              // a map with no "from" on it.
              referencePoint: ll.LatLng(_pickup.lat, _pickup.lon),
              onChanged: (p) => _destination = p,
              onNext: _enterPriceStep,
              onBack: () => _goBackTo(_PassengerStep.pickup),
            ),
            _PassengerStep.price => _PriceStep(
              controller: _priceController,
              pickup: _pickup,
              destination: _destination,
              preview: _routePreview,
              devicePosition: _devicePosition,
              deviceAccuracyMeters: _deviceFix?.accuracyMeters,
              onPublish: _publish,
              onBack: () => _goBackTo(_PassengerStep.destination),
            ),
            _PassengerStep.offers => _OffersStep(
              offers: _offers,
              receiptsFor: (pk) => _receiptsCache[pk] ?? const [],
              onOpenDriver: _openDriver,
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
                // Who the rider actually chose, carried through from the
                // offer they accepted. Nothing else in the trip can supply
                // this: a driver's name and face travel only inside their
                // gift-wrapped offer, never on a public relay.
                counterpartyName: selected.offer.payload.driverFullName,
                counterpartyPhotoJpeg: selected.offer.payload.driverPhotoBytes,
                kmTariffMnt: selected.offer.payload.kmTariffMnt,
                waitTariffMntPerMinute:
                    selected.offer.payload.waitTariffMntPerMinute,
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
    // One dialog per thing actually at stake. `done` used to share the
    // active-trip wording, which asked the passenger about "the trip" --
    // its live location, its calling, getting back into it -- while
    // `ActiveTripView` had not even been mounted. What is at stake there
    // is the booking: the choice, and the driver already heading over.
    final (leaveTitle, leaveMessage) = switch (_step) {
      _PassengerStep.offers => (
        l.leaveRideRequestTitle,
        l.leaveRideRequestMessage,
      ),
      _PassengerStep.done => (
        l.leaveSelectedDriverTitle,
        l.leaveSelectedDriverMessage,
      ),
      // The remaining arms are the active trip -- where the trip wording is
      // the true one -- and the three pre-publish steps, which never reach
      // the dialog at all (`_isRequestLive` is false there).
      _ => (l.leaveTripTitle, l.leaveTripMessage),
    };
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
      title: leaveTitle,
      message: leaveMessage,
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

/// The scrolling half of a wizard step, above the sheet that carries its
/// action.
///
/// Every step here has the same two-part shape -- something to read and set,
/// and one button to press -- and the button is anchored so it never scrolls
/// away under a raised keyboard. The same shape the taximeter's steps use, on
/// purpose: a rider moving between the two screens should not have to find
/// the primary action twice.
class _StepBody extends StatelessWidget {
  final Widget child;

  const _StepBody({required this.child});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
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
  );
}

/// The sheet at the foot of a wizard step: the step's one forward action,
/// and -- once there is a step to return to -- the way back under it.
class _StepActions extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// `null` on a step with no earlier step to return to.
  final VoidCallback? onBack;

  const _StepActions({
    required this.label,
    required this.onPressed,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return TakhiSheet(
      // Nothing here moves or dismisses, so a grab bar would promise a
      // gesture that does not exist.
      showHandle: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(label: label, onPressed: onPressed),
          if (back != null) ...[
            const SizedBox(height: TakhiSpace.xs),
            SecondaryButton(
              label: AppLocalizations.of(context)!.backAction,
              onPressed: back,
            ),
          ],
        ],
      ),
    );
  }
}

/// One end of the trip: pick the point on the map, name what is standing
/// there.
///
/// The heading is the part that was missing rather than merely plain. The
/// pickup step and the destination step draw the identical map, the
/// identical capsule and the identical button, so with no title above them a
/// rider halfway through the flow had nothing on screen telling them which
/// of the two points they were setting -- and no way to notice they had
/// answered the wrong question until a driver arrived at their destination.
class _LocationStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final ll.LatLng initialCenter;
  final String initialLandmarkText;

  /// See `LocationPickerField.devicePosition` -- null until a fix arrives,
  /// and forever if location was refused.
  final ll.LatLng? devicePosition;

  /// See `LocationPickerField.deviceAccuracyMeters`.
  final double? deviceAccuracyMeters;

  /// See `LocationPickerField.referencePoint` -- the trip's other end, on
  /// the step where one has already been picked.
  final ll.LatLng? referencePoint;

  final ValueChanged<PickedLocation> onChanged;
  final VoidCallback onNext;

  /// `null` on the first step, which has no earlier step to return to --
  /// there back simply leaves the page.
  final VoidCallback? onBack;

  const _LocationStep({
    super.key,
    required this.title,
    required this.subtitle,
    required this.initialCenter,
    required this.initialLandmarkText,
    required this.devicePosition,
    required this.deviceAccuracyMeters,
    this.referencePoint,
    required this.onChanged,
    required this.onNext,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        Expanded(
          child: _StepBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(title: title, subtitle: subtitle),
                const SizedBox(height: TakhiSpace.lg),
                LocationPickerField(
                  initialCenter: initialCenter,
                  initialLandmarkText: initialLandmarkText,
                  devicePosition: devicePosition,
                  deviceAccuracyMeters: deviceAccuracyMeters,
                  referencePoint: referencePoint,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
        _StepActions(label: l.nextStep, onPressed: onNext, onBack: onBack),
      ],
    );
  }
}

/// The last step before the ride goes out on the relays: what the rider is
/// willing to pay, over a statement of the trip they are about to publish.
///
/// The summary is not decoration. This is the only screen between two map
/// pickers and an irreversible publish, and until now it showed a bare
/// number field -- a rider who had mis-set one of the two points had no
/// chance left to notice before drivers started answering.
class _PriceStep extends StatelessWidget {
  final TextEditingController controller;
  final PickedLocation pickup;
  final PickedLocation destination;

  /// The route and its likely cost, or `null` while the routing service is
  /// still being asked. See [TripRouteMap], which draws the two ends either
  /// way -- the map is never blank while a rider waits.
  final TripRoutePreview? preview;

  final ll.LatLng? devicePosition;
  final double? deviceAccuracyMeters;

  final VoidCallback onPublish;
  final VoidCallback onBack;

  const _PriceStep({
    required this.controller,
    required this.pickup,
    required this.destination,
    required this.preview,
    required this.devicePosition,
    required this.deviceAccuracyMeters,
    required this.onPublish,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Column(
      children: [
        Expanded(
          child: _StepBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(
                  // `compact` here and nowhere else in this wizard: the two
                  // picker steps carry a map and one field, while this one
                  // carries a map, a chip row, two caveats, both addresses
                  // AND the field it exists to collect. A display-size
                  // heading over that column is what pushes the field off
                  // the bottom of the screen.
                  compact: true,
                  title: l.passengerPriceStepTitle,
                  subtitle: l.passengerPriceStepSubtitle,
                ),
                const SizedBox(height: TakhiSpace.md),
                // Above the two written-out points, not instead of them.
                // The map answers "is that the right side of the river" at a
                // glance; the rows underneath carry the landmark text and
                // the Plus Code, which is what a driver actually receives.
                MapCard(
                  height: _kRouteMapHeight,
                  child: TripRouteMap(
                    pickup: ll.LatLng(pickup.lat, pickup.lon),
                    destination: ll.LatLng(destination.lat, destination.lon),
                    preview: preview,
                    devicePosition: devicePosition,
                    deviceAccuracyMeters: deviceAccuracyMeters,
                  ),
                ),
                const SizedBox(height: TakhiSpace.sm),
                // Directly under the map, because they describe it: how far
                // that line runs and roughly what it costs. They are also
                // the anchor for the answer this step wants, so they belong
                // above the summary rather than below it.
                _RouteFacts(preview: preview),
                const SizedBox(height: TakhiSpace.sm),
                _TripSummary(pickup: pickup, destination: destination),
                const SizedBox(height: TakhiSpace.lg),
                LabeledField(
                  label: l.priceLabel,
                  icon: Icons.payments_outlined,
                  controller: controller,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ),
        _StepActions(
          label: l.publishRide,
          onPressed: onPublish,
          onBack: onBack,
        ),
      ],
    );
  }
}

/// The two ends of the trip, as one object in one sunken well -- the same
/// shape home states a trip in, so the rider recognises it as the thing they
/// filled in there rather than as a new kind of block.
class _TripSummary extends StatelessWidget {
  final PickedLocation pickup;
  final PickedLocation destination;

  const _TripSummary({required this.pickup, required this.destination});

  /// What a picked point is called on screen.
  ///
  /// The landmark the rider typed outranks everything: it is the only form
  /// of the point a driver can actually read. With none typed the Plus Code
  /// is all this app has -- it never asks a geocoding service what is
  /// standing at a coordinate (spec §6) -- so it is stated plainly rather
  /// than dressed up as an address.
  static String _name(PickedLocation point) => point.landmarkText.trim().isEmpty
      ? point.plusCode
      : point.landmarkText.trim();

  /// The exact form of the point, kept under the name when the name is a
  /// landmark and dropped when the name already *is* the code -- a row that
  /// prints the same string twice reads as a rendering fault.
  static String? _detail(PickedLocation point) =>
      point.landmarkText.trim().isEmpty ? null : point.plusCode;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.field,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TakhiSpace.md,
          vertical: TakhiSpace.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AddressRow(
              icon: Icons.trip_origin,
              label: l.homePickupLabel,
              value: _name(pickup),
              detail: _detail(pickup),
              accent: TakhiAccent.steppe,
            ),
            AddressRow(
              icon: Icons.place,
              label: l.homeDestinationPlaceholder,
              value: _name(destination),
              detail: _detail(destination),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the drawn route amounts to: how far it runs, how long it takes, and
/// every caveat those two figures carry.
///
/// ## Why there is no ₮ figure here
///
/// There was one, until it was read carefully. It was the routed distance
/// times a "city reference rate" that lived as the literal `2000` in
/// `CityConfig` -- unmeasured, uncited, and rounded in a way that made it
/// look checked. This is the screen where a rider types the price they are
/// willing to pay, and a figure printed directly above that field is not
/// information, it is an anchor: whatever number stands there is the number
/// most people will type some version of. An app with no company behind it,
/// whose entire premise is that the two people in the car agree the price,
/// cannot be the thing that decides what a kilometre costs in Ulaanbaatar.
///
/// So this row now states only what was actually measured, in order:
///
///  * the distance, which is the fact the app is most sure of;
///  * the driving time, when the routing service returned one -- the other
///    half of what a trip *is*, and the half a straight-line guess can never
///    supply, which is why it simply disappears offline instead of being
///    derived from an assumed speed;
///  * "ойролцоогоор" whenever the route is the offline straight line, on the
///    outlined chip that reads as a caveat rather than as a second figure;
///  * why the line looks broken, when it does;
///  * and, always, the sentence that says where a price does come from:
///    drivers, in their offers, each with their own rate.
///
/// Nothing at all is drawn while the routing request is in flight: a
/// placeholder figure is a number a rider can read and act on, and there is
/// no honest one to show yet. The map above keeps both ends in frame
/// throughout, so the step is never blank.
class _RouteFacts extends StatelessWidget {
  final TripRoutePreview? preview;

  const _RouteFacts({required this.preview});

  @override
  Widget build(BuildContext context) {
    final route = preview;
    if (route == null) return const SizedBox.shrink();

    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    // One decimal: the underlying metres are exact, but "7.2 км" is what a
    // person checks against their own sense of the city, and "7.1834 км" is
    // a number nobody can use.
    final km = double.parse(
      (route.distanceMeters / _kMetresPerKm).toStringAsFixed(1),
    );
    final seconds = route.durationSeconds;
    // Rounded up rather than to nearest, and never to zero: "0 мин" for a
    // trip that takes forty seconds is the one reading that is plainly
    // wrong, and a rider who arrives a minute early is never the one who
    // complains.
    final minutes = seconds == null
        ? null
        : (seconds / _kSecondsPerMinute).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: TakhiSpace.xs,
          runSpacing: TakhiSpace.xs,
          children: [
            InfoChip(
              icon: Icons.straighten,
              label: l.routePreviewDistanceLabel(km),
            ),
            if (minutes != null)
              InfoChip(
                icon: Icons.schedule,
                label: l.routePreviewDurationLabel(minutes),
              ),
            if (route.isApproximate)
              InfoChip(label: l.estimatedFareApproxLabel, tinted: false),
          ],
        ),
        if (route.isApproximate) ...[
          const SizedBox(height: TakhiSpace.xs),
          Text(
            l.routePreviewOfflineHint,
            style: TakhiType.support.copyWith(color: surfaces.muted),
          ),
        ],
        const SizedBox(height: TakhiSpace.xs),
        Text(
          l.routePreviewNoQuoteHint,
          style: TakhiType.support.copyWith(color: surfaces.muted),
        ),
      ],
    );
  }
}

/// The screen the whole app is built around: the rider choosing which driver
/// is coming.
///
/// Three things it has to say at once, and the order they are said in is the
/// design:
///
/// 1. **who** -- a [PersonRow] with the driver's mark, their key and their
///    reputation, because this app's entire claim is that a stranger can be
///    picked on evidence rather than on a dispatcher's word (spec §9). A
///    list that showed only a price and a car threw that away;
/// 2. **what it costs** -- the fare as the card's one large figure, with the
///    metered rates beside it when the offer has them, because those are the
///    numbers being compared down the list;
/// 3. **why this order** -- [rankRideOffers] sorts by reputation, and a list
///    that silently reorders itself is a list nobody can trust. The heading
///    says what the sort key is, and the leader is marked -- but only while
///    the leader actually leads.
class _OffersStep extends StatelessWidget {
  final List<RideOffer> offers;
  final List<TripReceipt> Function(String driverPubkey) receiptsFor;
  final ValueChanged<RankedRideOffer> onOpenDriver;

  /// Withdraws the published request and returns to the price step -- the
  /// way out when no offer arrives, or every one of them is too expensive.
  final VoidCallback onBack;

  const _OffersStep({
    required this.offers,
    required this.receiptsFor,
    required this.onOpenDriver,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ranked = rankRideOffers(offers, receiptsFor: receiptsFor);

    // Whether the order on screen means anything yet. Until some driver has
    // a confirmed trip behind them every `trustWeight` is 0, the sort is a
    // no-op, and calling the list "ranked by reputation" would be dressing
    // arrival order up as a judgement.
    final anyReputation = ranked.any((r) => r.reputation.trustWeight > 0);
    // And whether the *leader* leads. A badge on a card tied with the one
    // under it is a badge that points at nothing.
    final leaderIsAhead =
        ranked.length > 1 &&
        ranked.first.reputation.trustWeight > ranked[1].reputation.trustWeight;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TakhiSpace.md,
              TakhiSpace.lg,
              TakhiSpace.md,
              TakhiSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(
                  title: l.offersWaitingTitle,
                  subtitle: ranked.isEmpty
                      ? null
                      : (anyReputation
                            ? l.offersRankedByReputationHint
                            : l.offersAllNewHint),
                ),
                const SizedBox(height: TakhiSpace.lg),
                Expanded(
                  child: ranked.isEmpty
                      ? const _OffersWaitingView()
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: ranked.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: TakhiSpace.sm),
                          itemBuilder: (context, i) => _OfferCard(
                            ranked: ranked[i],
                            leads: i == 0 && leaderIsAhead,
                            onTap: () => onOpenDriver(ranked[i]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        TakhiSheet(
          showHandle: false,
          child: SecondaryButton(label: l.backAction, onPressed: onBack),
        ),
      ],
    );
  }
}

/// What the offers step shows while the request is live and nothing has come
/// back yet.
///
/// A title over an empty half-screen is indistinguishable from a screen that
/// failed to load, and this one can legitimately stay empty for a minute at
/// a quiet hour. So it says out loud what is happening and why waiting is
/// the correct thing to be doing.
///
/// Deliberately still: no spinner, no repeating animation. Not only because
/// a permanently-animating widget makes `pumpAndSettle` hang in every test
/// that passes through this step -- a spinner would also promise something
/// is being *fetched*, when in truth the request is already out and the app
/// is waiting on other people.
class _OffersWaitingView extends StatelessWidget {
  const _OffersWaitingView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AccentDot(icon: Icons.wifi_tethering, size: _kWaitingMarkSize),
          const SizedBox(height: TakhiSpace.md),
          Text(
            l.offersWaitingEmptyTitle,
            textAlign: TextAlign.center,
            style: TakhiType.heading.copyWith(color: surfaces.onSheet),
          ),
          const SizedBox(height: TakhiSpace.xs),
          Text(
            l.offersWaitingEmptyHint,
            textAlign: TextAlign.center,
            style: TakhiType.body.copyWith(color: surfaces.muted),
          ),
        ],
      ),
    );
  }
}

/// One driver's offer, as a card the rider presses to look closer at.
///
/// A card and not a `ListTile`: three offers stacked as plain text run
/// together into one block a rider has to parse line by line, and nothing in
/// it says any of it can be tapped.
///
/// The tap opens the driver's page, not the confirmation. It used to be the
/// confirmation: one press on a scrolling list stood between a rider and
/// handing a stranger their exact address, with a face the size of a
/// thumbnail as the whole of what they had to go on. Two presses, with the
/// face at face size in between, is the right number for that decision.
class _OfferCard extends StatelessWidget {
  final RankedRideOffer ranked;

  /// Whether this offer stands *strictly* ahead of the next one on
  /// reputation. Decided by the list, not by the card: a card cannot see the
  /// one below it, and "first among ties" is not a distinction.
  final bool leads;

  final VoidCallback onTap;

  const _OfferCard({
    required this.ranked,
    required this.leads,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return Material(
      color: surfaces.sheet,
      borderRadius: TakhiRadius.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: TakhiRadius.cardAll,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: TakhiRadius.cardAll,
            // The leader is outlined in the brand colour rather than filled
            // with it: an offer list is not a recommendation, and a card
            // loud enough to look pre-selected would be making the choice
            // the rider came here to make.
            border: Border.all(
              color: leads ? TakhiColors.gold : surfaces.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TakhiSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leads) ...[
                  InfoChip(
                    icon: Icons.verified_outlined,
                    label: l.offerTopReputationBadge,
                    accent: TakhiAccent.gold,
                  ),
                  const SizedBox(height: TakhiSpace.xs),
                ],
                DriverIdentityRow(
                  ranked: ranked,
                  // A plain row is a statement; the chevron is what says
                  // this one does something when pressed.
                  trailing: Icon(Icons.chevron_right, color: surfaces.muted),
                ),
                const SizedBox(height: TakhiSpace.xs),
                OfferTerms(payload: ranked.offer.payload),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The moment between choosing a driver and getting into the car.
///
/// It used to be one gold line floating in the middle of an otherwise empty
/// screen with a button under it -- which said less than the list the rider
/// had just come from, at the exact moment they most want to check what they
/// have committed to and who is coming. It now states the same facts the
/// offer card did, minus the car (which the heading names), so the choice
/// can still be read back while the driver is on their way.
class _DoneStep extends StatelessWidget {
  final RankedRideOffer? selected;
  final VoidCallback onStartTrip;

  const _DoneStep({required this.selected, required this.onStartTrip});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final chosen = selected;
    final photo = chosen?.offer.payload.driverPhotoBytes;

    return Column(
      children: [
        Expanded(
          child: _StepBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // `chosen` is never null in practice -- `_select` sets it
                // before moving to this step -- but a guard here can only
                // lose a card, while a `!` could crash a rider whose driver
                // is already on the way.
                if (chosen != null) ...[
                  SectionHeading(
                    // `compact`: this heading carries a whole vehicle
                    // description, and at display size a Mongolian sentence
                    // that long fills half the screen on its own.
                    compact: true,
                    title: l.driverOnTheWay(
                      chosen.offer.payload.vehicleDescription,
                    ),
                    subtitle: l.passengerDriverOnTheWaySubtitle,
                  ),
                  const SizedBox(height: TakhiSpace.lg),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: surfaces.field,
                      borderRadius: TakhiRadius.cardAll,
                      border: Border.all(color: surfaces.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(TakhiSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DriverIdentityRow(
                            ranked: chosen,
                            // Enlarges the portrait rather than reopening
                            // the driver page: the choice is already made,
                            // so the only thing left to do with this row is
                            // check the face against the car pulling up.
                            onTap: photo == null
                                ? null
                                : () => unawaited(
                                    showDriverPhoto(context, photo),
                                  ),
                          ),
                          const SizedBox(height: TakhiSpace.xs),
                          OfferTerms(
                            payload: chosen.offer.payload,
                            showVehicle: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        _StepActions(label: l.startTripAction, onPressed: onStartTrip),
      ],
    );
  }
}
