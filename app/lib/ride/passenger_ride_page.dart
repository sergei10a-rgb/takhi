// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../map/location_picker.dart';
import '../theme/takhi_theme.dart';
import '../widgets/primary_button.dart';
import 'offer_ranking.dart';
import 'offer_service.dart';
import 'ride_providers.dart';

/// Ulaanbaatar's Sukhbaatar Square -- the map's starting center until a
/// city-config seam exists (spec §11; see `RideMap`'s doc comment, Task 8).
///
/// Kept as separate `double` consts (rather than reading
/// `_defaultCityCenter.latitude`/`.longitude` below) because `LatLng`'s
/// fields, while `final`, aren't const-evaluable through instance-field
/// access on this SDK -- the plan's original single-const version fails to
/// compile (see Task 9 deviations).
const _defaultLat = 47.9186;
const _defaultLon = 106.9176;
const _defaultCityCenter = ll.LatLng(_defaultLat, _defaultLon);

enum _PassengerStep { pickup, destination, price, offers, done }

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
  PickedLocation _pickup = const PickedLocation(
    lat: _defaultLat,
    lon: _defaultLon,
  );
  PickedLocation _destination = const PickedLocation(
    lat: _defaultLat,
    lon: _defaultLon,
  );
  final _priceController = TextEditingController();
  String? _rideRequestId;
  final List<RideOffer> _offers = [];
  final Map<String, List<TripReceipt>> _receiptsCache = {};
  RankedRideOffer? _selected;

  @override
  void dispose() {
    _priceController.dispose();
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
    ref
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

  Future<void> _select(RankedRideOffer ranked) async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    if (identity == null || _rideRequestId == null) return;
    await ref
        .read(handoffServiceProvider)
        .sendHandoff(
          passengerPrivHex: identity.privHex,
          driverPubHex: ranked.offer.driverPubkey,
          rideRequestId: _rideRequestId!,
          lat: _pickup.lat,
          lon: _pickup.lon,
          landmarkText: _pickup.landmarkText,
          now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
    if (!mounted) return;
    setState(() {
      _selected = ranked;
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l.appName)),
      body: SafeArea(
        child: switch (_step) {
          _PassengerStep.pickup => _LocationStep(
            initialCenter: _defaultCityCenter,
            onChanged: (p) => _pickup = p,
            onNext: () => setState(() => _step = _PassengerStep.destination),
          ),
          _PassengerStep.destination => _LocationStep(
            initialCenter: _defaultCityCenter,
            onChanged: (p) => _destination = p,
            onNext: () => setState(() => _step = _PassengerStep.price),
          ),
          _PassengerStep.price => _PriceStep(
            controller: _priceController,
            onPublish: _publish,
          ),
          _PassengerStep.offers => _OffersStep(
            offers: _offers,
            receiptsFor: (pk) => _receiptsCache[pk] ?? const [],
            onSelect: _select,
          ),
          _PassengerStep.done => _DoneStep(selected: _selected),
        },
      ),
    );
  }
}

class _LocationStep extends StatelessWidget {
  final ll.LatLng initialCenter;
  final ValueChanged<PickedLocation> onChanged;
  final VoidCallback onNext;

  const _LocationStep({
    required this.initialCenter,
    required this.onChanged,
    required this.onNext,
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
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l.nextStep, onPressed: onNext),
        ],
      ),
    );
  }
}

class _PriceStep extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onPublish;
  const _PriceStep({required this.controller, required this.onPublish});

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
        ],
      ),
    );
  }
}

class _OffersStep extends StatelessWidget {
  final List<RideOffer> offers;
  final List<TripReceipt> Function(String driverPubkey) receiptsFor;
  final ValueChanged<RankedRideOffer> onSelect;
  const _OffersStep({
    required this.offers,
    required this.receiptsFor,
    required this.onSelect,
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
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  final RankedRideOffer? selected;
  const _DoneStep({required this.selected});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final vehicle = selected?.offer.payload.vehicleDescription;
    return Center(
      child: Text(
        vehicle == null ? '' : l.driverOnTheWay(vehicle),
        style: const TextStyle(color: TakhiColors.gold, fontSize: 18),
      ),
    );
  }
}
