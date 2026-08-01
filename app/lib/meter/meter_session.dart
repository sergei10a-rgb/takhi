// SPDX-License-Identifier: AGPL-3.0-or-later
import '../geo/gps_fix.dart';
import '../geo/gps_jitter.dart';
import '../geo/gps_track.dart';
import 'fare_calc.dart';
import 'meter_fix_verdict.dart';
import 'meter_run_snapshot.dart';

/// Accumulates GPS fixes for one taximeter run (spec §7.4 step 3: the big
/// live ₮/km/time display) and derives the running fare. `TaximeterPage`
/// (Task 8) owns the actual `LocationSource` subscription and calls
/// [addFix] as fixes arrive; this class has no I/O of its own — not even a
/// clock. Every second it counts comes from a fix's own timestamp, which is
/// what makes a finished run reproducible from its recorded track.
///
/// ## Exactly one meter runs at a time
///
/// A run is, at every instant, either **travelling** (billed by the
/// km-tariff) or **waiting** (billed by the minute-tariff). Never both: a
/// stopped phone's GPS keeps drifting a metre or two between fixes, so a
/// meter that accrued distance while also charging for the wait would bill
/// the passenger twice for one stop — once as jitter it never travelled,
/// once as time.
///
/// Ulaanbaatar traffic is what makes the waiting side necessary at all: a
/// distance-only meter bills a driver zero for the twenty-five minutes they
/// spend burning fuel in a jam, unable to pick anyone else up.
///
/// ## What decides which
///
/// One test, not two: **has the car measurably left the anchor** — the last
/// position distance was committed from. Cleared, it is travel and the
/// distance is billed. Not cleared, the car is standing still.
///
/// Standing still is **not** the same as waiting. A jam is part of the trip
/// and is paid for by the trip-duration rate; waiting is a phase the driver
/// enters deliberately, because the passenger has not come out yet or has
/// asked them to hold. The two rates never run together, so a minute is
/// charged once whichever it is.
///
/// That replaced a pair of per-segment rules (a jitter floor, then a 5 km/h
/// speed threshold) which each discarded a segment's distance permanently
/// when it failed. Together they cost a real driver 26% of one ride and 13%
/// of another, measured against a commercial meter on the same roads: with
/// a +/-15m fix at a five-second interval the floor sat at 30m, so anything
/// slower than 21.6 km/h earned exactly nothing and the metres were never
/// recovered. Anchoring keeps the anti-jitter property — a parked car never
/// displaces from its anchor however long it sits — while letting slow
/// movement accumulate until it is undeniable.
class MeterSession {
  final int mntPerKm;

  /// The driver's rate for waiting on the passenger. Charged only while
  /// [isWaiting], which only the driver can turn on.
  final int waitTariffMntPerMinute;

  /// Charged once, at the start of the run: the flag-fall.
  final int boardingMnt;

  /// The driver's whole-trip-duration rate, billed on every second from
  /// the first fix to the last whether the car was moving or not.
  ///
  /// Mutually exclusive with [waitTariffMntPerMinute]: a second is on one
  /// rate or the other, never both. Traffic is trip duration; waiting is
  /// the passenger keeping the driver.
  final int durationTariffMntPerMinute;

  final GpsTrackAccumulator _track = GpsTrackAccumulator();

  /// The last *accepted* fix, i.e. the open end of the segment the next fix
  /// will close. Held here rather than read back off [_track] because
  /// `GpsTrackAccumulator.fixes` hands out a fresh unmodifiable copy on
  /// every read.
  GpsFix? _previousFix;

  /// The last position distance was actually committed from.
  ///
  /// Distinct from [_previousFix] on purpose: the previous fix answers "how
  /// long since the last reading", the anchor answers "how far from
  /// somewhere we were sure about". Judging distance against the previous
  /// fix is what let a quarter of a real ride fall through the jitter floor
  /// five metres at a time -- see [addFix].
  GpsFix? _anchorFix;

  double _travelledMeters = 0;
  int _waitingSeconds = 0;
  int _pausedSeconds = 0;

  /// Seconds the meter was actually live: neither paused, nor inside a
  /// segment discarded across a pause boundary, nor inside one thrown out
  /// as a bad fix. Accumulated as it happens rather than derived by
  /// subtracting the pause from the wall clock, because subtraction leaks.
  /// See [billableDurationSeconds].
  int _billableDurationSeconds = 0;
  /// Turned on by the driver, never by the GPS. See the class doc.
  bool _isWaiting = false;

  /// Whether the car has stopped moving, as measured. Display only: a jam
  /// is billed by the trip-duration rate like any other minute of the trip,
  /// so this changes what the screen says and never what it charges.
  bool _isStopped = false;

  bool _isPaused = false;

  /// Seconds spent standing still, measured rather than charged. Kept for
  /// the receipt — a passenger who watched the car sit in traffic for
  /// twenty minutes is owed a line that says so.
  int _stoppedSeconds = 0;

  /// Set by [pause]/[resume] so the one segment straddling the change is
  /// dropped instead of being charged wholly at whichever mode happened to
  /// win. See [pause] for why the passenger is the one who gets the benefit
  /// of that doubt.
  bool _discardNextSegment = false;

  MeterSession({
    required this.mntPerKm,
    this.waitTariffMntPerMinute = 0,
    this.durationTariffMntPerMinute = 0,
    this.boardingMnt = 0,
  });

  /// Rebuilds a run that was interrupted, from the totals it had reached.
  ///
  /// The fix track is deliberately NOT restored: [fixes] starts empty and
  /// the first fix after a resume opens a fresh segment rather than closing
  /// one against a reading from before the app died. That gap is real and
  /// is resolved in the passenger's favour — the distance covered while the
  /// app was gone is not billed, because nothing measured it and inventing
  /// it would be inventing money.
  ///
  /// [durationSeconds] therefore restarts too, which is why the receipt
  /// takes its start time from the snapshot instead of from this class.
  MeterSession.resumed(MeterRunSnapshot from)
    : mntPerKm = from.mntPerKm,
      waitTariffMntPerMinute = from.waitTariffMntPerMinute,
      durationTariffMntPerMinute = from.durationTariffMntPerMinute,
      boardingMnt = from.boardingMnt {
    _travelledMeters = from.distanceMeters.toDouble();
    _waitingSeconds = from.waitingSeconds;
    _billableDurationSeconds = from.billableDurationSeconds;
    _pausedSeconds = from.pausedSeconds;
    _isPaused = from.isPaused;
    _isWaiting = from.isWaiting;
    _stoppedSeconds = from.stoppedSeconds;
  }

  MeterRunSnapshot snapshot({required int startedAtSeconds}) =>
      MeterRunSnapshot(
        mntPerKm: mntPerKm,
        waitTariffMntPerMinute: waitTariffMntPerMinute,
        durationTariffMntPerMinute: durationTariffMntPerMinute,
        startedAtSeconds: startedAtSeconds,
        distanceMeters: distanceMeters,
        waitingSeconds: _waitingSeconds,
        billableDurationSeconds: _billableDurationSeconds,
        pausedSeconds: _pausedSeconds,
        isPaused: _isPaused,
        isWaiting: _isWaiting,
        stoppedSeconds: _stoppedSeconds,
        boardingMnt: boardingMnt,
        lastFixSeconds: _previousFix?.timestampSeconds ?? 0,
      );

  /// Feeds one GPS reading in, closing the segment opened by the previous
  /// one and crediting it to exactly one meter.
  ///
  /// A fix that does not advance the clock — a duplicate, or a reading that
  /// arrives out of order after the device clock steps backwards — is
  /// dropped whole, leaving the open segment untouched so the *next* real
  /// fix still measures against a sane starting point. Dropping it also
  /// keeps [fixes] strictly ordered in time, which is what lets
  /// [durationSeconds] simply subtract the ends.
  ///
  /// Returns what it decided, and how far the fix said the car had moved
  /// before that decision was applied. Callers are free to ignore it; the
  /// diagnostic recorder is not. Until this return value existed a run that
  /// discarded a third of its distance looked exactly like a run that had
  /// not travelled it — see [MeterFixVerdict] for the field report that
  /// made the difference matter.
  MeterFixVerdict addFix(GpsFix fix) {
    final previous = _previousFix;
    if (previous == null) {
      _track.addFix(fix);
      _previousFix = fix;
      _anchorFix = fix;
      return const MeterFixVerdict(outcome: MeterFixOutcome.opened);
    }
    final seconds = fix.timestampSeconds - previous.timestampSeconds;
    if (seconds <= 0) {
      return const MeterFixVerdict(outcome: MeterFixOutcome.noTimeAdvance);
    }

    // Measured up front and carried into every branch below, including the
    // ones that throw it away. The discarded figure is the one worth
    // keeping: a run can only explain its own shortfall if the metres it
    // refused are written down beside the metres it billed.
    final rawMeters = haversineMeters(
      previous.lat,
      previous.lon,
      fix.lat,
      fix.lon,
    );
    final floorMeters = noiseFloorMeters(previous, fix);
    final speedKmh = segmentSpeedKmh(previous, fix);

    MeterFixVerdict verdict(MeterFixOutcome outcome, {double counted = 0}) =>
        MeterFixVerdict(
          outcome: outcome,
          seconds: seconds,
          rawMeters: rawMeters,
          countedMeters: counted,
          noiseFloorMeters: floorMeters,
          speedKmh: speedKmh,
        );

    _track.addFix(fix);
    _previousFix = fix;

    if (_discardNextSegment) {
      _discardNextSegment = false;
      // Re-anchor: a meter coming back from a pause measures from where it
      // resumed, not from where it stopped. Without this the whole paused
      // stretch would be committed in one step by the first fix after the
      // resume -- billing a passenger for a fuel stop.
      _anchorFix = fix;
      return verdict(MeterFixOutcome.pauseBoundary);
    }
    if (_isPaused) {
      _pausedSeconds += seconds;
      _anchorFix = fix;
      return verdict(MeterFixOutcome.paused);
    }
    // A fix that implies 200+ km/h is a wrong fix, not a fast car. Neither
    // meter is credited: charging the time would bill the passenger for the
    // GPS being confused, and charging the distance would add several
    // hundred phantom metres in one step. Judged against the previous fix
    // rather than the anchor, because it is a sanity check on this reading.
    if (speedKmh > kMaxPlausibleSpeedKmh) {
      return verdict(MeterFixOutcome.implausible);
    }

    if (_isWaiting) {
      // The waiting phase has its own rate. Running the trip-duration rate
      // through it as well would charge one minute twice — the exact
      // double-charge the author ruled out when this model was chosen.
      _waitingSeconds += seconds;
    } else {
      _billableDurationSeconds += seconds;
    }

    // Distance is measured from the ANCHOR -- the last position distance was
    // actually committed from -- and not from the previous fix.
    //
    // This is the fix for the shortfall a driver measured in the field: 26%
    // and 13% short against a commercial meter over two rides. The old rule
    // judged each five-second segment on its own and, when the segment did
    // not clear the jitter floor, threw its metres away for good. With a
    // +/-15m fix the floor is 30m, so anything under 21.6 km/h scored
    // exactly zero -- and Ulaanbaatar traffic lives below that. The metres
    // were never recovered; they were simply gone.
    //
    // Anchoring keeps both properties that matter:
    //
    //  * a PARKED car never accrues distance, because drift wanders around
    //    one spot and its displacement from the anchor never clears the
    //    floor no matter how long it sits there. That is the failure this
    //    class was built to prevent and it is preserved exactly.
    //
    //  * a car CRAWLING at 10 km/h now accrues, because after eleven
    //    seconds it is genuinely 30m from where it started, the floor is
    //    cleared, and the anchor moves up. Slow movement is no longer
    //    silently free.
    //
    // What is committed is the straight-line displacement from the anchor,
    // not the summed path since it. On a curve that under-counts slightly.
    // That is deliberate: the summed path of a parked car is jitter, and
    // committing it the moment the car pulled away would bill a passenger
    // for metres nobody drove. The under-count is bounded by how long the
    // anchor survives, which at any real driving speed is one fix.
    final anchor = _anchorFix ?? previous;
    switch (classifyMovement(anchor, fix)) {
      case GpsMovement.travelled:
        final anchorMeters = haversineMeters(
          anchor.lat,
          anchor.lon,
          fix.lat,
          fix.lon,
        );
        _travelledMeters += anchorMeters;
        _anchorFix = fix;
        _isStopped = false;
        return verdict(MeterFixOutcome.travelled, counted: anchorMeters);
      case GpsMovement.implausible:
        // Only reachable from a very old anchor, since the previous-fix
        // check above already caught the fast cases. Re-anchor: whatever
        // this reading is, measuring the next one against a position this
        // one disagrees with so violently would compound the error.
        _anchorFix = fix;
        return verdict(MeterFixOutcome.implausible);
      case GpsMovement.stationary:
        // Still inside the noise around the anchor: no distance. The
        // seconds are already on the trip-duration rate above, which is
        // what a jam costs — this only records that the car was stopped,
        // so the receipt can say so.
        _isStopped = true;
        // Not counted while the driver has the meter in its waiting phase:
        // those seconds are already on the waiting line, and a receipt whose
        // rows overlap is one a passenger cannot check.
        if (!_isWaiting) _stoppedSeconds += seconds;
        // `classifyMovement` folds two findings into one answer: a fix too
        // poor to measure against, and a movement too small to trust. They
        // cost the same distance and mean opposite things, so the verdict
        // separates them even though the billing does not.
        final accuracy = fix.accuracyMeters;
        return verdict(
          accuracy != null && accuracy > kMaxUsableAccuracyMeters
              ? MeterFixOutcome.accuracyTooPoor
              : MeterFixOutcome.belowNoiseFloor,
        );
    }
  }

  /// Stops the meter entirely: while paused neither distance nor waiting
  /// accrues, only [pausedSeconds]. For the breaks that are nobody's fare —
  /// the driver stopping for fuel, or a passenger's errand both sides agreed
  /// is off the clock.
  ///
  /// Takes effect from the next segment, and the segment straddling the call
  /// is discarded rather than charged: without a clock of its own this class
  /// cannot know where inside that segment the pause fell, and billing a
  /// passenger for a stretch that was partly already paused is the error
  /// worth avoiding. The cost is bounded by one fix interval — a few seconds
  /// of un-metered travel per pause, which lands on the passenger's side of
  /// the doubt on purpose.
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _isStopped = false;
    _discardNextSegment = true;
  }

  /// Starts charging the waiting rate: the passenger has not come out yet,
  /// or has asked the driver to hold.
  ///
  /// Driver-operated on purpose. The app cannot tell a car waiting outside
  /// a building from a car stopped at a light, and guessing wrong in one
  /// direction bills a passenger twice for a jam while guessing wrong in
  /// the other works the driver for nothing. Only one of the two people
  /// present knows which it is.
  void startWaiting() {
    if (_isWaiting || _isPaused) return;
    _isWaiting = true;
  }

  void stopWaiting() {
    if (!_isWaiting) return;
    _isWaiting = false;
  }

  /// Puts the meter back on the clock. The segment straddling the call is
  /// discarded for the same reason [pause] discards its own.
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _discardNextSegment = true;
  }

  List<GpsFix> get fixes => _track.fixes;

  /// Distance the vehicle actually travelled — waiting and paused segments
  /// contribute nothing, so this is both what the km-tariff bills and the
  /// honest number to record on a receipt.
  int get distanceMeters => _travelledMeters.round();

  /// Whole elapsed time of the run, first accepted fix to last: travelling
  /// plus waiting plus paused, plus the sub-interval remainder no segment
  /// has closed yet.
  int get durationSeconds => _track.durationSeconds;

  /// Seconds charged at the waiting rate — only the ones the driver put
  /// the meter into the waiting phase for.
  int get waitingSeconds => _waitingSeconds;

  /// Seconds the car stood still without the driver calling it waiting: a
  /// jam, a light, a queue. Measured for the receipt, charged by the
  /// trip-duration rate like every other minute of the trip.
  int get stoppedSeconds => _stoppedSeconds;

  /// Whether the car is standing still right now. Display only.
  bool get isStopped => _isStopped;
  int get pausedSeconds => _pausedSeconds;

  /// The seconds the trip-duration rate actually charges for: every second
  /// the meter was live.
  ///
  /// [durationSeconds] stays the honest wall clock, because that is what a
  /// receipt should say the trip took. This is the billable subset, and the
  /// two must not be confused.
  ///
  /// Excluding the pause is not a softening of the "duration means the WHOLE
  /// trip" rule the author set -- that rule settles the overlap with the
  /// stopped-time rate, which is deliberate and stays. [pause] is a
  /// different thing entirely: both sides agreeing the meter is OFF, for a
  /// break that is nobody's fare (the driver stopping for fuel, an errand
  /// the passenger asked for). Billing the duration rate straight through
  /// that would leave `pause()` charging money while announcing it had
  /// stopped, and «Түр зогсоох» would mean nothing at all. Measured before
  /// the fix: a 3-minute run with 2 minutes paused, at 600₮/мин, billed the
  /// passenger 1800₮ for a fuel stop.
  ///
  /// **Accumulated, not derived.** The obvious implementation is
  /// `durationSeconds - pausedSeconds`, and it is wrong: the segment
  /// straddling a `pause()` call is discarded rather than counted as paused
  /// (see [pause]), so it appears in neither term and the subtraction bills
  /// it anyway. That leak charged a whole fix interval per pause -- and it
  /// charged it in the one direction this class never resolves doubt,
  /// against the passenger. Counting up from the segments that were
  /// genuinely on the clock cannot leak, because a second has to be
  /// deliberately added to be billed.
  int get billableDurationSeconds => _billableDurationSeconds;

  /// Which meter is running right now — what the live display reads out so
  /// the passenger can see *why* the number is moving. `false` until the
  /// first segment closes: at that point nothing is accruing either way, and
  /// announcing a wait before one has been measured would be a claim the
  /// meter cannot back up.
  /// Whether the driver has put the meter into its waiting phase.
  bool get isWaiting => _isWaiting;
  bool get isPaused => _isPaused;

  int get distanceFareMnt =>
      computeFareMnt(mntPerKm: mntPerKm, distanceMeters: distanceMeters);

  /// The flag-fall, charged once the run has started.
  ///
  /// Gated on there being a fix rather than on the object existing, so a
  /// meter that has been opened but has not yet heard from the GPS shows
  /// zero rather than a charge for a trip that has not begun.
  int get boardingFareMnt => _previousFix == null ? 0 : boardingMnt;

  int get waitingFareMnt => computeWaitingFareMnt(
    mntPerMinute: waitTariffMntPerMinute,
    waitingSeconds: waitingSeconds,
  );

  /// What the whole-trip-duration rate has run up so far.
  int get durationFareMnt => computeDurationFareMnt(
    mntPerMinute: durationTariffMntPerMinute,
    durationSeconds: billableDurationSeconds,
  );

  /// The running total. Always exactly [distanceFareMnt] + [waitingFareMnt]
  /// + [durationFareMnt], so the breakdown a passenger reads adds up to the
  /// number they pay.
  int get fareMnt =>
      boardingFareMnt +
      computeTotalFareMnt(
        mntPerKm: mntPerKm,
        distanceMeters: distanceMeters,
        mntPerMinute: waitTariffMntPerMinute,
        waitingSeconds: waitingSeconds,
        durationMntPerMinute: durationTariffMntPerMinute,
        durationSeconds: billableDurationSeconds,
      );
}
