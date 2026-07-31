// SPDX-License-Identifier: AGPL-3.0-or-later
import '../geo/gps_fix.dart';
import '../geo/gps_track.dart';
import 'fare_calc.dart';

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
/// km-tariff) or **waiting** (billed by the minute-tariff) — decided per
/// segment from [segmentSpeedKmh] against [kWaitingSpeedThresholdKmh].
/// Never both. That is not an optimisation: a stopped phone's GPS keeps
/// drifting a metre or two between fixes, so a meter that accrued distance
/// while also charging for the wait would bill the passenger twice for one
/// stop — once as jitter it never travelled, once as time. Charging the
/// drift is the failure this class exists to prevent; the same rule also
/// keeps the recorded [distanceMeters] honest, since jitter is not travel
/// in a fixed-price trip either.
///
/// Ulaanbaatar traffic is what makes the waiting side necessary at all: a
/// distance-only meter bills a driver zero for the twenty-five minutes they
/// spend burning fuel in a jam, unable to pick anyone else up.
class MeterSession {
  final int mntPerKm;

  /// The driver's waiting rate. Zero — the default — means waiting is free,
  /// which is exactly how every run behaved before this existed and what a
  /// tariff saved by an older version of the app migrates to.
  final int waitTariffMntPerMinute;

  final GpsTrackAccumulator _track = GpsTrackAccumulator();

  /// The last *accepted* fix, i.e. the open end of the segment the next fix
  /// will close. Held here rather than read back off [_track] because
  /// `GpsTrackAccumulator.fixes` hands out a fresh unmodifiable copy on
  /// every read.
  GpsFix? _previousFix;

  double _travelledMeters = 0;
  int _waitingSeconds = 0;
  int _pausedSeconds = 0;
  bool _isWaiting = false;
  bool _isPaused = false;

  /// Set by [pause]/[resume] so the one segment straddling the change is
  /// dropped instead of being charged wholly at whichever mode happened to
  /// win. See [pause] for why the passenger is the one who gets the benefit
  /// of that doubt.
  bool _discardNextSegment = false;

  MeterSession({required this.mntPerKm, this.waitTariffMntPerMinute = 0});

  /// Feeds one GPS reading in, closing the segment opened by the previous
  /// one and crediting it to exactly one meter.
  ///
  /// A fix that does not advance the clock — a duplicate, or a reading that
  /// arrives out of order after the device clock steps backwards — is
  /// dropped whole, leaving the open segment untouched so the *next* real
  /// fix still measures against a sane starting point. Dropping it also
  /// keeps [fixes] strictly ordered in time, which is what lets
  /// [durationSeconds] simply subtract the ends.
  void addFix(GpsFix fix) {
    final previous = _previousFix;
    if (previous == null) {
      _track.addFix(fix);
      _previousFix = fix;
      return;
    }
    final seconds = fix.timestampSeconds - previous.timestampSeconds;
    if (seconds <= 0) return;

    _track.addFix(fix);
    _previousFix = fix;

    if (_discardNextSegment) {
      _discardNextSegment = false;
      return;
    }
    if (_isPaused) {
      _pausedSeconds += seconds;
      return;
    }
    _isWaiting = isWaitingSpeed(segmentSpeedKmh(previous, fix));
    if (_isWaiting) {
      _waitingSeconds += seconds;
    } else {
      _travelledMeters += haversineMeters(
        previous.lat,
        previous.lon,
        fix.lat,
        fix.lon,
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
    _isWaiting = false;
    _discardNextSegment = true;
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

  int get waitingSeconds => _waitingSeconds;
  int get pausedSeconds => _pausedSeconds;

  /// Which meter is running right now — what the live display reads out so
  /// the passenger can see *why* the number is moving. `false` until the
  /// first segment closes: at that point nothing is accruing either way, and
  /// announcing a wait before one has been measured would be a claim the
  /// meter cannot back up.
  bool get isWaiting => _isWaiting;
  bool get isPaused => _isPaused;

  int get distanceFareMnt =>
      computeFareMnt(mntPerKm: mntPerKm, distanceMeters: distanceMeters);

  int get waitingFareMnt => computeWaitingFareMnt(
    mntPerMinute: waitTariffMntPerMinute,
    waitingSeconds: waitingSeconds,
  );

  /// The running total. Always exactly [distanceFareMnt] + [waitingFareMnt],
  /// so the breakdown a passenger reads adds up to the number they pay.
  int get fareMnt => computeTotalFareMnt(
    mntPerKm: mntPerKm,
    distanceMeters: distanceMeters,
    mntPerMinute: waitTariffMntPerMinute,
    waitingSeconds: waitingSeconds,
  );
}
