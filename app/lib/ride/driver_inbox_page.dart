// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../identity/identity_service.dart' show Identity;
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/nearby_requests_layer.dart';
import '../map/ride_map.dart';
import '../payment/driver_qr_capture_page.dart';
import '../widgets/primary_button.dart';
import 'driver_inbox_service.dart';
import 'handoff_service.dart';
import 'ride_dm_payload.dart';
import 'ride_providers.dart';

const _defaultCityCenter = ll.LatLng(47.9186, 106.9176);

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
  ll.LatLng _myLocation = _defaultCityCenter;
  final List<RideRequestListing> _listings = [];
  ReceivedHandoff? _awardedHandoff;
  StreamSubscription<RideRequestListing>? _listingsSubscription;
  StreamSubscription<ReceivedHandoff>? _handoffSubscription;

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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _OfferDialog(
        onSubmit: (priceMnt, etaMinutes, vehicle) async {
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
                ),
                now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              );
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
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
    if (_awardedHandoff != null) {
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
                Text(_awardedHandoff!.payload.plusCode),
                Text(
                  _awardedHandoff!.payload.landmarkText,
                  textAlign: TextAlign.center,
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
  final Future<void> Function(int priceMnt, int etaMinutes, String vehicle)
  onSubmit;
  const _OfferDialog({required this.onSubmit});

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  final _price = TextEditingController();
  final _eta = TextEditingController();
  final _vehicle = TextEditingController();
  bool _submitting = false;

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
      await widget.onSubmit(price, eta, _vehicle.text);
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
        ],
      ),
      actions: [
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
