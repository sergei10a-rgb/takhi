// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:qr_flutter/qr_flutter.dart';

import '../config/city_config.dart';
import '../geo/geo_providers.dart';
import '../geo/gps_fix.dart';
import '../l10n/app_localizations.dart';
import '../map/location_picker.dart';
import '../map/ride_map.dart';
import '../payment/driver_qr_display.dart';
import '../theme/takhi_theme.dart';
import '../widgets/confirm_leave_scope.dart';
import '../widgets/location_permission_denied_view.dart';
import '../widgets/primary_button.dart';
import 'fare_estimate.dart';
import 'meter_journal.dart';
import 'meter_providers.dart';
import 'meter_session.dart';
import 'onboarding_qr_config.dart';

/// The elapsed-time display (spec §7.4 step 3) must keep advancing between
/// GPS fixes, not just when one arrives -- this periodic rebuild is the
/// simplest way to achieve that without a second stream.
const _fareTickInterval = Duration(seconds: 2);

/// How long `_onDestinationChanged` waits for the map pan / landmark
/// keystrokes to settle before actually issuing the permission-check + GPS
/// fix + routing request chain -- `LocationPickerField.onChanged` fires on
/// every single pan frame and keystroke, so without this a normal drag
/// gesture would fire that whole chain (including an HTTP call to the
/// public OSRM demo server) ten or more times per second.
const _destinationDebounceDuration = Duration(milliseconds: 600);

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
  // Set when a save attempt could not read a usable number out of the
  // field, cleared by the next successful save -- i.e. validate on
  // submit, the only moment the driver is asking for a verdict.
  bool _tariffInvalid = false;

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

  Timer? _destinationDebounceTimer;
  // Bumped on every settled destination change; a still-in-flight request
  // compares its own captured value against this after each `await` and
  // silently drops its result if it no longer matches -- i.e. a newer
  // destination change already started, so this one is stale. Guards
  // against genuine out-of-order completion (two full chains in flight at
  // once, e.g. one settles while an earlier one is still awaiting the
  // network), which the debounce Timer alone does not prevent.
  int _destinationRequestSeq = 0;

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
    // Spaces stripped rather than rejected: "15 000" is simply how a
    // price gets written by hand, and a number keyboard on some devices
    // offers the separator itself.
    final value = int.tryParse(
      _tariffController.text.replaceAll(RegExp(r'\s'), ''),
    );
    // Returning silently here (as this used to) is indistinguishable from
    // a broken button: the screen did not move and nothing said why, so a
    // driver could only guess whether the app or their typing was at
    // fault. A zero tariff is rejected for the same reason a missing one
    // is -- it would meter every trip at 0₮.
    if (value == null || value <= 0) {
      setState(() => _tariffInvalid = true);
      return;
    }
    await ref.read(tariffStoreProvider).saveMntPerKm(value);
    if (!mounted) return;
    setState(() {
      _tariff = value;
      _tariffInvalid = false;
      _step = _MeterStep.idle;
    });
  }

  /// Reopens the tariff step over an already-saved rate. Without this the
  /// first number a driver ever typed was permanent -- `TariffStore`
  /// keeps it forever and nothing else in the app writes that key -- so a
  /// mistyped 1500 instead of 15000 meant undercharging every single trip
  /// until the app was reinstalled.
  void _editTariff() {
    final tariff = _tariff;
    if (tariff == null) return;
    setState(() {
      _tariffController.text = '$tariff';
      _tariffInvalid = false;
      _step = _MeterStep.needsTariff;
    });
  }

  /// Whether the tariff step is an *edit* of an existing rate rather than
  /// the very first entry -- only then is there an idle step behind it to
  /// cancel back to, and only then may a back press mean "abandon the
  /// edit" instead of "leave the meter".
  bool get _canCancelTariffEdit =>
      _step == _MeterStep.needsTariff && _tariff != null;

  void _cancelTariffEdit() {
    setState(() {
      _tariffInvalid = false;
      _step = _MeterStep.idle;
    });
  }

  void _onDestinationChanged(PickedLocation destination) {
    _destinationDebounceTimer?.cancel();
    // Clears any estimate left over from the previous pin position right
    // away, rather than leaving it on screen for the whole debounce +
    // permission + GPS + routing round trip -- otherwise a stale number
    // would keep reading as if it belonged to wherever the pin/text just
    // moved to.
    if (_estimate != null) setState(() => _estimate = null);
    _destinationDebounceTimer = Timer(_destinationDebounceDuration, () {
      unawaited(_estimateDestinationFare(destination));
    });
  }

  /// Runs the permission-check + GPS-fix + routing-request chain for one
  /// settled [destination] -- only ever invoked after
  /// [_destinationDebounceDuration] has passed with no further pan/keystroke
  /// (`_onDestinationChanged`), so a single drag gesture or a burst of
  /// typing produces at most one of these instead of one per intermediate
  /// value. [_destinationRequestSeq] additionally survives the case where
  /// two of these chains are genuinely in flight at once (a newer one
  /// started before an older one finished) by dropping whichever result
  /// arrives once it is no longer the latest requested, so a slow stale
  /// response can never clobber a newer, already-displayed estimate.
  Future<void> _estimateDestinationFare(PickedLocation destination) async {
    final tariff = _tariff;
    if (tariff == null) return;
    final requestSeq = ++_destinationRequestSeq;
    final granted = await ref.read(locationPermissionCheckProvider)();
    if (!mounted || requestSeq != _destinationRequestSeq) return;
    if (!granted) {
      setState(() => _locationPermissionDenied = true);
      return;
    }
    setState(() => _locationPermissionDenied = false);
    final fix = await ref.read(locationSourceProvider).watch().first;
    if (!mounted || requestSeq != _destinationRequestSeq) return;
    final estimate = await estimateTripFare(
      routingClient: ref.read(routingClientProvider),
      mntPerKm: tariff,
      fromLat: fix.lat,
      fromLon: fix.lon,
      toLat: destination.lat,
      toLon: destination.lon,
    );
    if (!mounted || requestSeq != _destinationRequestSeq) return;
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

  /// Tears down a run the driver chose to abandon from the leave
  /// confirmation. Deliberately writes *no* journal entry: the dialog
  /// (`leaveMeterMessage`) states this run is discarded and points at
  /// "Дуусгах" as the way to record one, so silently banking a half-run
  /// would both contradict what the driver was just told and put fares
  /// nobody was ever charged into the day's takings.
  void _discardRun() {
    // Plain field writes, no `setState`: this runs from
    // `ConfirmLeaveScope.onConfirmedLeave`, one step before the route
    // pops and this state is disposed, so rebuilding the running step's
    // map on the way out would be wasted work. Cancelling here rather
    // than leaving it all to `dispose` keeps the teardown at the moment
    // the decision is made, next to the reason for it.
    unawaited(_gpsSubscription?.cancel());
    _gpsSubscription = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _session = null;
    _startedAt = null;
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
    _destinationDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final page = Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l.taximeterTitle)),
      body: SafeArea(child: _buildStep(l)),
    );

    // Exactly one pop guard is ever mounted, never both. A route asks
    // *every* `PopScope` registered under it, and hands the same
    // `didPop: false` to all of their callbacks -- so a second guard
    // blocking a pop would make `ConfirmLeaveScope` read it as "the
    // driver is trying to leave" and raise the stop-the-meter dialog on
    // a step with nothing running. Swapping the wrapper instead of
    // nesting keeps that impossible; the two conditions are mutually
    // exclusive (`_canCancelTariffEdit` implies the tariff step).
    if (_canCancelTariffEdit) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _cancelTariffEdit();
        },
        child: page,
      );
    }
    return ConfirmLeaveScope(
      // Only a running meter has anything to lose: the fare, distance and
      // duration exist solely in `_session` until `_finish` writes them
      // to the journal. Every other step is either pre-run or already
      // recorded, so back leaves unchallenged.
      enabled: _step == _MeterStep.running,
      title: l.leaveMeterTitle,
      message: l.leaveMeterMessage,
      onConfirmedLeave: _discardRun,
      child: page,
    );
  }

  Widget _buildStep(AppLocalizations l) => switch (_step) {
    _MeterStep.needsTariff => _TariffStep(
      controller: _tariffController,
      errorText: _tariffInvalid ? l.meterTariffInvalidHint : null,
      onSave: _saveTariff,
      onCancel: _canCancelTariffEdit ? _cancelTariffEdit : null,
    ),
    _MeterStep.idle => _buildIdleStep(),
    _MeterStep.running => _RunningStep(session: _session!, onFinish: _finish),
    _MeterStep.finished => _FinishedStep(
      entry: _lastEntry!,
      onReset: _resetToIdle,
    ),
  };

  Widget _buildIdleStep() {
    if (_locationPermissionDenied) {
      return LocationPermissionDeniedView(onRetry: _retryLocationPermission);
    }
    final tariff = _tariff;
    // Unreachable in practice -- every transition into `idle` sets a
    // tariff first -- but written as a guard rather than a `!` so a
    // future step transition can only lose a screen, never crash a
    // driver mid-shift.
    if (tariff == null) return const SizedBox.shrink();
    return _IdleStep(
      tariffMntPerKm: tariff,
      estimate: _estimate,
      onDestinationChanged: _onDestinationChanged,
      onStart: _start,
      onEditTariff: _editTariff,
    );
  }
}

class _TariffStep extends StatelessWidget {
  final TextEditingController controller;

  /// Why the last save attempt was refused, or `null` while nothing is
  /// wrong.
  final String? errorText;
  final VoidCallback onSave;

  /// `null` on the very first run: until a tariff has been saved once
  /// there is no idle step to cancel back to.
  final VoidCallback? onCancel;

  const _TariffStep({
    required this.controller,
    required this.errorText,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cancel = onCancel;
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
              errorText: errorText,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l.saveTariffAction, onPressed: onSave),
          if (cancel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: cancel, child: Text(l.cancelAction)),
          ],
        ],
      ),
    );
  }
}

class _IdleStep extends StatelessWidget {
  final int tariffMntPerKm;
  final FareEstimate? estimate;
  final ValueChanged<PickedLocation> onDestinationChanged;
  final VoidCallback onStart;
  final VoidCallback onEditTariff;

  const _IdleStep({
    required this.tariffMntPerKm,
    required this.estimate,
    required this.onDestinationChanged,
    required this.onStart,
    required this.onEditTariff,
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
          const SizedBox(height: 8),
          // Spells out the rate rather than hiding it behind a settings
          // icon: a driver only notices they typed 1500 for 15000 if the
          // number is in front of them before the trip starts.
          TextButton.icon(
            onPressed: onEditTariff,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l.meterEditTariffAction(tariffMntPerKm)),
          ),
          const SizedBox(height: 16),
          Text(l.meterDestinationOptionalHint),
          const SizedBox(height: 8),
          LocationPickerField(
            initialCenter: ll.LatLng(
              defaultCityConfig.centerLat,
              defaultCityConfig.centerLon,
            ),
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
    final center = points.isEmpty
        ? ll.LatLng(defaultCityConfig.centerLat, defaultCityConfig.centerLon)
        : points.last;
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
