// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../call/call_providers.dart';
import '../config/city_config.dart';
import '../home/home_status_row.dart' show shortenNpub;
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/location_picker.dart';
import '../meter/money_format.dart';
import '../theme/takhi_theme.dart';
import '../widgets/accent_dot.dart';
import '../widgets/address_row.dart';
import '../widgets/confirm_leave_scope.dart';
import '../widgets/dialog_action_bar.dart';
import '../widgets/info_chip.dart';
import '../widgets/person_row.dart';
import '../widgets/labeled_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'active_trip_view.dart';
import 'ride_dm_payload.dart';
import 'metered_tariff_label.dart';
import 'offer_ranking.dart';
import 'offer_service.dart';
import 'ride_providers.dart';
import 'trip_role.dart';

/// Diameter of the mark that stands for the whole waiting state while no
/// offer has arrived. Large enough to be the thing the eye lands on -- the
/// step is otherwise a title over an empty half-screen, which reads as a
/// screen that failed to load rather than as one that is working.
const _kWaitingMarkSize = 72.0;

/// How many characters of a driver's `npub` the avatar mark carries.
///
/// Two, and they are the *first two of the key itself* rather than the
/// first two of the string: every npub begins `npub1`, so a mark taken off
/// the front would read "NP" for every driver on the list. Taken from
/// after the prefix it varies per driver and matches the head of the key
/// printed beside it, which is what makes it checkable rather than
/// decorative.
const _kDriverMarkLength = 2;

/// Where the human-readable part of a bech32 `npub` starts: past the `npub`
/// prefix and its `1` separator.
const _kNpubDataOffset = 5;

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
              onChanged: (p) => _pickup = p,
              onNext: () => setState(() => _step = _PassengerStep.destination),
            ),
            _PassengerStep.destination => _LocationStep(
              key: const ValueKey(_PassengerStep.destination),
              title: l.passengerDestinationStepTitle,
              subtitle: l.passengerDestinationStepSubtitle,
              initialCenter: ll.LatLng(_destination.lat, _destination.lon),
              initialLandmarkText: _destination.landmarkText,
              onChanged: (p) => _destination = p,
              onNext: () => setState(() => _step = _PassengerStep.price),
              onBack: () => _goBackTo(_PassengerStep.pickup),
            ),
            _PassengerStep.price => _PriceStep(
              controller: _priceController,
              pickup: _pickup,
              destination: _destination,
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
  final VoidCallback onPublish;
  final VoidCallback onBack;

  const _PriceStep({
    required this.controller,
    required this.pickup,
    required this.destination,
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
                  title: l.passengerPriceStepTitle,
                  subtitle: l.passengerPriceStepSubtitle,
                ),
                const SizedBox(height: TakhiSpace.lg),
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
  final ValueChanged<RankedRideOffer> onSelect;

  /// Withdraws the published request and returns to the price step -- the
  /// way out when no offer arrives, or every one of them is too expensive.
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
                            onTap: () => onSelect(ranked[i]),
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

/// One driver's offer, as a card the rider presses to accept it.
///
/// A card and not a `ListTile`: three offers stacked as plain text run
/// together into one block a rider has to parse line by line, and nothing in
/// it says any of it can be tapped -- which matters more here than anywhere
/// else in the app, because this tap is what sends a stranger an exact
/// address.
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
                _DriverIdentityRow(
                  ranked: ranked,
                  // A plain row is a statement; the chevron is what says
                  // this one does something when pressed.
                  trailing: Icon(Icons.chevron_right, color: surfaces.muted),
                ),
                const SizedBox(height: TakhiSpace.xs),
                _OfferTerms(payload: ranked.offer.payload),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Who is offering, and what standing they have.
///
/// The name line is the driver's key, shortened. This app mints no display
/// names and asks no server for one, so the key *is* the identity -- and the
/// avatar mark is cut from the same string (see [_kDriverMarkLength]) so the
/// two agree and a rider comparing them has something to compare.
///
/// The reputation underneath is stated as trips rather than as the score the
/// list sorts by. `trustWeight` is a damped, web-of-trust-weighted figure
/// (spec §9) that means nothing to a rider standing on a kerb; "eleven trips
/// both sides signed off on" is the fact it is computed from, and the one
/// they can actually weigh. A driver with none is told apart from a
/// badly-rated one in words, and their star is hidden entirely -- an average
/// of zero over no ratings is not a rating.
class _DriverIdentityRow extends StatelessWidget {
  final RankedRideOffer ranked;
  final Widget? trailing;

  const _DriverIdentityRow({required this.ranked, this.trailing});

  /// The two characters the avatar carries: the first of the key's own
  /// data, past the shared `npub1` prefix. Falls back to the whole string
  /// for anything too short to slice, which keeps a malformed or
  /// test-shortened key rendering as itself rather than throwing.
  static String _mark(String npub) {
    if (npub.length < _kNpubDataOffset + _kDriverMarkLength) {
      return npub.toUpperCase();
    }
    return npub
        .substring(_kNpubDataOffset, _kNpubDataOffset + _kDriverMarkLength)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final reputation = ranked.reputation;
    final trips = reputation.pairedTripCount;
    final npub = hexToNpub(ranked.offer.driverPubkey);

    return PersonRow(
      name: shortenNpub(npub),
      initials: _mark(npub),
      rating: trips == 0 ? null : reputation.averageRating,
      subtitle: trips == 0
          ? l.driverNoConfirmedTripsLabel
          : l.driverConfirmedTripsLabel(trips),
      // Colour carries the same fact the words do: steppe is this app's
      // "confirmed, established" family, neutral says a driver has no
      // history yet rather than a bad one.
      accent: trips == 0 ? TakhiAccent.neutral : TakhiAccent.steppe,
      trailing: trailing,
    );
  }
}

/// What the offer costs and what turns up for it.
///
/// The fare is the card's one large figure because it is the number being
/// compared down the list; everything qualifying it -- how soon, which car,
/// what the meter charges -- is a chip, which is how this app writes
/// metadata everywhere else.
class _OfferTerms extends StatelessWidget {
  final RideOfferPayload payload;

  /// Whether to repeat the vehicle here. False where the screen has already
  /// named it in its heading: printing "мөнгөлөг Toyota Alphard" twice on
  /// one short screen reads as a fault, not as emphasis.
  final bool showVehicle;

  const _OfferTerms({required this.payload, this.showVehicle = true});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final kmTariffMnt = payload.kmTariffMnt;

    // Spec §7.2/§7.4: a metered offer is not one price but two rates, and
    // this list is where the rider chooses between drivers. Both rates
    // therefore sit on the card itself -- never behind the confirm dialog,
    // never derived after the trip. `null` is a plain fixed-price offer,
    // which stays the single figure it has always been: quoting rates
    // beside it would describe charges that never apply.
    final qualifiers = <Widget>[
      if (showVehicle)
        InfoChip(
          icon: Icons.directions_car_filled_outlined,
          label: payload.vehicleDescription,
        ),
      if (kmTariffMnt != null)
        InfoChip(
          icon: Icons.speed_outlined,
          label: meteredTariffLabel(
            l,
            kmTariffMnt: kmTariffMnt,
            waitTariffMntPerMinute: payload.waitTariffMntPerMinute,
          ),
          accent: TakhiAccent.gold,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.meterFareLabel(groupedMnt(payload.priceMnt)),
                style: TakhiType.numeric.copyWith(color: surfaces.onSheet),
              ),
            ),
            InfoChip(
              icon: Icons.schedule_outlined,
              label: l.offerEtaLabel(payload.etaMinutes),
              accent: TakhiAccent.steppe,
            ),
          ],
        ),
        if (qualifiers.isNotEmpty) ...[
          const SizedBox(height: TakhiSpace.xs),
          Wrap(
            spacing: TakhiSpace.xs,
            runSpacing: TakhiSpace.xs,
            children: qualifiers,
          ),
        ],
      ],
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
                          _DriverIdentityRow(ranked: chosen),
                          const SizedBox(height: TakhiSpace.xs),
                          _OfferTerms(
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
