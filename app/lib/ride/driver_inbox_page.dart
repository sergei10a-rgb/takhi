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
import '../meter/money_format.dart';
import '../payment/driver_qr_capture_page.dart';
import '../profile/profile_providers.dart';
import '../theme/takhi_theme.dart';
import '../widgets/address_row.dart';
import '../widgets/confirm_leave_scope.dart';
import '../widgets/dialog_action_bar.dart';
import '../widgets/info_chip.dart';
import '../widgets/labeled_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'active_trip_view.dart';
import 'driver_inbox_service.dart';
import 'handoff_service.dart';
import 'metered_tariff_label.dart';
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

  /// The waiting rate that went out with [_lastOfferedKmTariffMnt]. Never
  /// set on its own: the two halves of a metered price are offered
  /// together, accepted together, and metered together, so a trip can never
  /// end up running on one driver's distance rate and nobody's waiting
  /// rate.
  int? _lastOfferedWaitTariffMntPerMinute;

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
    // Rides along with the km-tariff rather than being a separate choice in
    // the offer dialog: it is the same published profile figure, and a
    // driver deciding to meter this trip is offering both of their rates.
    final driverWaitTariffMntPerMinute = driverProfile?.waitTariffMntPerMinute;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _OfferDialog(
        // What the passenger themselves published about this call. A driver
        // pricing a job they cannot see anything about is guessing, and the
        // dialog used to open as three empty boxes with no clue which of
        // the pins on the map it belonged to.
        requestNote: listing.request.note,
        requestOfferedMnt: listing.request.offeredMnt,
        driverKmTariffMnt: driverKmTariffMnt,
        driverWaitTariffMntPerMinute: driverWaitTariffMntPerMinute,
        onSubmit: (priceMnt, etaMinutes, vehicle, kmTariffMnt) async {
          // Null unless this is a metered offer: a fixed price already
          // covers however long the trip stands still, so quoting a waiting
          // rate beside it would describe a charge that never applies.
          final waitTariffMntPerMinute = kmTariffMnt == null
              ? null
              : driverWaitTariffMntPerMinute;
          setState(() {
            _lastOfferedPriceMnt = priceMnt;
            _lastOfferedKmTariffMnt = kmTariffMnt;
            _lastOfferedWaitTariffMntPerMinute = waitTariffMntPerMinute;
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
                  waitTariffMntPerMinute: waitTariffMntPerMinute,
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
    // Cleared with its partner, never on its own -- the two halves of a
    // metered price are set together in `_sendOffer` and must not be able
    // to survive a shift apart from one another.
    _lastOfferedWaitTariffMntPerMinute = null;
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
      return _shell(
        l,
        ActiveTripView(
          role: TripRole.driver,
          tripId: handoff.payload.tripId,
          counterpartyPubHex: handoff.senderPubkey,
          agreedPriceMnt: _lastOfferedPriceMnt ?? 0,
          counterpartyPhone: handoff.payload.phone,
          kmTariffMnt: _lastOfferedKmTariffMnt,
          waitTariffMntPerMinute: _lastOfferedWaitTariffMntPerMinute,
          onTripSettled: () => setState(() => _tripInFlight = false),
          onFinished: _finishTrip,
        ),
      );
    }
    if (handoff != null) {
      return _shell(
        l,
        _AwardedHandoffView(
          handoff: handoff,
          agreedPriceMnt: _lastOfferedPriceMnt,
          onStartTrip: () => setState(() {
            _activeTrip = true;
            _tripInFlight = true;
          }),
        ),
      );
    }
    return _shell(
      l,
      _ListeningView(
        center: _myLocation,
        listings: _listings,
        onCenterChanged: (c) => setState(() => _myLocation = c),
        onTapListing: _sendOffer,
      ),
    );
  }

  /// The one `Scaffold` all three states share.
  ///
  /// Written once rather than per branch because the QR action in the bar
  /// is a shift-long affordance, not a per-screen one: the driver's payment
  /// code is what a passenger scans at the *end* of a trip, so dropping the
  /// action on any branch leaves the moment it is needed with no way to
  /// reach it.
  Widget _shell(AppLocalizations l, Widget body) => Scaffold(
    appBar: AppBar(
      title: Text(l.appName),
      actions: [_QrSettingsAction(tooltip: l.qrCaptureTitle)],
    ),
    body: body,
  );
}

/// The between-trips state: a full-bleed map of nearby calls, with a sheet
/// on it saying what the screen is doing.
///
/// The map on its own was the whole screen, and on a quiet street it is a
/// blank grey field -- a driver who has just tapped "Жолоочоор" could not
/// tell a working app from a broken one, an empty street from a lost relay
/// connection. The sheet answers both: it names the state, says how a call
/// arrives, and counts what is currently visible. Zero is an answer.
class _ListeningView extends StatelessWidget {
  final ll.LatLng center;
  final List<RideRequestListing> listings;
  final ValueChanged<ll.LatLng> onCenterChanged;
  final ValueChanged<RideRequestListing> onTapListing;

  const _ListeningView({
    required this.center,
    required this.listings,
    required this.onCenterChanged,
    required this.onTapListing,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Stack(
      children: [
        Positioned.fill(
          child: RideMap(
            initialCenter: center,
            onCenterChanged: onCenterChanged,
            layers: [
              NearbyRequestsLayer(listings: listings, onTap: onTapListing),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          // Opaque so a drag that starts on the sheet stays on the sheet
          // rather than panning the map underneath it (the guard
          // `HomePage._HomeSheet` documents).
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            child: TakhiSheet(
              showHandle: false,
              child: SectionHeading(
                compact: true,
                title: l.driverInboxListeningTitle,
                subtitle: l.driverInboxListeningSubtitle,
                // On the heading's own line rather than on a row of its
                // own: the count qualifies the state, and the sheet has to
                // stay short enough that it never covers a pin the driver
                // is reaching for.
                trailing: InfoChip(
                  icon: Icons.hail,
                  label: l.driverInboxNearbyCountLabel(listings.length),
                  accent: listings.isEmpty
                      ? TakhiAccent.neutral
                      : TakhiAccent.steppe,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The passenger picked this driver, and here is where to collect them.
///
/// The screen used to open with the pickup point and nothing else: no word
/// that the offer had been won, no sight of the price this driver had just
/// committed to, and the Plus Code -- the one string on the glass a driver
/// retypes into a navigation app -- set as unstyled body text between two
/// other unstyled lines. Now the outcome is stated first, the point is an
/// [AddressRow] (readable name on top, exact code underneath, exactly as
/// the rest of the app states a place), and the agreed fare rides beside it
/// as a chip.
class _AwardedHandoffView extends StatelessWidget {
  final ReceivedHandoff handoff;

  /// What this driver offered for the trip, when the offer went out from
  /// this same session. `null` after a restart -- the offer lives only in
  /// `_DriverInboxPageState` -- in which case the chip is simply absent
  /// rather than showing a zero nobody agreed to.
  final int? agreedPriceMnt;

  final VoidCallback onStartTrip;

  const _AwardedHandoffView({
    required this.handoff,
    required this.agreedPriceMnt,
    required this.onStartTrip,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final payload = handoff.payload;
    final landmark = payload.landmarkText.trim();
    final price = agreedPriceMnt;
    final sharedPhone = payload.phone?.trim();
    final phone = sharedPhone == null || sharedPhone.isEmpty
        ? null
        : sharedPhone;

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
              children: [
                SectionHeading(
                  title: l.driverAwardedTitle,
                  subtitle: l.driverAwardedSubtitle,
                ),
                const SizedBox(height: TakhiSpace.lg),
                DecoratedBox(
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
                    child: AddressRow(
                      icon: Icons.person_pin_circle,
                      label: l.handoffReceivedTitle,
                      // The landmark leads because it is the half a human
                      // reads; the Plus Code sits under it as the exact
                      // form, which is the split `AddressRow` exists for. A
                      // passenger who wrote no landmark leaves the code to
                      // carry the row on its own rather than leaving the
                      // primary line blank.
                      value: landmark.isEmpty ? payload.plusCode : landmark,
                      detail: landmark.isEmpty ? null : payload.plusCode,
                      accent: TakhiAccent.steppe,
                    ),
                  ),
                ),
                // The two facts a driver acts on between "you won it" and
                // "drive there": what was agreed, and -- when the passenger
                // chose to share it (spec §6, opt-in per trip) -- the number
                // to ring when they cannot find the doorway. Neither was
                // anywhere on this screen before, and the phone number in
                // particular was carried in the handoff and then shown
                // nowhere until a call had already failed.
                if (price != null || phone != null) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  Wrap(
                    spacing: TakhiSpace.xs,
                    runSpacing: TakhiSpace.xs,
                    children: [
                      if (price != null)
                        InfoChip(
                          icon: Icons.payments_outlined,
                          label: l.meterFareLabel(groupedMnt(price)),
                          accent: TakhiAccent.gold,
                        ),
                      if (phone != null)
                        InfoChip(
                          icon: Icons.phone_outlined,
                          label: phone,
                          accent: TakhiAccent.steppe,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        TakhiSheet(
          showHandle: false,
          child: PrimaryButton(
            label: l.viewActiveTripAction,
            onPressed: onStartTrip,
          ),
        ),
      ],
    );
  }
}

/// What a driver answers a call with: a price, how soon they can be there,
/// and which car to look for.
///
/// It opened as three underlined Material fields with floating labels and
/// no heading -- a form, with nothing on it saying which of the pins on the
/// map it belonged to or what the passenger had asked for. What it is now
/// is a statement of the call (whatever the passenger wrote, and the price
/// they proposed if they named one) followed by the three answers, each in
/// the app's own capsule with its label standing above it so it survives
/// being filled in.
class _OfferDialog extends StatefulWidget {
  final Future<void> Function(
    int priceMnt,
    int etaMinutes,
    String vehicle,
    int? kmTariffMnt,
  )
  onSubmit;

  /// The free text the passenger attached to their public request. Empty
  /// for a request that carried none, in which case there is nothing to
  /// state and the block is left out entirely rather than rendered blank.
  final String requestNote;

  /// The price the passenger proposed, when they named one (spec §5 makes
  /// it optional). `null` means they left it to the drivers.
  final int? requestOfferedMnt;

  /// See `_DriverInboxPageState._sendOffer`'s doc comment -- `null` means
  /// this driver has no saved km-tariff, so the metered-pricing toggle
  /// (spec §7.2) is not offered at all.
  final int? driverKmTariffMnt;

  /// The §7.4 waiting rate that would ride along with [driverKmTariffMnt].
  /// Shown beside it rather than left implicit: the toggle commits this
  /// driver to *both* rates at once, and a rate they cannot see on the way
  /// out is one they cannot check. `null`/zero is a complete answer --
  /// waiting is free -- not a missing one.
  final int? driverWaitTariffMntPerMinute;

  const _OfferDialog({
    required this.onSubmit,
    this.requestNote = '',
    this.requestOfferedMnt,
    this.driverKmTariffMnt,
    this.driverWaitTariffMntPerMinute,
  });

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
    final note = widget.requestNote.trim();
    final offered = widget.requestOfferedMnt;
    final hasContext = note.isNotEmpty || offered != null;

    return AlertDialog(
      // Nothing here is allowed to be cut off, and a Mongolian label at a
      // large text scale can outgrow a phone: let the sheet scroll rather
      // than let the metered toggle fall off the bottom of it.
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(
        TakhiSpace.xl,
        TakhiSpace.xl,
        TakhiSpace.xl,
        TakhiSpace.md,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            compact: true,
            title: l.offerDialogTitle,
            subtitle: l.offerDialogSubtitle,
          ),
          if (hasContext) ...[
            const SizedBox(height: TakhiSpace.lg),
            _RequestContext(note: note, offeredMnt: offered),
          ],
          const SizedBox(height: TakhiSpace.lg),
          LabeledField(
            label: l.offerPriceFieldLabel,
            icon: Icons.payments_outlined,
            controller: _price,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: TakhiSpace.md),
          LabeledField(
            label: l.offerEtaFieldLabel,
            icon: Icons.schedule_outlined,
            controller: _eta,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: TakhiSpace.md),
          LabeledField(
            label: l.offerVehicleFieldLabel,
            icon: Icons.directions_car_outlined,
            controller: _vehicle,
            // The one field here whose answer is words rather than digits,
            // and "Цагаан Toyota Prius 30, 1234УБА" does not fit one line
            // of a 390dp phone. At one line the capsule scrolls to the
            // caret and the driver checks their own offer against
            // «ан Toyota Prius 30, 1234УБА» -- no ellipsis, no way to tell
            // a lost word from a typing mistake. This is what the
            // passenger identifies the car by, so it has to be readable
            // whole before it is sent.
            maxLines: 2,
          ),
          const SizedBox(height: TakhiSpace.lg),
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
            _MeteredToggle(
              value: _metered,
              onChanged: (v) => setState(() => _metered = v),
              label: l.meteredOfferToggleLabel,
              // Spec §7.4: the toggle commits this driver to both rates at
              // once, so both are on screen before it is ticked -- including
              // the case where the waiting rate is zero, which is a price
              // ("waiting is free"), not a blank.
              detail: meteredTariffLabel(
                l,
                kmTariffMnt: driverKmTariffMnt,
                waitTariffMntPerMinute: widget.driverWaitTariffMntPerMinute,
              ),
            )
          else
            _NoTariffHint(text: l.meteredOfferNoTariffHint),
        ],
      ),
      actions: [
        DialogActionBar(
          // Until this existed the only ways out of this dialog were a
          // barrier tap and the hardware back button -- neither of them
          // visible, so a driver who tapped the wrong request on the map
          // had no on-screen way back and could easily send an offer just
          // to be rid of it. Disabled mid-publish so a stray tap cannot
          // tear the dialog down while `sendOffer` is still in flight.
          dismiss: DialogAction(
            label: l.cancelAction,
            tone: DialogActionTone.neutral,
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          ),
          proceed: DialogAction(
            label: l.sendOfferAction,
            tone: DialogActionTone.primary,
            busy: _submitting,
            // `_submit` is `Future<void>`, but `DialogAction.onPressed` is
            // a `VoidCallback` -- `unawaited()` makes the fire-and-forget
            // explicit (dart/coding-style.md), instead of the Future (and
            // any error `sendOffer` throws) being silently dropped.
            onPressed: () => unawaited(_submit()),
          ),
        ),
      ],
    );
  }
}

/// What the passenger said about the call being bid on.
///
/// Deliberately a statement and not a field: everything in it was written
/// by somebody else, and a driver reading "хоёр хүн, ачаагүй" beside a
/// proposed price is pricing a job rather than filling in a form.
class _RequestContext extends StatelessWidget {
  final String note;
  final int? offeredMnt;

  const _RequestContext({required this.note, required this.offeredMnt});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final price = offeredMnt;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.field,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.isNotEmpty) ...[
              Text(
                l.offerRequestNoteLabel,
                style: TakhiType.micro.copyWith(color: surfaces.muted),
              ),
              const SizedBox(height: TakhiSpace.xxs),
              Text(
                note,
                style: TakhiType.body.copyWith(color: surfaces.onSheet),
              ),
            ],
            if (price != null) ...[
              if (note.isNotEmpty) const SizedBox(height: TakhiSpace.sm),
              InfoChip(
                icon: Icons.local_offer_outlined,
                label: l.offerRequestOfferedPriceLabel(groupedMnt(price)),
                accent: TakhiAccent.sky,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Charge this trip on my meter instead", as one tappable row.
///
/// A `CheckboxListTile` put the two-line Cyrillic label on the left and the
/// box on the far right edge of the dialog, so the tick sat opposite the
/// second line of a label it belonged to. This keeps the same control and
/// the same words, aligned to the first line and inside a well the whole of
/// which is the touch target.
class _MeteredToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  /// Both of this driver's rates, spelled out (see the call site).
  final String detail;

  const _MeteredToggle({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return Material(
      color: surfaces.field,
      borderRadius: TakhiRadius.cardAll,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: TakhiRadius.cardAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TakhiSpace.sm,
            vertical: TakhiSpace.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TakhiType.title.copyWith(color: surfaces.onSheet),
                    ),
                    const SizedBox(height: TakhiSpace.xxs),
                    Text(
                      detail,
                      style: TakhiType.support.copyWith(color: surfaces.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TakhiSpace.sm),
              Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the metered option is not on this dialog.
///
/// Said out loud rather than left as an absence: a driver who came here to
/// offer a metered price and finds no such choice needs to be told where
/// the tariff lives, and a bare missing checkbox tells them nothing.
class _NoTariffHint extends StatelessWidget {
  final String text;

  const _NoTariffHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: _kHintGlyphSize, color: surfaces.muted),
        const SizedBox(width: TakhiSpace.xs),
        Expanded(
          child: Text(
            text,
            style: TakhiType.support.copyWith(color: surfaces.muted),
          ),
        ),
      ],
    );
  }
}

/// Glyph beside a one-line explanatory hint. Matched to
/// [TakhiType.support]'s cap height so the mark and the sentence share a
/// baseline instead of the icon riding above it.
const _kHintGlyphSize = 16.0;

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
