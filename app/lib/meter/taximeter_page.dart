// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:qr_flutter/qr_flutter.dart';

import '../geo/geo_providers.dart';
import '../geo/gps_fix.dart';
import '../l10n/app_localizations.dart';
import '../map/location_picker.dart';
import '../map/ride_map.dart';
import '../payment/driver_qr_display.dart';
import '../theme/takhi_theme.dart';
import '../widgets/location_permission_denied_view.dart';
import '../widgets/primary_button.dart';
import 'fare_estimate.dart';
import 'meter_journal.dart';
import 'meter_providers.dart';
import 'meter_session.dart';
import 'onboarding_qr_config.dart';

/// Ulaanbaatar's Sukhbaatar Square -- the same map-center fallback every
/// other ride/meter screen uses until a real city-config seam exists (spec
/// §11; see `RideMap`'s doc comment).
const _defaultCenter = ll.LatLng(47.9186, 106.9176);

/// The elapsed-time display (spec §7.4 step 3) must keep advancing between
/// GPS fixes, not just when one arrives -- this periodic rebuild is the
/// simplest way to achieve that without a second stream.
const _fareTickInterval = Duration(seconds: 2);

enum _MeterStep { needsTariff, idle, running, finished }

/// Fully offline, driver-only "Замын Унаа" taximeter (spec §7.4): this file
/// and everything it imports from `meter/` never touches `RelayPool`,
/// `RideDmChannel`, or `identity/` -- a meter run never mints a Nostr event
/// and never needs the rider to have the app at all (Global Constraints).
class TaximeterPage extends ConsumerStatefulWidget {
  const TaximeterPage({super.key});

  @override
  ConsumerState<TaximeterPage> createState() => _TaximeterPageState();
}

class _TaximeterPageState extends ConsumerState<TaximeterPage> {
  _MeterStep _step = _MeterStep.needsTariff;
  int? _tariff;
  final _tariffController = TextEditingController();

  FareEstimate? _estimate;

  MeterSession? _session;
  DateTime? _startedAt;
  MeterTripEntry? _lastEntry;

  // Set whenever `locationPermissionCheckProvider` comes back false from
  // either `_start` or `_onDestinationChanged` -- both need a GPS fix, so
  // one flag covers the idle step regardless of which action triggered the
  // denial. Mirrors `ActiveTripView._locationPermissionDenied`'s reasoning.
  bool _locationPermissionDenied = false;

  StreamSubscription<GpsFix>? _gpsSubscription;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTariff());
  }

  Future<void> _loadTariff() async {
    final saved = await ref.read(tariffStoreProvider).loadMntPerKm();
    if (!mounted) return;
    setState(() {
      _tariff = saved;
      _step = saved == null ? _MeterStep.needsTariff : _MeterStep.idle;
    });
  }

  Future<void> _saveTariff() async {
    final value = int.tryParse(_tariffController.text);
    if (value == null) return;
    await ref.read(tariffStoreProvider).saveMntPerKm(value);
    if (!mounted) return;
    setState(() {
      _tariff = value;
      _step = _MeterStep.idle;
    });
  }

  Future<void> _onDestinationChanged(PickedLocation destination) async {
    final tariff = _tariff;
    if (tariff == null) return;
    final granted = await ref.read(locationPermissionCheckProvider)();
    if (!mounted) return;
    if (!granted) {
      setState(() => _locationPermissionDenied = true);
      return;
    }
    setState(() => _locationPermissionDenied = false);
    final fix = await ref.read(locationSourceProvider).watch().first;
    if (!mounted) return;
    final estimate = await estimateTripFare(
      routingClient: ref.read(routingClientProvider),
      mntPerKm: tariff,
      fromLat: fix.lat,
      fromLon: fix.lon,
      toLat: destination.lat,
      toLon: destination.lon,
    );
    if (!mounted) return;
    setState(() => _estimate = estimate);
  }

  Future<void> _start() async {
    final tariff = _tariff;
    if (tariff == null) return;
    final granted = await ref.read(locationPermissionCheckProvider)();
    if (!mounted) return;
    if (!granted) {
      setState(() => _locationPermissionDenied = true);
      return;
    }
    setState(() => _locationPermissionDenied = false);

    final session = MeterSession(mntPerKm: tariff);
    _gpsSubscription = ref.read(locationSourceProvider).watch().listen((fix) {
      session.addFix(fix);
      if (mounted) setState(() {});
    });
    _tickTimer = Timer.periodic(_fareTickInterval, (_) {
      if (mounted) setState(() {});
    });

    setState(() {
      _session = session;
      _startedAt = DateTime.now();
      _step = _MeterStep.running;
    });
  }

  Future<void> _finish() async {
    final session = _session;
    final startedAt = _startedAt;
    if (session == null || startedAt == null) return;

    // Without cancelling these, the GPS stream subscription and the tick
    // timer both keep firing after the run is over -- mirrors
    // `ActiveTripView._stopTrackingAndMoveToRating`'s own cleanup reasoning.
    unawaited(_gpsSubscription?.cancel());
    _gpsSubscription = null;
    _tickTimer?.cancel();
    _tickTimer = null;

    final entry = MeterTripEntry(
      startedAt: startedAt.millisecondsSinceEpoch ~/ 1000,
      endedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      distanceMeters: session.distanceMeters,
      fareMnt: session.fareMnt,
    );
    await ref.read(meterJournalStoreProvider).append(entry);
    if (!mounted) return;
    setState(() {
      _lastEntry = entry;
      _step = _MeterStep.finished;
    });
  }

  Future<void> _retryLocationPermission() async {
    final granted = await ref.read(locationPermissionCheckProvider)();
    if (!mounted) return;
    setState(() => _locationPermissionDenied = !granted);
  }

  void _resetToIdle() {
    setState(() {
      _session = null;
      _startedAt = null;
      _lastEntry = null;
      _estimate = null;
      _step = _MeterStep.idle;
    });
  }

  @override
  void dispose() {
    _tariffController.dispose();
    unawaited(_gpsSubscription?.cancel());
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l.taximeterTitle)),
      body: SafeArea(
        child: switch (_step) {
          _MeterStep.needsTariff => _TariffStep(
            controller: _tariffController,
            onSave: _saveTariff,
          ),
          _MeterStep.idle =>
            _locationPermissionDenied
                ? LocationPermissionDeniedView(
                    onRetry: _retryLocationPermission,
                  )
                : _IdleStep(
                    estimate: _estimate,
                    onDestinationChanged: _onDestinationChanged,
                    onStart: _start,
                  ),
          _MeterStep.running => _RunningStep(
            session: _session!,
            onFinish: _finish,
          ),
          _MeterStep.finished => _FinishedStep(
            entry: _lastEntry!,
            onReset: _resetToIdle,
          ),
        },
      ),
    );
  }
}

class _TariffStep extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSave;
  const _TariffStep({required this.controller, required this.onSave});

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
              labelText: l.meterTariffFieldLabel,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l.saveTariffAction, onPressed: onSave),
        ],
      ),
    );
  }
}

class _IdleStep extends StatelessWidget {
  final FareEstimate? estimate;
  final ValueChanged<PickedLocation> onDestinationChanged;
  final VoidCallback onStart;

  const _IdleStep({
    required this.estimate,
    required this.onDestinationChanged,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final currentEstimate = estimate;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          PrimaryButton(label: l.startMeterAction, onPressed: onStart),
          const SizedBox(height: 24),
          Text(l.meterDestinationOptionalHint),
          const SizedBox(height: 8),
          LocationPickerField(
            initialCenter: _defaultCenter,
            onChanged: onDestinationChanged,
          ),
          if (currentEstimate != null) ...[
            const SizedBox(height: 16),
            Text(
              l.estimatedFareLabel(currentEstimate.mnt),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: TakhiColors.gold,
              ),
            ),
            if (currentEstimate.isApproximate) Text(l.estimatedFareApproxLabel),
          ],
        ],
      ),
    );
  }
}

class _RunningStep extends StatelessWidget {
  final MeterSession session;
  final VoidCallback onFinish;

  const _RunningStep({required this.session, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final points = session.fixes
        .map((fix) => ll.LatLng(fix.lat, fix.lon))
        .toList();
    final center = points.isEmpty ? _defaultCenter : points.last;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            l.meterFareLabel(session.fareMnt),
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: TakhiColors.gold,
            ),
          ),
        ),
        Text(l.meterRunningDistanceLabel(session.distanceMeters / 1000)),
        Text(l.meterRunningDurationLabel(session.durationSeconds ~/ 60)),
        const SizedBox(height: 12),
        Expanded(
          child: RideMap(
            initialCenter: center,
            layers: [
              if (points.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      color: TakhiColors.gold,
                      strokeWidth: 4,
                    ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(label: l.finishMeterAction, onPressed: onFinish),
        ),
      ],
    );
  }
}

class _FinishedStep extends StatelessWidget {
  final MeterTripEntry entry;
  final VoidCallback onReset;

  const _FinishedStep({required this.entry, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final durationMinutes = (entry.endedAt - entry.startedAt) ~/ 60;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            l.meterSummaryTitle,
            style: const TextStyle(
              color: TakhiColors.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l.meterFareLabel(entry.fareMnt),
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: TakhiColors.gold,
            ),
          ),
          Text(l.meterRunningDistanceLabel(entry.distanceMeters / 1000)),
          Text(l.meterRunningDurationLabel(durationMinutes)),
          const SizedBox(height: 24),
          // Always shown here -- this screen is driver-only by construction
          // (Global Constraints), so there is no passenger-side branch to
          // consider, unlike `ActiveTripView._DoneView`.
          const DriverQrDisplay(),
          const SizedBox(height: 24),
          QrImageView(data: kTakhiAppDownloadUrl, size: 96),
          const SizedBox(height: 8),
          Text(l.downloadTakhiQrLabel),
          const SizedBox(height: 24),
          PrimaryButton(label: l.startMeterAction, onPressed: onReset),
        ],
      ),
    );
  }
}
