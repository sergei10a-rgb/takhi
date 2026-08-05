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
import '../identity/identity_service.dart';
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/location_picker.dart';
import '../map/map_card.dart';
import '../map/offers_map.dart';
import '../map/trip_route_map.dart';
import '../map/trip_tracking_map.dart';
import '../map/trip_route_preview.dart';
import '../meter/distance_format.dart';
import '../meter/meter_providers.dart';
import '../meter/money_format.dart';
import '../theme/takhi_theme.dart';
import '../widgets/address_row.dart';
import '../widgets/confirm_leave_scope.dart';
import '../widgets/dialog_action_bar.dart';
import '../widgets/driver_portrait.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_chip.dart';
import '../widgets/labeled_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/segmented_choice.dart';
import '../widgets/takhi_sheet.dart';
import 'active_trip_view.dart';
import 'driver_offer_view.dart';
import 'offer_ranking.dart';
import 'offer_service.dart';
import 'ride_cancel_reason.dart';
import 'ride_dm_payload.dart';
import 'ride_request_service.dart';
import 'ride_providers.dart';
import 'trip_role.dart';

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

/// How tall the "your driver is coming" map is.
///
/// Taller than the route preview: this one is watched, not glanced at. A
/// passenger deciding whether to put their coat on is reading it every few
/// seconds for several minutes, and a strip too short to show both the car
/// and the kerb it is heading for answers nothing.
const _kApproachMapHeight = 260.0;

/// Unit conversions for the two measured facts the price step states. Named
/// rather than inline so the arithmetic reads as what it is and cannot be
/// mistyped by an order of magnitude.
const _kMetresPerKm = 1000;
const _kSecondsPerMinute = 60;

/// How close to its deadline an offer's countdown turns from calm to clay —
/// the last stretch where a rider weighing it should know it is about to go.
const int _kOfferExpirySoonSeconds = 30;

/// The passenger flow's default clock: real unix seconds. A top-level
/// function (not a closure) so it is a compile-time constant and
/// [PassengerRidePage] can stay `const`; a test passes its own to hold the
/// clock still or move it by hand.
int _defaultNowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// The passenger's wizard.
///
/// [review] used to be called `price`, and used to ask for one. The step
/// itself survived the removal because asking for a price was never all it
/// did: it draws the route, states how far and how long, and carries the
/// publish button. Losing the box left a screen that answers "is this the
/// trip I meant" before it goes out to every driver nearby, which is worth
/// a step on its own.
enum _PassengerStep { pickup, destination, review, offers, done, activeTrip }

/// The passenger's full "call a ride" flow (spec §7.1): pick pickup, pick
/// destination, review the route, publish, watch offers arrive live
/// ranked by reputation (or by whichever key the rider picks instead --
/// [OfferSort]), select one. Ends once the exact-location handoff
/// is sent -- the trip itself (in-progress tracking, fare settlement) is
/// Plan 4.
class PassengerRidePage extends ConsumerStatefulWidget {
  /// The clock the offers step counts down against. Defaults to the system
  /// unix second; injected only by tests, which hold it still or advance it
  /// by hand so an offer's expiry is a thing they decide, not a race with the
  /// wall clock.
  final int Function() nowSeconds;

  const PassengerRidePage({super.key, this.nowSeconds = _defaultNowSeconds});

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
  String? _rideRequestId;

  /// Where the chosen driver is right now, or `null` until their first
  /// ping arrives.
  ///
  /// Null is drawn as "waiting for their position", never as a car at a
  /// stale or invented point: a passenger deciding whether to step outside
  /// is acting on this dot, and a dot that is guessing is worse than none.
  ll.LatLng? _driverPosition;
  StreamSubscription<LiveLocation>? _driverPositionSubscription;
  String? _tripId;

  /// The four-digit pickup code minted when this passenger selected a driver,
  /// shown big on the done step for them to read out. Null until a selection
  /// is made.
  String? _startCode;
  final List<RideOffer> _offers = [];
  final Map<String, List<TripReceipt>> _receiptsCache = {};
  RankedRideOffer? _selected;
  StreamSubscription<RideOffer>? _offersSubscription;

  /// Inbound cancellations from a driver, live from the moment the request is
  /// published until the trip starts. Before this existed the passenger's
  /// screen listened for a driver's approach but never for their *withdrawal*:
  /// a driver who marked a no-show, or backed out, left the rider watching a
  /// car that was never coming, with no word. Torn down with
  /// [_offersSubscription] everywhere, and only ever acted on for the driver
  /// they actually selected (see [_onDriverCancellation]).
  StreamSubscription<ReceivedRideCancel>? _cancelSubscription;

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
    // Without this, `RelayPool.subscribe`'s `StreamController.onCancel`
    // (relay_pool.dart) never fires -- the relay subscription this page
    // opened in `_publish` stays open for the app's remaining lifetime.
    unawaited(_offersSubscription?.cancel());
    // The inbound-cancellation stream opened alongside it, for the same
    // relay-leak reason.
    unawaited(_cancelSubscription?.cancel());
    // Same for the GPS radio, which keeps running behind a closed page if
    // the first fix never arrived to cancel this itself.
    unawaited(_fixSubscription?.cancel());
    // And the driver's live position, which unlike the two above is opened
    // late (at handoff) and is meant to run for minutes.
    unawaited(_driverPositionSubscription?.cancel());
    super.dispose();
  }

  Future<void> _publish() async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (identity == null) return;
    final event = await ref
        .read(rideRequestServiceProvider)
        .publishRequest(
          privHex: identity.privHex,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          pickupLat: _pickup.lat,
          pickupLon: _pickup.lon,
          destLat: _destination.lat,
          destLon: _destination.lon,
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
    _cancelSubscription = ref
        .read(rideRequestServiceProvider)
        .receiveCancellations(identity.pubHex, identity.privHex)
        .listen(_onDriverCancellation);
  }

  /// A cancellation the passenger received. Acted on only when it is the
  /// driver they *selected*, about *this* request, and the trip has not yet
  /// started -- the same three-part guard the driver's own `_onCancellation`
  /// applies, because the public ride request is visible to anyone and a
  /// stranger's forged cancel must never tear a rider's screen down. Once the
  /// trip is live, `ActiveTripView` owns the phase channel and a stray cancel
  /// here is ignored.
  void _onDriverCancellation(ReceivedRideCancel cancel) {
    if (!mounted) return;
    final selected = _selected;
    if (selected == null) return;
    if (cancel.senderPubkey != selected.offer.driverPubkey) return;
    if (cancel.payload.rideRequestId != _rideRequestId) return;
    if (_step != _PassengerStep.offers && _step != _PassengerStep.done) return;

    final l = AppLocalizations.of(context)!;
    // A no-show is named as such; every other reason the driver might give is
    // reported as a plain cancellation, since to the waiting rider the
    // difference between "changed their mind" and "too far" is not worth a
    // distinct sentence -- what matters is that the car is not coming.
    final notice = cancel.payload.reasonCode == RideCancelReason.passengerNoShow
        ? l.passengerMarkedNoShowNotice
        : l.passengerDriverCancelledNotice;
    _finishTrip();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
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
    _PassengerStep.review => false,
    _PassengerStep.offers || _PassengerStep.done => true,
    _PassengerStep.activeTrip => _tripInFlight,
  };

  /// Walks one step back. Nothing the passenger entered is cleared --
  /// `_pickup` and `_destination` both survive, so the earlier step comes
  /// back showing the point they picked rather than a blank map.
  void _goBackTo(_PassengerStep step) => setState(() => _step = step);

  /// Opens the review step and starts fetching the route it draws.
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
  void _enterReviewStep() {
    final seq = ++_routeRequestSeq;
    setState(() {
      _routePreview = null;
      _step = _PassengerStep.review;
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
    unawaited(_cancelSubscription?.cancel());
    _cancelSubscription = null;
    setState(() {
      _offers.clear();
      _receiptsCache.clear();
      _rideRequestId = null;
    });
    // Through the same door the destination step uses, so a rider who backs
    // out of a published request lands on a price step showing their trip
    // rather than on one showing an empty map.
    _enterReviewStep();
  }

  /// Everybody who is currently waiting on an answer from this passenger.
  ///
  /// Once a driver is chosen it is only them: the others were never told
  /// they lost, and telling them now that a ride *they are not on* was
  /// cancelled would be noise about a job they had already stopped
  /// expecting. Before that point it is every driver who answered -- each
  /// of them is holding a price open for a passenger who has just walked
  /// away.
  List<String> get _engagedDriverPubkeys {
    final selected = _selected;
    if (selected != null) return [selected.offer.driverPubkey];
    return _offers.map((o) => o.driverPubkey).toSet().toList();
  }

  /// The passenger calling the ride off on purpose, from a button rather
  /// than from a back gesture (spec §7.5).
  ///
  /// Deliberately separate from [_abandonRequest], which the back guard
  /// runs while the route is being torn down. This one leaves the passenger
  /// on the page, so it has both to send and to leave the screen in an
  /// honest state -- and it has to be reachable *without* a back gesture,
  /// because "press back and confirm you are leaving" is not a way to say
  /// "I do not want this ride".
  ///
  /// What it does not do is claim the published request was retracted. It
  /// cannot be (`RideRequestService`'s doc comment says why), so the wizard
  /// simply returns to its first step and the dialog that got here spells
  /// out that a late offer can still arrive.
  Future<void> _cancelRide({
    required String title,
    required String message,
  }) async {
    final reasonCode = await _confirmCancel(title: title, message: message);
    if (reasonCode == null) return;
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    final rideRequestId = _rideRequestId;
    final recipients = _engagedDriverPubkeys;
    // Deliberately not awaited, for the reason [_abandonRequest] gives:
    // the relay pool is app-scoped, and a slow relay must not hold the
    // passenger on a screen they have just asked to leave. Nothing here
    // depends on the answer -- the local teardown below is what makes the
    // request dead on this device either way.
    if (identity != null && rideRequestId != null && recipients.isNotEmpty) {
      unawaited(
        ref
            .read(rideRequestServiceProvider)
            .cancelWithDrivers(
              privHex: identity.privHex,
              driverPubHexes: recipients,
              rideRequestId: rideRequestId,
              now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              reasonCode: reasonCode,
            ),
      );
    }
    // The same teardown a finished trip does, and for the same reason: what
    // is left is a passenger with no ride, which is exactly the state the
    // first step describes. Their picked points and typed price survive, so
    // changing their mind again costs two taps rather than a re-survey of
    // the city.
    _finishTrip();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.rideRequestCancelledConfirmation)));
  }

  /// Asks before a cancellation goes out.
  ///
  /// Emphasis on the cancel, unlike [ConfirmLeaveScope]'s dialogs: this one
  /// was *sought out* -- the passenger pressed a button that says what it
  /// does -- so the loud answer is the one they came for. It is still
  /// [DialogActionTone.caution] rather than a filled primary, because what
  /// is on the other side of it is a driver who stops coming.
  Future<RideCancelReason?> _confirmCancel({
    required String title,
    required String message,
  }) => showModalBottomSheet<RideCancelReason>(
    // A sheet, not an `AlertDialog`: the reason picker is a `SegmentedChoice`,
    // and that control measures itself with a `LayoutBuilder`, which an
    // `AlertDialog` (it sizes to its content's intrinsic width) cannot lay
    // out. `_announceCancellation` on the driver side is a sheet for its own
    // reasons; this one is a sheet so the picker can exist at all.
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    builder: (sheetContext) =>
        _CancelReasonSheet(title: title, message: message),
  );
  // A returned reason means "cancel, and here is why"; `null` -- the keep
  // button, a barrier tap, or a back press -- means keep it and send nothing.

  /// Runs while the leave dialog's answer is still on the stack, just
  /// before the route pops -- late enough to be sure the passenger meant
  /// it, early enough to still read the state it is tearing down. If a
  /// driver was already chosen they are told the ride is off (spec §7.5)
  /// instead of driving to a pickup nobody is waiting at.
  void _abandonRequest() {
    unawaited(_offersSubscription?.cancel());
    _offersSubscription = null;
    unawaited(_cancelSubscription?.cancel());
    _cancelSubscription = null;
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
  ///
  /// Also the teardown [_cancelRide] uses: a ride that ended and a ride
  /// that was called off leave this page holding exactly the same
  /// nothing, and clearing [_selected] in both is what keeps the back
  /// guard from firing a second cancellation at a driver already told.
  void _finishTrip() {
    // The offers subscription outlives `_select`, so a second ride
    // published from the reset page would otherwise overwrite (and leak)
    // this handle -- same reasoning as [_withdrawRequest].
    unawaited(_offersSubscription?.cancel());
    _offersSubscription = null;
    unawaited(_cancelSubscription?.cancel());
    _cancelSubscription = null;
    setState(() {
      // The agreement that made this driver's exact position acceptable to
      // receive is the thing that has just ended.
      _stopWatchingDriver();
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
  /// Returns the bonus the rider agreed to pay on top of this driver's
  /// price, or `null` if they backed out.
  ///
  /// `null` and `0` mean different things and the caller must keep them
  /// apart: `null` is "do not send anything to anybody", `0` is "send the
  /// handoff, with no bonus". A barrier tap or a back press on the dialog
  /// answers `null` -- the safe reading for an irreversible disclosure.
  Future<int?> _confirmSelect(RankedRideOffer ranked) => showDialog<int>(
    context: context,
    builder: (_) => _ConfirmOfferDialog(payload: ranked.offer.payload),
  );

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
    final tipMnt = await _confirmSelect(ranked);
    if (tipMnt == null || !mounted) return;
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
    // Minted here, on the passenger's own device: the driver confirms this
    // code, never generates one. It travels inside the handoff's gift-wrap to
    // the one chosen driver and is shown big on this screen for the passenger
    // to read out at the kerb.
    final startCode = ref.read(startCodeGeneratorProvider)();
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
          // Zero travels as absent: the driver's screen must not carry a
          // «Нэмэлт 0 ₮» row for a bonus nobody offered.
          tipMnt: tipMnt > 0 ? tipMnt : null,
          startCode: startCode,
        );
    if (!mounted) return;
    setState(() {
      _selected = ranked;
      _tripId = tripId;
      _startCode = startCode;
      _step = _PassengerStep.done;
    });
    _watchDriverApproach(identity, tripId);
  }

  /// Follows the chosen driver while they drive over.
  ///
  /// The gap this closes: the encrypted live-location channel and the
  /// tracking map both already existed, but neither side opened them until
  /// the trip was STARTED -- a button pressed at the kerb. Between choosing
  /// a driver and getting in is exactly the stretch where the car is moving
  /// and the passenger has nothing to look at, which is the stretch they
  /// asked to see.
  void _watchDriverApproach(Identity identity, String tripId) {
    unawaited(_driverPositionSubscription?.cancel());
    _driverPositionSubscription = ref
        .read(liveLocationChannelProvider)
        .watch(identity.pubHex, identity.privHex, tripId)
        .listen((loc) {
          if (!mounted) return;
          setState(() => _driverPosition = ll.LatLng(loc.lat, loc.lon));
        });
  }

  /// Stops following, and forgets where they were.
  ///
  /// Both halves matter. Leaving the subscription open would keep a
  /// cancelled passenger receiving a stranger's position; leaving the last
  /// point behind would draw that stranger's car on the next booking's map.
  void _stopWatchingDriver() {
    unawaited(_driverPositionSubscription?.cancel());
    _driverPositionSubscription = null;
    _driverPosition = null;
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
              onNext: _enterReviewStep,
              onBack: () => _goBackTo(_PassengerStep.pickup),
            ),
            _PassengerStep.review => _ReviewStep(
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
              nowSeconds: widget.nowSeconds,
              pickup: _pickup,
              receiptsFor: (pk) => _receiptsCache[pk] ?? const [],
              // Absent until the store answers, which is a moment: an
              // empty set ranks exactly as this screen did before trust
              // had any input at all, so nothing flickers or reorders
              // under the rider's finger.
              viewerTrusted:
                  ref.watch(trustedDriversProvider).valueOrNull ?? const {},
              onOpenDriver: _openDriver,
              onQuickPick: (ranked) => unawaited(_select(ranked)),
              onBack: _withdrawRequest,
              onCancel: () => unawaited(
                _cancelRide(
                  title: l.cancelRideRequestConfirmTitle,
                  message: l.cancelRideRequestConfirmMessage,
                ),
              ),
            ),
            // No in-body *back* past this point -- a driver is committed,
            // and there is no earlier step to walk to that would not leave
            // them driving over. There is an in-body way *out*: the back
            // gesture used to be the only one, which meant a passenger who
            // simply did not want the ride any more had to discover that
            // "leave the screen" is where "cancel" lives.
            _PassengerStep.done => _DoneStep(
              selected: selected,
              pickup: _pickup,
              startCode: _startCode,
              driverPosition: _driverPosition,
              devicePosition: _devicePosition,
              deviceAccuracyMeters: _deviceFix?.accuracyMeters,
              onStartTrip: () =>
                  setState(() => _step = _PassengerStep.activeTrip),
              onCancel: () => unawaited(
                _cancelRide(
                  title: l.cancelSelectedDriverConfirmTitle,
                  message: l.cancelSelectedDriverConfirmMessage,
                ),
              ),
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
                durationTariffMntPerMinute:
                    selected.offer.payload.durationTariffMntPerMinute,
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
      _PassengerStep.review => _PassengerStep.destination,
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
/// and -- when the step has one -- the quieter answer under it.
class _StepActions extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// The second answer, or `null` on a step that offers none.
  final VoidCallback? onBack;

  /// What that second answer is called. Defaults to «Буцах», which is what
  /// it is on every step that has an earlier one to return to.
  ///
  /// Overridable because the last step before the trip has a second answer
  /// that is emphatically *not* "back": there is nowhere to walk to from a
  /// driver already on their way, and the only other thing a passenger can
  /// want there is to call it off. Labelling that "Буцах" would hide the
  /// one irreversible action on the screen behind the app's most ordinary
  /// word.
  final String? backLabel;

  const _StepActions({
    required this.label,
    required this.onPressed,
    this.onBack,
    this.backLabel,
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
              label: backLabel ?? AppLocalizations.of(context)!.backAction,
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
class _ReviewStep extends StatelessWidget {
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

  const _ReviewStep({
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
                  // carries a map, a chip row, two caveats and both
                  // addresses. A display-size heading over that column
                  // pushes the publish button off the bottom of the screen.
                  compact: true,
                  title: l.passengerReviewStepTitle,
                  subtitle: l.passengerReviewStepSubtitle,
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

/// The last stop before [_PassengerRidePageState._select] hands a driver
/// the passenger's exact pickup coordinates, landmark text and -- if
/// sharing is on -- their phone number. A single stray tap on a scrolling
/// offer list would otherwise leak all of that irreversibly, so the offer
/// being accepted is spelled out and has to be confirmed first.
///
/// It also carries the one price the passenger gets to name.
///
/// Until 2026-08-01 they named one at the START, before publishing, and it
/// went out in the request itself. That was removed: a passenger cannot
/// know what a trip across Ulaanbaatar costs at that hour, so the figure
/// was a guess, and a guess that landed low produced no offers at all --
/// leaving them watching an empty list with nothing saying why. The wish
/// behind it was real, though ("I will pay more to actually get picked
/// up"), so it moved here, where there is a real driver quoting a real
/// number to add it to.
///
/// Stateful, because the total has to move as the rider types. A bonus
/// confirmed against a stale total is a bonus they did not agree to.
class _ConfirmOfferDialog extends StatefulWidget {
  final RideOfferPayload payload;

  const _ConfirmOfferDialog({required this.payload});

  @override
  State<_ConfirmOfferDialog> createState() => _ConfirmOfferDialogState();
}

class _ConfirmOfferDialogState extends State<_ConfirmOfferDialog> {
  final _tip = TextEditingController();

  @override
  void dispose() {
    _tip.dispose();
    super.dispose();
  }

  /// The typed bonus, or 0 for anything that is not a positive number.
  ///
  /// Empty is the common case and means no bonus. A negative is refused
  /// rather than clamped-and-charged: it would reduce a price the driver
  /// has already quoted, which is a counter-offer wearing the wrong name --
  /// the driver would be accepting a figure they never saw.
  int get _tipMnt {
    final value = int.tryParse(_tip.text.trim().replaceAll(RegExp(r'\s'), ''));
    return value == null || value < 0 ? 0 : value;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final payload = widget.payload;

    return AlertDialog(
      // Cyrillic at a large text scale outgrows a phone, and none of this
      // may be cut off: the sheet scrolls rather than losing the bonus box
      // or an action off the bottom.
      scrollable: true,
      title: Text(l.confirmSelectOfferTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.confirmSelectOfferMessage(
              payload.vehicleDescription,
              groupedMnt(payload.priceMnt),
              payload.etaMinutes,
            ),
          ),
          const SizedBox(height: TakhiSpace.sm),
          // Which contract this is, said out loud rather than left to be
          // inferred from whether a tariff line happens to be present.
          //
          // Every taxi argument in the world starts the same way: one side
          // thought the price was fixed and the other thought it was
          // metered. This is the last screen before that becomes somebody's
          // problem at the kerb, so it is the screen that has to say.
          Text(
            payload.kmTariffMnt == null
                ? l.confirmOfferFixedPriceLine(groupedMnt(payload.priceMnt))
                : l.confirmOfferMeteredLine(groupedMnt(payload.priceMnt)),
            style: TakhiType.body.copyWith(
              color: TakhiSurfaces.of(context).onSheet,
            ),
          ),
          const SizedBox(height: TakhiSpace.lg),
          LabeledField(
            key: const Key('confirmOfferTipField'),
            label: l.offerTipFieldLabel,
            icon: Icons.card_giftcard_outlined,
            controller: _tip,
            keyboardType: TextInputType.number,
            hint: l.offerTipHint,
            onChanged: (_) => setState(() {}),
          ),
          // Only once there is a bonus to add. A «Нийт» row that merely
          // repeats the driver's price is noise on a dialog that is already
          // asking for an irreversible decision.
          if (_tipMnt > 0) ...[
            const SizedBox(height: TakhiSpace.sm),
            Text(
              l.offerTipTotalLabel(groupedMnt(payload.priceMnt + _tipMnt)),
              style: TakhiType.title.copyWith(
                color: TakhiSurfaces.of(context).onSheet,
              ),
            ),
          ],
        ],
      ),
      actions: [
        // The one confirmation in this file the rider *sought out* --
        // they tapped an offer -- so unlike the back-guard dialogs the
        // emphasis belongs on going forward, not on backing out.
        DialogActionBar(
          dismiss: DialogAction(
            label: l.cancelAction,
            tone: DialogActionTone.neutral,
            onPressed: () => Navigator.of(context).pop(),
          ),
          proceed: DialogAction(
            // The button records what was agreed to. A fixed offer carries
            // its figure; a metered one carries none, because there is none
            // yet — and a button that showed an estimate as though it were
            // the price would be the first half of the argument this dialog
            // exists to prevent.
            label: payload.kmTariffMnt == null
                ? l.confirmSelectOfferFixedAction(
                    groupedMnt(payload.priceMnt + _tipMnt),
                  )
                : l.confirmSelectOfferMeteredAction,
            tone: DialogActionTone.primary,
            onPressed: () => Navigator.of(context).pop(_tipMnt),
          ),
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
/// 3. **why this order, and whose order it is** -- [rankRideOffers] sorts by
///    the key the rider picked, and a list that silently reorders itself is a
///    list nobody can trust. The heading names the current key in words, the
///    control under it lets the rider change it, and the most-trusted driver
///    is marked wherever they end up sitting.
///
/// The sort control is the part that took the longest to justify. Reputation
/// stays the default -- it is the one ordering a rider cannot reproduce by
/// eye, since price and ETA are printed on every card -- but a default that
/// cannot be overridden is not a default, it is this app deciding what
/// matters on somebody else's behalf. A rider counting coins at the end of the
/// month wants the cheapest offer, and being quietly shown the most trusted
/// one instead is the behaviour every dispatcher app has and the reason this
/// one exists.
/// How tall the offers map is.
///
/// Shorter than the review step's route map (`_kRouteMapHeight`): this one
/// shares its screen with a heading, a sort control and the offer rows,
/// and the rows are what a passenger actually decides on. The map is here
/// to answer "which of these is near me", which needs far less height than
/// following a route across the city.
/// "Take the one arriving soonest", with the offer it means written on it.
///
/// Exists because two different people use this screen. One wants to weigh
/// price against reputation against arrival time -- that is the list, and
/// it is why the list carries all three. The other is standing in the cold
/// and wants a car. Before this, the second person had to read the list
/// anyway, and the app had no answer for them at all.
///
/// It states the price and the arrival time on the button, so it is never
/// a blind "surprise me": what the tap accepts is legible before the tap.
class _QuickPickButton extends StatelessWidget {
  final RankedRideOffer ranked;
  final VoidCallback onPressed;

  const _QuickPickButton({required this.ranked, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final payload = ranked.offer.payload;

    return OutlinedButton.icon(
      key: const Key('offersQuickPickButton'),
      style: OutlinedButton.styleFrom(
        foregroundColor: surfaces.onSheet,
        side: const BorderSide(color: TakhiColors.gold),
        minimumSize: const Size.fromHeight(TakhiTouch.minTarget),
        shape: const RoundedRectangleBorder(borderRadius: TakhiRadius.pillAll),
        // Never the bare token: `ButtonStyle.textStyle` replaces the
        // inherited style rather than merging onto it, and the bundled
        // Cyrillic family would go with it.
        textStyle: takhiButtonTextStyle(context, TakhiType.title),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.bolt_outlined),
      label: Text(
        l.offersQuickPickLabel(
          groupedMnt(payload.priceMnt),
          payload.etaMinutes,
        ),
      ),
    );
  }
}

/// Which half of the offers screen the rider is looking at.
enum _OffersView { list, map }

class _OffersStep extends StatefulWidget {
  final List<RideOffer> offers;

  /// The current unix second, read every tick so an offer's countdown runs
  /// and an expired one drops out of the list. Injected (rather than read off
  /// `DateTime.now` here) so a test can hold the clock still or move it by
  /// hand; production passes the system clock.
  final int Function() nowSeconds;

  /// Where the passenger is waiting, so the map has something for the cars
  /// to be near. Without it "which of these is closest" has no answer.
  final PickedLocation pickup;
  final List<TripReceipt> Function(String driverPubkey) receiptsFor;

  /// Pubkeys this passenger has personally vouched for, from
  /// `trustedDriversProvider`. Empty on a first ride, which is most rides.
  final Set<String> viewerTrusted;

  final ValueChanged<RankedRideOffer> onOpenDriver;

  /// The hurry-up path: take this offer without reading the others.
  ///
  /// Goes straight to `_select`, which still opens the irreversible-
  /// disclosure confirmation -- the shortcut skips the COMPARING, never the
  /// consent. Two taps instead of four; nothing is sent on the first.
  final ValueChanged<RankedRideOffer> onQuickPick;

  /// Withdraws the published request and returns to the price step -- the
  /// way out when no offer arrives, or every one of them is too expensive.
  /// Nobody is told, and nobody needs to be: the passenger is about to
  /// republish, and each driver still has their own offer open.
  final VoidCallback onBack;

  /// Calls the ride off for good, telling every driver who answered.
  ///
  /// A separate action from [onBack] because they answer different
  /// questions. "Буцах" means *reprice this trip*; this one means *I am
  /// not riding*, and it is the only one of the two that owes anybody a
  /// message. Until it existed the second question had no button at all --
  /// a passenger who had changed their mind had to press back, meet a
  /// dialog about leaving the screen, and hope.
  final VoidCallback onCancel;

  const _OffersStep({
    required this.offers,
    required this.nowSeconds,
    required this.pickup,
    required this.receiptsFor,
    required this.viewerTrusted,
    required this.onOpenDriver,
    required this.onQuickPick,
    required this.onBack,
    required this.onCancel,
  });

  @override
  State<_OffersStep> createState() => _OffersStepState();
}

class _OffersStepState extends State<_OffersStep> {
  /// Reputation until the rider says otherwise -- see the class doc for why
  /// that is the right default and why it has to be overridable.
  ///
  /// Held here rather than on `_PassengerRidePageState` because it dies with
  /// the step: a rider who withdrew a request, repriced it and republished is
  /// asking a new question, and inheriting the sort they last used on a list
  /// that no longer exists would be surprising in the exact place surprise is
  /// most expensive.
  OfferSort _sort = OfferSort.reputation;

  /// List until the rider asks for the map. The list carries price,
  /// reputation and ETA -- everything the choice is actually made on -- so
  /// it is what a passenger should land on; the map answers the narrower
  /// question of who is near, and is one tap away.
  _OffersView _view = _OffersView.list;

  /// Ticks once a second so the offers' countdowns advance and an expired one
  /// drops out — nothing else here moves on its own. Scoped to this step, so
  /// it rebuilds only the offer list and not the whole page (the map holds
  /// its own camera across the rebuild and does not re-fetch).
  Timer? _countdownTick;

  /// Whether any offer still has a deadline in the future worth counting down.
  ///
  /// The ticker re-arms only while this is true, and never starts otherwise.
  /// That keeps two things right: a test that never sets an expiry (every
  /// offer's deadline `null`) spins no timer, so `pumpAndSettle` is not left
  /// waiting on one for ever; and once every real offer's deadline has passed
  /// the timer stops on its own, rather than ticking a settled screen and a
  /// battery with it.
  bool _anyOfferStillCounting() {
    final now = widget.nowSeconds();
    return widget.offers.any((o) {
      final expiresAt = o.payload.expiresAtSeconds;
      return expiresAt != null && expiresAt > now;
    });
  }

  @override
  void initState() {
    super.initState();
    if (_anyOfferStillCounting()) _scheduleTick();
  }

  @override
  void didUpdateWidget(_OffersStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An offer carrying a deadline may have just arrived on the stream; start
    // the countdown if one has and it is not already running.
    if (_countdownTick == null && _anyOfferStillCounting()) _scheduleTick();
  }

  void _scheduleTick() {
    _countdownTick = Timer(const Duration(seconds: 1), () {
      _countdownTick = null;
      if (!mounted) return;
      setState(() {});
      if (_anyOfferStillCounting()) _scheduleTick();
    });
  }

  @override
  void dispose() {
    _countdownTick?.cancel();
    super.dispose();
  }

  /// What the heading says the current order means.
  ///
  /// Reputation is the one mode with two answers: until some driver has a
  /// confirmed trip behind them every `trustWeight` is 0, the sort is a
  /// no-op, and calling the list "ranked by reputation" would be dressing
  /// arrival order up as a judgement.
  String _sortHint(AppLocalizations l, bool anyReputation) => switch (_sort) {
    OfferSort.reputation =>
      anyReputation ? l.offersRankedByReputationHint : l.offersAllNewHint,
    OfferSort.price => l.offersSortedByPriceHint,
    OfferSort.eta => l.offersSortedByEtaHint,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final nowSeconds = widget.nowSeconds();
    // An expired offer is hidden rather than deleted: the source list on the
    // page keeps it (deleting mid-tick would fight the offers stream), but a
    // promise the driver can no longer keep is not shown, not ranked, and not
    // reachable by the quick-pick shortcut. A `null` deadline never expires —
    // an offer from a client older than the field, shown as it always was.
    final liveOffers = widget.offers.where((o) {
      final expiresAt = o.payload.expiresAtSeconds;
      return expiresAt == null || expiresAt > nowSeconds;
    }).toList();
    final ranked = rankRideOffers(
      liveOffers,
      receiptsFor: widget.receiptsFor,
      sort: _sort,
      // The passenger's own vouches. A receipt from somebody they have
      // ridden with and chose to trust weighs more than one from a
      // stranger, because faking the first is cheap and faking the second
      // means fooling a specific real person. Empty until they have
      // trusted anyone, which is every passenger's first trip.
      viewerTrusted: widget.viewerTrusted,
    );

    // No map offered at all until some driver's offer actually carries a
    // position: a map holding nothing but the rider's own pin is a grey
    // rectangle, and a toggle onto it is a button that makes the screen
    // worse.
    final mapAvailable = OffersMap.hasPlottableOffers(ranked);
    final showMap = mapAvailable && _view == _OffersView.map;

    // Whoever says they will arrive soonest -- not whoever is nearest in
    // metres. A car three streets away on the wrong side of a jam is
    // "closer" and slower, and what a rider in a hurry is asking is when
    // somebody gets here. Ties keep arrival order, like every other list
    // in this file.
    final fastest = ranked.isEmpty
        ? null
        : ranked.reduce(
            (a, b) =>
                b.offer.payload.etaMinutes < a.offer.payload.etaMinutes ? b : a,
          );

    final anyReputation = ranked.any((r) => r.reputation.trustWeight > 0);
    // Which card carries the badge -- an identity, not a position. See
    // [mostTrustedIndex]: the most-trusted driver is still the most-trusted
    // driver when the rider sorts by price, and a badge that quietly hopped
    // to whoever was cheapest would be a lie told by a layout.
    final topTrust = mostTrustedIndex(ranked);

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
                  subtitle: ranked.isEmpty || showMap
                      ? null
                      : _sortHint(l, anyReputation),
                ),
                // Only once there is a list to reorder. A sort control over
                // an empty screen offers a rider a knob that does nothing
                // while they are waiting on other people.
                if (ranked.isNotEmpty && !showMap) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  SegmentedChoice<OfferSort>(
                    semanticsLabel: l.offersSortSemanticsLabel,
                    value: _sort,
                    onChanged: (sort) => setState(() => _sort = sort),
                    options: [
                      SegmentedOption(
                        value: OfferSort.reputation,
                        label: l.offersSortReputationOption,
                        icon: Icons.verified_outlined,
                      ),
                      SegmentedOption(
                        value: OfferSort.price,
                        label: l.offersSortPriceOption,
                        icon: Icons.payments_outlined,
                      ),
                      SegmentedOption(
                        value: OfferSort.eta,
                        label: l.offersSortEtaOption,
                        icon: Icons.schedule_outlined,
                      ),
                    ],
                  ),
                ],
                // Map or list, never both at once.
                //
                // The first build of this put a 180dp map strip above the
                // rows, and the screenshot settled it: with the heading,
                // the sort control and that strip, exactly ONE offer card
                // was left on screen. The list is where a passenger
                // actually decides -- price, reputation, ETA -- so halving
                // it to make room for a map they cannot pick a car out of
                // either was the worst of both.
                //
                // Given the full frame, each view does its own job: the map
                // answers "which of these is near me", the list answers
                // "which of these do I want".
                if (mapAvailable) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  SegmentedChoice<_OffersView>(
                    semanticsLabel: l.offersViewSemanticsLabel,
                    value: _view,
                    onChanged: (view) => setState(() => _view = view),
                    options: [
                      SegmentedOption(
                        value: _OffersView.list,
                        label: l.offersViewListOption,
                        icon: Icons.view_list_outlined,
                      ),
                      SegmentedOption(
                        value: _OffersView.map,
                        label: l.offersViewMapOption,
                        icon: Icons.map_outlined,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: TakhiSpace.lg),
                Expanded(
                  child: ranked.isEmpty
                      ? const _OffersWaitingView()
                      : showMap
                      ? MapCard(
                          height: double.infinity,
                          child: OffersMap(
                            pickup: ll.LatLng(
                              widget.pickup.lat,
                              widget.pickup.lon,
                            ),
                            offers: ranked,
                            onTapDriver: widget.onOpenDriver,
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: ranked.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: TakhiSpace.sm),
                          itemBuilder: (context, i) => _OfferCard(
                            ranked: ranked[i],
                            leads: i == topTrust,
                            viewerTrusts: widget.viewerTrusted.contains(
                              ranked[i].offer.driverPubkey,
                            ),
                            nowSeconds: nowSeconds,
                            onTap: () => widget.onOpenDriver(ranked[i]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        TakhiSheet(
          showHandle: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The step's own action, in the place every other step in
              // this wizard keeps one.
              //
              // It started life above the list and was moved here after
              // the screenshot: stacked with the sort control and the
              // list/map switch it made THREE full-width pills before a
              // single offer appeared, leaving one and a half cards on a
              // 360dp phone. The list is what a rider decides on; three
              // rows of chrome above it is the same mistake the map strip
              // made, in a different shape.
              if (fastest != null) ...[
                _QuickPickButton(
                  ranked: fastest,
                  onPressed: () => widget.onQuickPick(fastest),
                ),
                const SizedBox(height: TakhiSpace.xs),
              ],
              // Above «Буцах» rather than below it: this is the answer to
              // the question the empty half of this screen keeps asking
              // ("is anyone coming?"), and the one with a consequence
              // outside this phone.
              SecondaryButton(
                label: l.cancelRideRequestAction,
                onPressed: widget.onCancel,
              ),
              const SizedBox(height: TakhiSpace.xs),
              SecondaryButton(label: l.backAction, onPressed: widget.onBack),
            ],
          ),
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
/// [EmptyState] carries the shape and the reasoning behind it -- including
/// why it is deliberately still rather than spinning: the request is already
/// out, and what the app is waiting on is other people.
class _OffersWaitingView extends StatelessWidget {
  const _OffersWaitingView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return EmptyState(
      icon: Icons.wifi_tethering,
      title: l.offersWaitingEmptyTitle,
      message: l.offersWaitingEmptyHint,
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

  /// Whether this offer belongs to the single most-trusted driver on the
  /// list -- see [mostTrustedIndex], which is also where "nobody" comes from.
  /// Decided by the list, not by the card: a card cannot see the ones around
  /// it, and "first among ties" is not a distinction.
  ///
  /// Note what this is *not*: "is this the top row". The badge names a
  /// driver, so it stays on that driver when the rider re-sorts the list by
  /// price and they end up third.
  final bool leads;

  /// Whether the rider has personally vouched for this offer's driver -- the
  /// "I trust this driver" tick from a past ride. Unlike [leads], which is a
  /// comparison against the other offers on this list, this is a fact about
  /// this one driver, so it is decided per card from the rider's trusted set.
  final bool viewerTrusts;

  /// The current unix second, handed down each tick so the validity countdown
  /// reads the same clock the list expires offers against. The card is
  /// stateless and rebuilt by the step's ticker, so it does not own a timer.
  final int nowSeconds;

  final VoidCallback onTap;

  const _OfferCard({
    required this.ranked,
    required this.leads,
    required this.viewerTrusts,
    required this.nowSeconds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final expiresAt = ranked.offer.payload.expiresAtSeconds;
    // Never negative: the list has already hidden any offer past its deadline,
    // so this only ever counts a positive remainder down, and the guard just
    // covers the single tick where the two cross.
    final remainingSeconds = expiresAt == null
        ? null
        : (expiresAt - nowSeconds < 0 ? 0 : expiresAt - nowSeconds);

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
                  viewerTrusts: viewerTrusts,
                  // A plain row is a statement; the chevron is what says
                  // this one does something when pressed.
                  trailing: Icon(Icons.chevron_right, color: surfaces.muted),
                ),
                const SizedBox(height: TakhiSpace.xs),
                OfferTerms(payload: ranked.offer.payload),
                // A live shelf life, only for an offer that carries a
                // deadline. It turns from calm to clay in the last
                // [_kOfferExpirySoonSeconds] so a rider weighing this row
                // sees it is about to go before it vanishes under their eyes.
                if (remainingSeconds != null) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  InfoChip(
                    icon: Icons.timelapse_outlined,
                    label: l.offerValidForLabel(displayClock(remainingSeconds)),
                    accent: remainingSeconds <= _kOfferExpirySoonSeconds
                        ? TakhiAccent.clay
                        : TakhiAccent.steppe,
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

  /// Where the passenger is standing -- the map's anchor, and what the
  /// driver is driving towards.
  final PickedLocation pickup;

  /// The chosen driver's last reported position, or `null` until their
  /// first ping lands. Null draws no car: a passenger deciding whether to
  /// step outside is acting on this dot, and a dot that is guessing is
  /// worse than no dot at all.
  final ll.LatLng? driverPosition;

  final ll.LatLng? devicePosition;
  final double? deviceAccuracyMeters;

  /// The four-digit code the passenger reads out to the driver at the kerb,
  /// minted on this device when they made the selection. Null only for an
  /// old in-flight selection that predates the field; the card simply
  /// doesn't draw then.
  final String? startCode;

  final VoidCallback onStartTrip;

  /// Calls the booking off and tells the driver who is already coming
  /// (spec §7.5). Under the forward action rather than beside it: a
  /// passenger reading this screen is checking who is on their way, and the
  /// answer they need most of the time is "get in", not "cancel".
  final VoidCallback onCancel;

  const _DoneStep({
    required this.selected,
    required this.pickup,
    required this.startCode,
    required this.driverPosition,
    required this.devicePosition,
    required this.deviceAccuracyMeters,
    required this.onStartTrip,
    required this.onCancel,
  });

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
                  const SizedBox(height: TakhiSpace.md),
                  // The pickup code, held big and gold so it reads at arm's
                  // length: the passenger says it aloud when the car pulls up
                  // and the driver types it before the meter runs, so the two
                  // are proven to be the same pair before any money is owed.
                  // Only drawn when there is a code -- an old in-flight
                  // selection from before this field simply skips it.
                  if (startCode != null) ...[
                    _StartCodeCard(code: startCode!),
                    const SizedBox(height: TakhiSpace.lg),
                  ],
                  // The car, moving, for as long as it takes them to get
                  // here. Both the encrypted position channel and this map
                  // already existed -- they were simply not opened until
                  // the trip was STARTED, a button pressed at the kerb. The
                  // minutes before that are the ones a waiting passenger
                  // actually wants to watch.
                  MapCard(
                    height: _kApproachMapHeight,
                    child: TripTrackingMap(
                      selfPosition: devicePosition,
                      selfAccuracyMeters: deviceAccuracyMeters,
                      counterpartyPosition: driverPosition,
                      counterpartyIsDriver: true,
                      fallbackCenter: ll.LatLng(pickup.lat, pickup.lon),
                    ),
                  ),
                  // Said plainly while nothing has arrived, rather than
                  // leaving an empty map to be read as "the driver is not
                  // moving". Their phone may still be waking its GPS up.
                  if (driverPosition == null) ...[
                    const SizedBox(height: TakhiSpace.sm),
                    Text(
                      l.passengerAwaitingDriverPositionHint,
                      textAlign: TextAlign.center,
                      style: TakhiType.support.copyWith(color: surfaces.muted),
                    ),
                  ],
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
        _StepActions(
          label: l.startTripAction,
          onPressed: onStartTrip,
          onBack: onCancel,
          backLabel: l.cancelSelectedDriverAction,
        ),
      ],
    );
  }
}

/// The pickup code, drawn as the one thing on this screen a passenger has to
/// read out loud. Gold on a gold-tinted field so it separates from the map
/// and the driver card around it, and spaced wide so `0421` never reads as
/// `042 1` across a car window in the dark.
class _StartCodeCard extends StatelessWidget {
  const _StartCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    // The brand gold as a ground/foreground pair that moves with brightness
    // and is asserted at >= 4.5:1 in both -- so the code stays legible on the
    // wash in dark mode too, which a flat `TakhiColors.gold` could not
    // promise (2.28:1 on a light sheet). `tint` lifts the card off the sheet
    // without becoming a second button; `onTint` carries the digits.
    final gold = takhiAccentColors(
      TakhiAccent.gold,
      Theme.of(context).brightness,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: gold.tint,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: gold.onTint),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: TakhiSpace.md,
          horizontal: TakhiSpace.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.passengerStartCodeTitle,
              textAlign: TextAlign.center,
              style: TakhiType.support.copyWith(color: surfaces.muted),
            ),
            const SizedBox(height: TakhiSpace.xs),
            Text(
              code,
              textAlign: TextAlign.center,
              // Positive tracking is safe here where numericDisplay forbids it
              // for fares: there is no `₮` to collide with, only digits, and
              // the gap is what makes the code legible when spoken.
              style: TakhiType.numericDisplay.copyWith(
                color: gold.onTint,
                letterSpacing: 10,
              ),
            ),
            const SizedBox(height: TakhiSpace.xs),
            Text(
              l.passengerStartCodeHint,
              textAlign: TextAlign.center,
              style: TakhiType.support.copyWith(color: surfaces.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The cancel confirmation, now carrying a reason. The passenger says *why*
/// they are backing out so the driver reads "the rider changed their mind"
/// rather than a bare "cancelled" — three segments, no free typing, because a
/// person calling a ride off wants one tap, not a form.
///
/// A bottom sheet rather than an `AlertDialog`: the [SegmentedChoice] measures
/// itself with a `LayoutBuilder`, which the intrinsic-width sizing of an
/// `AlertDialog` cannot lay out — the same reason the driver's own
/// cancellation notice is a sheet.
///
/// It pops the picked [RideCancelReason] on confirm and nothing on keep (or a
/// barrier/back dismiss), so the caller sends a cancel only when a reason
/// comes back. The picker starts on [RideCancelReason.passengerChangedMind],
/// the honest default and by far the commonest case.
class _CancelReasonSheet extends StatefulWidget {
  const _CancelReasonSheet({required this.title, required this.message});

  final String title;
  final String message;

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  RideCancelReason _reason = RideCancelReason.passengerChangedMind;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return TakhiSheet(
      showHandle: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            compact: true,
            title: widget.title,
            subtitle: widget.message,
          ),
          const SizedBox(height: TakhiSpace.lg),
          SegmentedChoice<RideCancelReason>(
            semanticsLabel: l.cancelReasonPickerLabel,
            value: _reason,
            onChanged: (r) => setState(() => _reason = r),
            options: [
              SegmentedOption(
                value: RideCancelReason.passengerChangedMind,
                label: l.cancelReasonChangedMind,
              ),
              SegmentedOption(
                value: RideCancelReason.driverTooFar,
                label: l.cancelReasonDriverTooFar,
              ),
              SegmentedOption(
                value: RideCancelReason.other,
                label: l.cancelReasonOther,
              ),
            ],
          ),
          const SizedBox(height: TakhiSpace.lg),
          DialogActionBar(
            dismiss: DialogAction(
              label: l.keepRideAction,
              tone: DialogActionTone.neutral,
              onPressed: () => Navigator.of(context).pop(),
            ),
            proceed: DialogAction(
              label: l.cancelRideConfirmAction,
              tone: DialogActionTone.caution,
              onPressed: () => Navigator.of(context).pop(_reason),
            ),
          ),
        ],
      ),
    );
  }
}
