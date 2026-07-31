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
import '../map/device_location_layer.dart';
import '../map/location_picker.dart';
import '../map/map_camera_fit.dart';
import '../map/ride_map.dart';
import '../payment/driver_qr_display.dart';
import '../theme/takhi_theme.dart';
import '../widgets/confirm_leave_scope.dart';
import '../widgets/dialog_action_bar.dart';
import '../widgets/info_chip.dart';
import '../widgets/location_permission_denied_view.dart';
import '../widgets/pill_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/qr_card.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'fare_estimate.dart';
import 'meter_journal.dart';
import 'meter_providers.dart';
import 'meter_session.dart';
import 'money_format.dart';
import 'onboarding_qr_config.dart';
import 'tariff_store.dart';

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

/// Ceiling on the destination picker sheet, as a fraction of the screen --
/// the map inside it needs room, but the sheet must still read as something
/// covering the meter rather than as a new screen.
const _kPickerHeightFactor = 0.8;

/// Glyph beside a secondary figure on the running step.
const _kStatGlyphSize = 18.0;

/// Width of the driven-route line on the running step's map.
///
/// Map geometry rather than layout spacing, so it is a named constant here and
/// not a [TakhiSpace] token: it is measured against the map tiles under it, and
/// would look wrong at whatever the spacing scale happened to say.
const _kRouteStrokeWidth = 4.0;

/// Left/right/top margin kept clear of the driven route when the running
/// step's camera is fitted to it.
const _kRouteFitEdgeInset = 48.0;

/// Bottom margin for the same fit. Far larger than the others, and not a
/// spacing token, because it is not spacing: the running sheet is anchored
/// over the bottom of the map, so this is roughly how much of the map that
/// sheet hides. Fitting without it would centre the route in the map's
/// *rectangle* and drop the newest half of it behind the fare.
const _kRouteFitSheetInset = 300.0;

/// The two above, as the padding `CameraFit` takes.
const _kRouteFitPadding = EdgeInsets.fromLTRB(
  _kRouteFitEdgeInset,
  _kRouteFitEdgeInset,
  _kRouteFitEdgeInset,
  _kRouteFitSheetInset,
);

/// Glyph inside the "this is what I charge" pill.
const _kTariffGlyphSize = 16.0;

/// Side of the "download Takhi" code. Small on purpose: it is an invitation,
/// not the thing the passenger came to this screen to scan.
const _kDownloadQrSize = 96.0;

/// Metres as the kilometre figure a driver actually reads.
///
/// Display only -- the fare is computed from the full-precision metre count
/// in `fare_calc.dart` and never from this, which is exactly what makes the
/// rounding safe. Without it the secondary line reads "0.11123479 км": a
/// number that is technically the truth and practically unreadable at a
/// junction, on the one screen in this app that is looked at while driving.
double _displayKm(int meters) =>
    double.parse((meters / 1000).toStringAsFixed(1));

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

  /// The driver's waiting rate (₮/минут, spec §7.4). Zero — the value every
  /// tariff saved before waiting fares existed migrates to — means waiting
  /// is free and the running meter behaves exactly as it always did.
  int _waitTariff = 0;

  final _tariffController = TextEditingController();
  final _waitTariffController = TextEditingController();
  // Set when a save attempt could not read a usable number out of the
  // field, cleared by the next successful save -- i.e. validate on
  // submit, the only moment the driver is asking for a verdict.
  bool _tariffInvalid = false;
  bool _waitTariffInvalid = false;

  FareEstimate? _estimate;

  /// The last settled destination, kept purely so the idle step's pill can
  /// say which place the estimate belongs to. Written when the debounce
  /// settles rather than on every pan frame, so dragging the picker map does
  /// not rebuild the page behind it sixty times a second.
  PickedLocation? _destination;

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
    final saved = await ref.read(tariffStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _tariff = saved?.mntPerKm;
      _waitTariff = saved?.mntPerMinute ?? 0;
      _step = saved == null ? _MeterStep.needsTariff : _MeterStep.idle;
    });
  }

  /// A price as the driver typed it, or `null` if it is not a whole
  /// non-negative number.
  ///
  /// Spaces are stripped rather than rejected: "15 000" is simply how a
  /// price gets written by hand, and a number keyboard on some devices
  /// offers the separator itself.
  static int? _parsePrice(String text) {
    final value = int.tryParse(text.replaceAll(RegExp(r'\s'), ''));
    return value == null || value < 0 ? null : value;
  }

  Future<void> _saveTariff() async {
    final kmValue = _parsePrice(_tariffController.text);
    final waitText = _waitTariffController.text.trim();
    // An empty waiting field means "waiting is free", not "you forgot
    // something": a driver who does not charge for time stopped has
    // nothing to type there, and demanding a 0 out of them would be an
    // error message for a correct answer.
    final waitValue = waitText.isEmpty ? 0 : _parsePrice(waitText);

    // A zero km-tariff is rejected for the same reason a missing one is --
    // it would meter every trip at 0₮. A zero waiting tariff is a real
    // choice and passes.
    final kmInvalid = kmValue == null || kmValue <= 0;
    final waitInvalid = waitValue == null;
    // Returning silently here (as this used to) is indistinguishable from
    // a broken button: the screen did not move and nothing said why, so a
    // driver could only guess whether the app or their typing was at
    // fault. Both verdicts are set in one pass so a driver with two
    // mistakes is not sent back a second time for the second one.
    if (kmInvalid || waitInvalid) {
      setState(() {
        _tariffInvalid = kmInvalid;
        _waitTariffInvalid = waitInvalid;
      });
      return;
    }

    await ref
        .read(tariffStoreProvider)
        .save(DriverTariff(mntPerKm: kmValue, mntPerMinute: waitValue));
    if (!mounted) return;
    setState(() {
      _tariff = kmValue;
      _waitTariff = waitValue;
      _tariffInvalid = false;
      _waitTariffInvalid = false;
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
      // A free wait reopens as an empty field rather than as a 0: that is
      // what the driver left there, and an unasked-for zero in a price box
      // reads as a rate somebody set deliberately.
      _waitTariffController.text = _waitTariff == 0 ? '' : '$_waitTariff';
      _tariffInvalid = false;
      _waitTariffInvalid = false;
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
      _waitTariffInvalid = false;
      _step = _MeterStep.idle;
    });
  }

  /// What the destination pill says once something has been picked: the
  /// landmark the driver typed if there is one, otherwise the Plus Code of
  /// the pin. Never a raw lat/lon pair -- nobody reads those out loud.
  String? get _destinationLabel {
    final destination = _destination;
    if (destination == null) return null;
    final landmark = destination.landmarkText.trim();
    return landmark.isEmpty ? destination.plusCode : landmark;
  }

  /// Opens the map picker over the idle step.
  ///
  /// The picker used to sit permanently on the idle step, which meant the
  /// one screen a driver looks at while waiting for a passenger was mostly
  /// a map they were not using, with the start button pushed below it. It
  /// is a detour now: the pill states where the trip is going, and the map
  /// only appears when the driver asks for it.
  Future<void> _openDestinationPicker() async {
    final l = AppLocalizations.of(context)!;
    final start = _destination;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // `TakhiSheet` paints its own rounded surface, edge and shadow;
      // Material's default background would draw a second sheet behind it.
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        // Lifts the sheet clear of the keyboard the landmark field raises.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: TakhiSheet(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(sheetContext).height * _kPickerHeightFactor,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeading(
                    compact: true,
                    title: l.meterDestinationOptionalHint,
                  ),
                  const SizedBox(height: TakhiSpace.md),
                  LocationPickerField(
                    initialCenter: start == null
                        ? ll.LatLng(
                            defaultCityConfig.centerLat,
                            defaultCityConfig.centerLon,
                          )
                        : ll.LatLng(start.lat, start.lon),
                    initialLandmarkText: start?.landmarkText ?? '',
                    onChanged: _onDestinationChanged,
                  ),
                  const SizedBox(height: TakhiSpace.md),
                  PrimaryButton(
                    label: l.meterDestinationDoneAction,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
      if (mounted) setState(() => _destination = destination);
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

    final session = MeterSession(
      mntPerKm: tariff,
      waitTariffMntPerMinute: _waitTariff,
    );
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
      waitingFareMnt: session.waitingFareMnt,
      waitingSeconds: session.waitingSeconds,
      pausedSeconds: session.pausedSeconds,
    );
    await ref.read(meterJournalStoreProvider).append(entry);
    if (!mounted) return;
    setState(() {
      _lastEntry = entry;
      _step = _MeterStep.finished;
    });
  }

  /// Takes the running meter off the clock, or puts it back on.
  ///
  /// Pausing asks first. This screen is held (or propped) in a moving car,
  /// and the control sits a thumb's width from the map the driver pans, so
  /// an unguarded tap would silently stop the fare and be noticed only at
  /// the end of the trip, when the number is too small and there is no way
  /// to reconstruct what was lost.
  ///
  /// Resuming does not ask. It restores a state the driver already chose
  /// once, and every second spent confirming it is a second the meter is
  /// still off -- the error the dialog would be guarding against is the
  /// cheap one, in the direction that costs the driver rather than the
  /// passenger.
  Future<void> _togglePause() async {
    final session = _session;
    if (session == null) return;
    if (session.isPaused) {
      setState(session.resume);
      return;
    }
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.pauseMeterConfirmTitle),
        content: Text(l.pauseMeterConfirmMessage),
        actions: [
          // Emphasis on pausing, unlike the back-guard dialog: this one was
          // sought out by a deliberate tap, so the loud button is the step
          // the driver came here to take.
          DialogActionBar(
            dismiss: DialogAction(
              label: l.cancelAction,
              tone: DialogActionTone.neutral,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            proceed: DialogAction(
              label: l.pauseMeterAction,
              tone: DialogActionTone.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(session.pause);
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
    _waitTariffController.dispose();
    unawaited(_gpsSubscription?.cancel());
    _tickTimer?.cancel();
    _destinationDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final page = Scaffold(
      backgroundColor: surfaces.canvas,
      appBar: AppBar(
        backgroundColor: surfaces.canvas,
        // Flat in both senses: no tint, and no colour change when content
        // scrolls under it. The steps supply their own planes -- a second,
        // automatic one at the top would compete with the sheet.
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l.taximeterTitle,
          style: TakhiType.title.copyWith(color: surfaces.onSheet),
        ),
      ),
      body: SafeArea(
        // Not the bottom: every step ends in a `TakhiSheet`, which adds the
        // gesture inset itself. Consuming it here as well would pad it twice.
        bottom: false,
        child: AnimatedSwitcher(
          duration: TakhiMotion.normal,
          switchInCurve: TakhiMotion.enter,
          switchOutCurve: TakhiMotion.exit,
          // Steps differ by runtime type, so the switcher animates on a step
          // change and -- critically -- does *not* animate on the two-second
          // fare tick, which rebuilds the running step as the same type. A
          // live fare that cross-fades on every update is a fare nobody can
          // read at a junction.
          child: _buildStep(l),
        ),
      ),
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
      waitController: _waitTariffController,
      errorText: _tariffInvalid ? l.meterTariffInvalidHint : null,
      waitErrorText: _waitTariffInvalid ? l.meterWaitTariffInvalidHint : null,
      onSave: _saveTariff,
      onCancel: _canCancelTariffEdit ? _cancelTariffEdit : null,
    ),
    _MeterStep.idle => _buildIdleStep(),
    _MeterStep.running => _RunningStep(
      session: _session!,
      onFinish: _finish,
      onTogglePause: _togglePause,
    ),
    _MeterStep.finished => _FinishedStep(
      entry: _lastEntry!,
      tariffMntPerKm: _tariff,
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
      waitTariffMntPerMinute: _waitTariff,
      estimate: _estimate,
      destinationLabel: _destinationLabel,
      onPickDestination: _openDestinationPicker,
      onStart: _start,
      onEditTariff: _editTariff,
    );
  }
}

/// The scrolling half of a step, above the sheet that carries its action.
///
/// Every step here has the same two-part shape -- something to read, and one
/// button to press -- and the button is anchored so it never scrolls out of
/// reach, which on this screen is the difference between finishing a run and
/// hunting for a control while pulling over.
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

class _TariffStep extends StatelessWidget {
  final TextEditingController controller;

  /// The ₮/минут charged while the vehicle is stopped. Kept on the same
  /// step as the km rate rather than behind a settings screen: the two
  /// numbers are one decision -- what this driver charges -- and a waiting
  /// rate nobody ever found is a waiting rate nobody ever earns.
  final TextEditingController waitController;

  /// Why the last save attempt was refused, or `null` while nothing is
  /// wrong.
  final String? errorText;
  final String? waitErrorText;
  final VoidCallback onSave;

  /// `null` on the very first run: until a tariff has been saved once
  /// there is no idle step to cancel back to.
  final VoidCallback? onCancel;

  const _TariffStep({
    required this.controller,
    required this.waitController,
    required this.errorText,
    required this.waitErrorText,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final cancel = onCancel;

    return Column(
      children: [
        Expanded(
          child: _StepBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(
                  title: l.meterTariffTitle,
                  subtitle: l.meterTariffSubtitle,
                ),
                const SizedBox(height: TakhiSpace.xl),
                _TariffField(
                  label: l.meterTariffFieldLabel,
                  icon: Icons.payments_outlined,
                  controller: controller,
                  errorText: errorText,
                ),
                const SizedBox(height: TakhiSpace.lg),
                _TariffField(
                  label: l.meterWaitTariffFieldLabel,
                  icon: Icons.hourglass_bottom_outlined,
                  controller: waitController,
                  errorText: waitErrorText,
                  // Spelled out under the field, not left to the label: a
                  // driver meeting a "waiting rate" for the first time has
                  // to be told what it charges for before they can price
                  // it, and "0 means free" is what stops them typing a
                  // number they did not want just to get past the screen.
                  hint: l.meterWaitTariffHint,
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
              PrimaryButton(label: l.saveTariffAction, onPressed: onSave),
              if (cancel != null) ...[
                const SizedBox(height: TakhiSpace.xs),
                _SecondaryAction(
                  label: l.cancelAction,
                  onPressed: cancel,
                  foreground: surfaces.muted,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One priced field on the tariff step: a standing label, the capsule, an
/// optional explanation and an optional verdict.
///
/// The label stands above the field rather than floating inside Material's
/// border, which slides out of the way the moment the field has a value --
/// exactly when a driver wants to check whether the 15000 they are looking
/// at is the per-kilometre rate or the per-minute one.
class _TariffField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;

  /// The quiet line under the field explaining what the rate buys. `null`
  /// where the label already says everything.
  final String? hint;

  /// Why the last save attempt refused this field, or `null`.
  final String? errorText;

  const _TariffField({
    required this.label,
    required this.icon,
    required this.controller,
    this.hint,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final scheme = Theme.of(context).colorScheme;
    final explanation = hint;
    final error = errorText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TakhiType.micro.copyWith(color: surfaces.muted)),
        const SizedBox(height: TakhiSpace.xs),
        PillField(
          icon: icon,
          controller: controller,
          keyboardType: TextInputType.number,
        ),
        // The verdict sits directly under the capsule it judges, *above*
        // the standing explanation. Ordering them the other way round put
        // the km field's error immediately under its box and the waiting
        // field's an explanation-line lower, so on the one screen where
        // both can be refused at once the two refusals appeared at two
        // different distances from the boxes they belonged to.
        if (error != null) ...[
          const SizedBox(height: TakhiSpace.xs),
          Text(error, style: TakhiType.support.copyWith(color: scheme.error)),
        ],
        if (explanation != null) ...[
          const SizedBox(height: TakhiSpace.xs),
          Text(
            explanation,
            style: TakhiType.support.copyWith(color: surfaces.muted),
          ),
        ],
      ],
    );
  }
}

/// The quiet full-width action under a [PrimaryButton].
///
/// Shared rather than restyled per step so "the second choice on a sheet"
/// is one shape everywhere -- and so its foreground is never Material's
/// default `colorScheme.primary`, which is brand gold at 2.28:1 on a light
/// sheet.
class _SecondaryAction extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color foreground;

  const _SecondaryAction({
    required this.label,
    required this.onPressed,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: foreground,
      minimumSize: const Size.fromHeight(TakhiTouch.minTarget),
      shape: const RoundedRectangleBorder(borderRadius: TakhiRadius.pillAll),
      textStyle: takhiButtonTextStyle(context, TakhiType.title),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

class _IdleStep extends StatelessWidget {
  final int tariffMntPerKm;

  /// Zero means waiting is free -- stated on its own pill rather than
  /// omitted, so "I charge nothing for waiting" and "I forgot to set it"
  /// do not look the same on the screen the driver checks before starting.
  final int waitTariffMntPerMinute;
  final FareEstimate? estimate;

  /// Where the trip is going, once a destination has settled. `null` while
  /// none has been picked -- the pill shows its placeholder instead.
  final String? destinationLabel;
  final VoidCallback onPickDestination;
  final VoidCallback onStart;
  final VoidCallback onEditTariff;

  const _IdleStep({
    required this.tariffMntPerKm,
    required this.waitTariffMntPerMinute,
    required this.estimate,
    required this.destinationLabel,
    required this.onPickDestination,
    required this.onStart,
    required this.onEditTariff,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final currentEstimate = estimate;

    return Column(
      children: [
        Expanded(
          child: _StepBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(title: l.meterReadyTitle),
                const SizedBox(height: TakhiSpace.md),
                // Spells both rates out rather than hiding them behind a
                // settings icon: a driver only notices they typed 1500 for
                // 15000 if the number is in front of them before the trip
                // starts. Wrapped rather than in a fixed row -- two
                // Cyrillic rate labels do not fit one line on a small
                // phone, and a truncated price is worse than a second row.
                Wrap(
                  spacing: TakhiSpace.xs,
                  runSpacing: TakhiSpace.xs,
                  children: [
                    _TariffPill(
                      label: l.meterEditTariffAction(
                        groupedMnt(tariffMntPerKm),
                      ),
                      onTap: onEditTariff,
                    ),
                    _TariffPill(
                      label: l.meterEditWaitTariffAction(
                        groupedMnt(waitTariffMntPerMinute),
                      ),
                      onTap: onEditTariff,
                    ),
                  ],
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
              Text(
                l.meterDestinationOptionalHint,
                style: TakhiType.micro.copyWith(color: surfaces.muted),
              ),
              const SizedBox(height: TakhiSpace.xs),
              PillField(
                icon: Icons.place_outlined,
                text: destinationLabel,
                placeholder: l.meterDestinationPlaceholder,
                onTap: onPickDestination,
                semanticsLabel: l.meterDestinationPlaceholder,
                trailing: Icon(
                  Icons.chevron_right,
                  size: _kStatGlyphSize,
                  color: surfaces.muted,
                ),
              ),
              if (currentEstimate != null) ...[
                const SizedBox(height: TakhiSpace.sm),
                Wrap(
                  spacing: TakhiSpace.xs,
                  runSpacing: TakhiSpace.xs,
                  children: [
                    InfoChip(
                      icon: Icons.payments_outlined,
                      label: l.estimatedFareLabel(
                        groupedMnt(currentEstimate.mnt),
                      ),
                      accent: TakhiAccent.gold,
                    ),
                    // An offline straight-line guess has to keep saying so:
                    // the outlined variant reads as a caveat next to the
                    // filled number it qualifies.
                    if (currentEstimate.isApproximate)
                      InfoChip(
                        label: l.estimatedFareApproxLabel,
                        tinted: false,
                      ),
                  ],
                ),
              ],
              // Said before the trip rather than explained after it: the
              // number above is distance only (`estimateFareMntOffline`),
              // because how long a trip will sit in a jam is exactly what
              // cannot be known in advance. Dropped when waiting is free --
              // then there is nothing for traffic to add, and the caveat
              // would be a warning about a charge that does not exist.
              if (waitTariffMntPerMinute > 0) ...[
                const SizedBox(height: TakhiSpace.xs),
                Text(
                  l.meterEstimateExcludesWaitingHint,
                  style: TakhiType.support.copyWith(color: surfaces.muted),
                ),
              ],
              const SizedBox(height: TakhiSpace.md),
              PrimaryButton(label: l.startMeterAction, onPressed: onStart),
            ],
          ),
        ),
      ],
    );
  }
}

/// The rate this meter charges, as a pill you press to change it.
class _TariffPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TariffPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return Material(
      color: surfaces.field,
      borderRadius: TakhiRadius.pillAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: TakhiRadius.pillAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TakhiTouch.minTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TakhiSpace.md,
              vertical: TakhiSpace.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: _kTariffGlyphSize,
                  color: surfaces.muted,
                ),
                const SizedBox(width: TakhiSpace.xs),
                Flexible(
                  child: Text(
                    label,
                    style: TakhiType.label.copyWith(color: surfaces.onSheet),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which of the three things the meter can be doing right now.
///
/// Named as one closed set rather than read off two booleans at each call
/// site, so the screen cannot render a fourth combination that the session
/// cannot actually be in (paused *and* waiting).
enum _MeterMode { moving, waiting, paused }

class _RunningStep extends StatefulWidget {
  final MeterSession session;
  final VoidCallback onFinish;
  final VoidCallback onTogglePause;

  const _RunningStep({
    required this.session,
    required this.onFinish,
    required this.onTogglePause,
  });

  @override
  State<_RunningStep> createState() => _RunningStepState();
}

class _RunningStepState extends State<_RunningStep>
    with MapCameraFit<_RunningStep> {
  /// Drives the camera so the map keeps showing the run.
  ///
  /// `initialCenter` is honoured exactly once, on the frame the map is
  /// created -- which on this step is the frame the meter starts, when the
  /// track is a single point. Every fix after that extended the gold line
  /// away from a camera that never moved again, so a few minutes in, the
  /// map showed the *start* of the trip with the line leaving the right
  /// edge and the car nowhere on screen. A map that cannot say where you
  /// are is not a map.
  ///
  /// The following itself lives in [MapCameraFit], shared with the trip
  /// screens: one camera-following behaviour in this app rather than one
  /// per map, which is what stops the next map from re-learning this bug.
  final _ownMapController = MapController();

  @override
  MapController get mapCameraController => _ownMapController;

  /// How many fixes the camera has already been fitted to, so a rebuild that
  /// is not a new fix -- the two-second fare tick, a pause, a theme change --
  /// does not re-issue the same fit.
  int _fittedPointCount = 0;

  @override
  void dispose() {
    _ownMapController.dispose();
    super.dispose();
  }

  _MeterMode get _mode {
    if (widget.session.isPaused) return _MeterMode.paused;
    return widget.session.isWaiting ? _MeterMode.waiting : _MeterMode.moving;
  }

  /// Frames the whole driven track, after the frame currently being built.
  ///
  /// Scheduled rather than called inline because `build` is not allowed to
  /// touch the render tree, and because on the very first pass the map has
  /// not finished laying out yet.
  void _scheduleRouteFit(List<ll.LatLng> points) {
    if (points.isEmpty || points.length == _fittedPointCount) return;
    _fittedPointCount = points.length;
    // A single fix is a `move`, not a degenerate bounding box -- see
    // [MapCameraFit]. That is the first second of every run, and it is
    // when the driver most wants to see the car on the map.
    fitMapCamera(points, padding: _kRouteFitPadding);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final session = widget.session;
    final mode = _mode;
    final paused = mode == _MeterMode.paused;
    final points = session.fixes
        .map((fix) => ll.LatLng(fix.lat, fix.lon))
        .toList();
    final center = points.isEmpty
        ? ll.LatLng(defaultCityConfig.centerLat, defaultCityConfig.centerLon)
        : points.last;
    // The newest reading, kept as the fix rather than as a bare coordinate:
    // the ring around the dot is the accuracy that same reading reported,
    // and pairing them here is what stops the two from ever disagreeing.
    final lastFix = session.fixes.isEmpty ? null : session.fixes.last;
    _scheduleRouteFit(points);

    return Stack(
      children: [
        Positioned.fill(
          child: RideMap(
            initialCenter: center,
            controller: mapCameraController,
            onMapReady: () {
              // Not `setState`: nothing this widget paints depends on the
              // flag, and the fit is issued from the next build the track
              // grows in anyway.
              markMapCameraReady();
            },
            layers: [
              if (points.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      color: TakhiColors.gold,
                      strokeWidth: _kRouteStrokeWidth,
                    ),
                  ],
                ),
              // Where the car is NOW, drawn as the same mark every other map
              // in this app draws it as. The head of the gold line is not
              // that mark: it is one end of a shape, it is the same colour
              // as the rest of the line, and on the first fix of a run there
              // is no line at all -- which is exactly the moment a driver
              // looks for the car.
              if (lastFix != null)
                DeviceLocationLayer(
                  position: ll.LatLng(lastFix.lat, lastFix.lon),
                  accuracyMeters: lastFix.accuracyMeters,
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: TakhiSheet(
            showHandle: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Which meter is running, above the number it explains.
                // Without it a driver stopped at a light sees a figure that
                // has stopped climbing (or one climbing while the car is
                // still) and has no way to tell a working meter from a
                // broken one -- and neither does the passenger reading it
                // over their shoulder.
                _MeterModeBadge(mode: mode),
                const SizedBox(height: TakhiSpace.xs),
                // The whole screen exists for this number, and until now it
                // did not look like it: the map had three quarters of the
                // height and the figure a strip at the bottom, which is the
                // wrong way round for an instrument read at a glance from
                // the driver's seat. `meterHeadline` is the taximeter's own
                // size, used nowhere else. Maximum contrast (never the brand
                // gold, which is 2.28:1 on a light sheet), tabular digits so
                // it does not shuffle sideways as it ticks, and scaled down
                // rather than clipped once a fare runs past five figures.
                // Muted while paused: a full-contrast live-looking figure on
                // a meter that has stopped counting is simply a lie.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    l.meterFareLabel(groupedMnt(session.fareMnt)),
                    textAlign: TextAlign.center,
                    style: TakhiType.meterHeadline.copyWith(
                      color: paused ? surfaces.muted : surfaces.onSheet,
                    ),
                  ),
                ),
                const SizedBox(height: TakhiSpace.xs),
                _RunningStatRow(
                  spacing: TakhiSpace.xl,
                  children: [
                    _RunningStat(
                      icon: Icons.straighten,
                      value: l.meterRunningDistanceLabel(
                        _displayKm(session.distanceMeters),
                      ),
                      muted: paused,
                    ),
                    _RunningStat(
                      icon: Icons.schedule_outlined,
                      value: l.meterRunningDurationLabel(
                        session.durationSeconds ~/ 60,
                      ),
                      muted: paused,
                    ),
                  ],
                ),
                // The waiting half of the fare, kept on screen for the whole
                // run rather than appearing when the car stops: a row that
                // comes and goes makes the sheet jump under a driver's eye,
                // and a standing zero is itself the answer to "am I being
                // charged for this jam?". Absent entirely when the driver
                // charges nothing for waiting -- then it could only ever
                // read zero, which is noise on the one screen read while
                // driving.
                if (session.waitTariffMntPerMinute > 0) ...[
                  const SizedBox(height: TakhiSpace.xs),
                  _RunningStatRow(
                    spacing: TakhiSpace.md,
                    children: [
                      _RunningStat(
                        icon: Icons.hourglass_bottom_outlined,
                        value: l.meterWaitingTimeLabel(
                          session.waitingSeconds ~/ 60,
                        ),
                        compact: true,
                        muted: paused,
                      ),
                      _RunningStat(
                        icon: Icons.payments_outlined,
                        value: l.meterWaitingFareLabel(
                          groupedMnt(session.waitingFareMnt),
                        ),
                        compact: true,
                        muted: paused,
                      ),
                    ],
                  ),
                ],
                // A deliberate gap, not rhythm: the controls that end or
                // stop the run sit inside the sheet, a clear step below the
                // figures and well clear of the map a driver pans with the
                // same thumb. Backing out of a run is guarded by
                // `ConfirmLeaveScope`; pressing here is guarded by distance.
                const SizedBox(height: TakhiSpace.lg),
                // The two actions swap emphasis rather than positions when
                // the meter is paused, so both are always in the same two
                // places and the loud one is always the safe one. On a
                // paused meter the recoverable mistake is resuming by
                // accident; finishing by accident writes the journal entry
                // and takes the screen away, so it becomes the quiet
                // button -- while staying reachable, because a trip that
                // ended during a stop must not force the driver to restart
                // the meter just to end it.
                PrimaryButton(
                  label: paused ? l.resumeMeterAction : l.finishMeterAction,
                  onPressed: paused ? widget.onTogglePause : widget.onFinish,
                ),
                const SizedBox(height: TakhiSpace.xs),
                _SecondaryAction(
                  label: paused ? l.finishMeterAction : l.pauseMeterAction,
                  onPressed: paused ? widget.onFinish : widget.onTogglePause,
                  foreground: surfaces.muted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Which meter is running, as one small capsule above the fare.
///
/// A chip rather than a coloured border or a blinking dot: it has to be
/// readable in one glance at arm's length, and it has to be *readable* --
/// a driver who has not memorised a colour code still needs the answer.
/// The cross-fade is short and never repeats, so a car crawling through a
/// jam does not turn the top of the sheet into a flashing light.
class _MeterModeBadge extends StatelessWidget {
  final _MeterMode mode;

  const _MeterModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (label, icon, accent) = switch (mode) {
      // Steppe is the app's "in progress, on its way" family; gold marks
      // the mode that is still charging, only by the minute instead of by
      // the kilometre; clay is the caveat colour, for the one mode where
      // nothing is being charged at all.
      _MeterMode.moving => (
        l.meterModeMovingLabel,
        Icons.navigation_outlined,
        TakhiAccent.steppe,
      ),
      _MeterMode.waiting => (
        l.meterModeWaitingLabel,
        Icons.hourglass_bottom_outlined,
        TakhiAccent.gold,
      ),
      _MeterMode.paused => (
        l.meterModePausedLabel,
        Icons.pause_circle_outline,
        TakhiAccent.clay,
      ),
    };
    // Centred here rather than at the call site: the running sheet's column
    // stretches its children, and a chip stretched to the width of the
    // sheet stops reading as a chip at all.
    return Center(
      child: AnimatedSwitcher(
        duration: TakhiMotion.fast,
        switchInCurve: TakhiMotion.enter,
        switchOutCurve: TakhiMotion.exit,
        child: InfoChip(
          // Keyed by mode, not by label: the switcher has to animate when
          // the meter changes what it is doing and at no other time -- the
          // fare tick rebuilds this widget twice a second.
          key: ValueKey(mode),
          icon: icon,
          label: label,
          accent: accent,
        ),
      ),
    );
  }
}

/// A centred line of [_RunningStat]s that shrinks rather than clipping.
///
/// The same answer the headline fare gives to the same problem: these
/// labels are Mongolian words next to open-ended төгрөг figures, so on a
/// 360dp phone the pair genuinely can outgrow the sheet. Wrapping was the
/// alternative and is worse here -- it would change the sheet's height the
/// moment a fare gained a digit, moving every control under it while the
/// driver is reaching for one. Truncating is not on the table at all: the
/// clipped end of "Хүлээлгэ 12 300₮" is the part that says how much.
class _RunningStatRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const _RunningStatRow({required this.children, required this.spacing});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) SizedBox(width: spacing),
          child,
        ],
      ],
    ),
  );
}

/// One secondary figure under the running fare: a muted glyph and the value
/// in the numeric face, so it is legible at a glance without competing with
/// the number above it.
class _RunningStat extends StatelessWidget {
  final IconData icon;
  final String value;

  /// Sets the value in the label face instead of the numeric one, for the
  /// third-tier figures (the waiting pair) that must not read as loudly as
  /// the distance and duration above them.
  final bool compact;

  /// Drops the value to the supporting colour, for a meter that is paused
  /// and therefore not producing these numbers any more.
  final bool muted;

  const _RunningStat({
    required this.icon,
    required this.value,
    this.compact = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: compact ? _kTariffGlyphSize : _kStatGlyphSize,
          color: surfaces.muted,
        ),
        const SizedBox(width: TakhiSpace.xs),
        Text(
          value,
          style: (compact ? TakhiType.label : TakhiType.numeric).copyWith(
            color: muted ? surfaces.muted : surfaces.onSheet,
          ),
        ),
      ],
    );
  }
}

class _FinishedStep extends StatelessWidget {
  final MeterTripEntry entry;

  /// The rate the run was metered at, for the breakdown line. Nullable only
  /// because the page's own tariff is -- an unreachable state that costs the
  /// subtitle rather than crashing the summary a passenger is waiting on.
  final int? tariffMntPerKm;
  final VoidCallback onReset;

  const _FinishedStep({
    required this.entry,
    required this.tariffMntPerKm,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final durationMinutes = (entry.endedAt - entry.startedAt) ~/ 60;
    final km = _displayKm(entry.distanceMeters);
    final tariff = tariffMntPerKm;
    // Both, not either: a run can have waited without accruing a charge
    // (the driver charges nothing for waiting) and — with a small rate over
    // a short stop — can round to zero төгрөг after genuinely waiting. In
    // both cases the passenger watched the car sit still and is owed the
    // row that accounts for it.
    final waited = entry.waitingSeconds > 0 || entry.waitingFareMnt > 0;

    return Column(
      children: [
        Expanded(
          child: _StepBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(title: l.meterSummaryTitle),
                const SizedBox(height: TakhiSpace.md),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    l.meterFareLabel(groupedMnt(entry.fareMnt)),
                    style: TakhiType.numericDisplay.copyWith(
                      color: surfaces.onSheet,
                    ),
                  ),
                ),
                const SizedBox(height: TakhiSpace.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: TakhiSpace.xs,
                  runSpacing: TakhiSpace.xs,
                  children: [
                    InfoChip(
                      icon: Icons.straighten,
                      label: l.meterRunningDistanceLabel(km),
                    ),
                    InfoChip(
                      icon: Icons.schedule_outlined,
                      label: l.meterRunningDurationLabel(durationMinutes),
                    ),
                  ],
                ),
                const SizedBox(height: TakhiSpace.lg),
                // The arithmetic, itemised. A metered fare a passenger
                // cannot take apart is a fare they can only accept or
                // argue with, and the waiting half is the half that
                // surprises them -- twenty-five minutes in a jam is money
                // they did not watch the odometer earn. Every row here is
                // one the total is literally made of: `distanceFareMnt` is
                // derived from the recorded total minus the recorded
                // waiting half, so the column can never fail to add up.
                _SummaryRow(
                  label: l.meterSummaryDistanceFareRow,
                  value: l.meterFareLabel(groupedMnt(entry.distanceFareMnt)),
                  detail: tariff == null
                      ? null
                      : l.meterFareBreakdownLabel(km, groupedMnt(tariff)),
                ),
                if (waited) ...[
                  const SizedBox(height: TakhiSpace.sm),
                  _SummaryRow(
                    label: l.meterSummaryWaitingFareRow,
                    value: l.meterFareLabel(groupedMnt(entry.waitingFareMnt)),
                  ),
                  const SizedBox(height: TakhiSpace.sm),
                  _SummaryRow(
                    label: l.meterSummaryWaitingDurationRow,
                    value: l.meterRunningDurationLabel(
                      entry.waitingSeconds ~/ 60,
                    ),
                  ),
                ],
                const SizedBox(height: TakhiSpace.sm),
                Divider(height: 1, thickness: 1, color: surfaces.hairline),
                const SizedBox(height: TakhiSpace.sm),
                _SummaryRow(
                  label: l.meterSummaryTotalRow,
                  value: l.meterFareLabel(groupedMnt(entry.fareMnt)),
                  emphasised: true,
                ),
                const SizedBox(height: TakhiSpace.xl),
                SectionHeading(
                  compact: true,
                  title: l.meterPaymentTitle,
                  subtitle: l.payWithQrOrCashHint,
                ),
                const SizedBox(height: TakhiSpace.md),
                // Always shown here -- this screen is driver-only by
                // construction (Global Constraints), so there is no
                // passenger-side branch to consider, unlike
                // `ActiveTripView._DoneView`.
                const Center(child: DriverQrDisplay()),
                const SizedBox(height: TakhiSpace.lg),
                const _DownloadTakhiCard(),
              ],
            ),
          ),
        ),
        TakhiSheet(
          showHandle: false,
          child: PrimaryButton(label: l.startMeterAction, onPressed: onReset),
        ),
      ],
    );
  }
}

/// The "install Тахь" invitation (spec §7.4 step 6, §10 onboarding loop),
/// as a row rather than as a second free-standing code.
///
/// It used to be a bare [QrCard] centred under the driver's own, and the
/// two together do not fit a phone -- which is fine on a scrolling page,
/// except that a white plate on near-white paper has no visible edge, so
/// where the page ran out the picture showed a QR code sliced through the
/// middle with nothing around it. Read at a glance that is a broken code,
/// not a page with more below it. Sitting in a filled, hairlined card the
/// same shape as every other row in the app, a partly-visible invitation
/// reads as exactly what it is.
///
/// It is also the honest hierarchy: the passenger came to this screen to
/// scan the code above, and this one is an offer.
class _DownloadTakhiCard extends StatelessWidget {
  const _DownloadTakhiCard();

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
        padding: const EdgeInsets.all(TakhiSpace.sm),
        child: Row(
          children: [
            QrCard(
              child: QrImageView(
                data: kTakhiAppDownloadUrl,
                size: _kDownloadQrSize,
                // Spelled out rather than left to the package's defaults,
                // which follow neither the plate nor the theme: the modules
                // have to be dark on the white plate in both brightnesses
                // to stay scannable.
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: TakhiColors.ink,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: TakhiColors.ink,
                ),
              ),
            ),
            const SizedBox(width: TakhiSpace.md),
            Expanded(
              child: Text(
                l.downloadTakhiQrLabel,
                style: TakhiType.title.copyWith(color: surfaces.onSheet),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the finished step's fare breakdown: what it is on the left,
/// how much on the right, and — on the one row that has any — the sum
/// behind it underneath.
///
/// The value is always in the numeric face so the column of figures lines
/// up on its tabular digits; a passenger checking that the parts add to the
/// total should be able to do it down a straight edge, not by hunting for
/// numbers of different sizes.
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  /// The arithmetic behind [value], set on the distance row. `null`
  /// elsewhere.
  final String? detail;

  /// Sets the row in the heavier faces: the total, which is the number the
  /// passenger is actually being asked for.
  final bool emphasised;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.detail,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final explanation = detail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: (emphasised ? TakhiType.title : TakhiType.body).copyWith(
                  color: emphasised ? surfaces.onSheet : surfaces.muted,
                ),
              ),
            ),
            const SizedBox(width: TakhiSpace.sm),
            Text(
              value,
              style: TakhiType.numeric.copyWith(color: surfaces.onSheet),
            ),
          ],
        ),
        if (explanation != null) ...[
          const SizedBox(height: TakhiSpace.xxs),
          Text(
            explanation,
            style: TakhiType.support.copyWith(color: surfaces.muted),
          ),
        ],
      ],
    );
  }
}
