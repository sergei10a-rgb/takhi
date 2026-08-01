// SPDX-License-Identifier: AGPL-3.0-or-later

/// Records what the meter saw and what it did about it, so a run that
/// under-counts can say where the missing distance went.
///
/// Built after a field test where Takhi's odometer read 26% and 13% short
/// against a commercial meter on the same two rides. Three separate causes
/// were plausible and none could be told apart from the finished fare:
///
///  1. the jitter floor discarding real movement (`belowNoiseFloor`),
///  2. Android throttling location delivery once the app went to the
///     background — which shows up here not as a verdict at all but as a
///     **gap between arrivals**, because the fixes simply stop coming.
///
/// Guessing between those and "fixing" the wrong one would have been worse
/// than the bug: loosening the jitter floor while delivery was still being
/// throttled would start over-counting, and over-counting bills a passenger
/// for metres nobody drove. So this measures first.
///
/// No clock of its own: the arrival time is passed in. That keeps the whole
/// class testable without a device, which is the same rule `MeterSession`
/// follows and for the same reason.
library;

import 'dart:math' as math;

import '../geo/gps_fix.dart';
import 'meter_fix_verdict.dart';

/// Anything longer than this between two arrivals is not a fix interval,
/// it is a stall. The app asks for one fix every 5 seconds, so three times
/// that is well outside normal jitter and well inside what a backgrounded
/// app looks like.
const int kStalledArrivalMillis = 15000;

/// How many samples the log keeps for the row-by-row export.
///
/// A 12-hour shift at one fix per 5 seconds is over 8,000 rows, which is
/// more than anyone will read and more than a driver can paste into a chat.
/// The **totals below are accumulated as fixes arrive, not derived from the
/// retained rows**, so trimming costs detail and never costs accuracy —
/// the same rule `billableDurationSeconds` learned the hard way.
const int kMaxRetainedSamples = 4000;

/// One recorded fix: what arrived, when it arrived, and what was made of it.
class MeterDiagnosticSample {
  final GpsFix fix;

  /// Device wall clock at the moment the fix reached the app, in
  /// milliseconds. Deliberately *not* the fix's own timestamp: the gap
  /// between arrivals is what exposes a stalled location stream, and a fix
  /// delivered late still carries an honest capture time, so the two clocks
  /// disagree in exactly the case worth detecting.
  final int arrivalMillis;

  final MeterFixVerdict verdict;

  const MeterDiagnosticSample({
    required this.fix,
    required this.arrivalMillis,
    required this.verdict,
  });
}

/// Running diagnostic for one meter run.
class MeterDiagnosticLog {
  final int maxRetainedSamples;

  MeterDiagnosticLog({this.maxRetainedSamples = kMaxRetainedSamples});

  final List<MeterDiagnosticSample> _samples = [];
  final Map<MeterFixOutcome, int> _outcomeCounts = {};
  final Map<MeterFixOutcome, double> _discardedByOutcome = {};

  int _recordedCount = 0;
  int _trimmedCount = 0;
  double _rawMeters = 0;
  double _countedMeters = 0;
  int _longestArrivalGapMillis = 0;
  int _stalledArrivalCount = 0;
  double _accuracySum = 0;
  int _accuracySamples = 0;
  double _worstAccuracyMeters = 0;
  double _noiseFloorSum = 0;
  int _noiseFloorSamples = 0;
  int? _firstArrivalMillis;
  int? _lastArrivalMillis;

  /// Files one fix. [arrivalMillis] is the device wall clock when it landed.
  void record({
    required GpsFix fix,
    required int arrivalMillis,
    required MeterFixVerdict verdict,
  }) {
    final previousArrival = _lastArrivalMillis;
    if (previousArrival != null) {
      final gap = arrivalMillis - previousArrival;
      // A negative gap means the device clock stepped backwards mid-run.
      // Counting it would understate the longest stall, so it is ignored
      // rather than clamped to zero and quietly averaged in.
      if (gap > 0) {
        _longestArrivalGapMillis = math.max(_longestArrivalGapMillis, gap);
        if (gap >= kStalledArrivalMillis) _stalledArrivalCount++;
      }
    }
    _firstArrivalMillis ??= arrivalMillis;
    _lastArrivalMillis = arrivalMillis;

    _recordedCount++;
    _rawMeters += verdict.rawMeters;
    _countedMeters += verdict.countedMeters;
    _outcomeCounts.update(verdict.outcome, (n) => n + 1, ifAbsent: () => 1);
    if (verdict.discardedMeters > 0) {
      _discardedByOutcome.update(
        verdict.outcome,
        (m) => m + verdict.discardedMeters,
        ifAbsent: () => verdict.discardedMeters,
      );
    }

    final accuracy = fix.accuracyMeters;
    if (accuracy != null) {
      _accuracySum += accuracy;
      _accuracySamples++;
      _worstAccuracyMeters = math.max(_worstAccuracyMeters, accuracy);
    }
    if (verdict.noiseFloorMeters > 0) {
      _noiseFloorSum += verdict.noiseFloorMeters;
      _noiseFloorSamples++;
    }

    _samples.add(
      MeterDiagnosticSample(
        fix: fix,
        arrivalMillis: arrivalMillis,
        verdict: verdict,
      ),
    );
    while (_samples.length > maxRetainedSamples) {
      _samples.removeAt(0);
      _trimmedCount++;
    }
  }

  List<MeterDiagnosticSample> get samples => List.unmodifiable(_samples);

  /// Every fix handed to [record], including the ones whose rows have since
  /// been trimmed.
  int get recordedCount => _recordedCount;
  int get trimmedCount => _trimmedCount;

  /// Total displacement the GPS reported, before any rule was applied.
  double get rawMeters => _rawMeters;

  /// Total distance that reached the odometer.
  double get countedMeters => _countedMeters;

  /// What the rules refused. The number this whole class exists to produce.
  double get discardedMeters => _rawMeters - _countedMeters;

  /// Share of measured distance that was billed, 0..1. `1` when nothing was
  /// measured at all, because "no distance, none lost" is a better answer
  /// than a division by zero.
  double get countedFraction => _rawMeters <= 0 ? 1 : _countedMeters / _rawMeters;

  double discardedMetersBy(MeterFixOutcome outcome) =>
      _discardedByOutcome[outcome] ?? 0;

  int countOf(MeterFixOutcome outcome) => _outcomeCounts[outcome] ?? 0;

  /// The longest a fix ever took to follow the one before it. Well over the
  /// requested interval means delivery stalled — the signature of the app
  /// being backgrounded or the screen sleeping.
  int get longestArrivalGapMillis => _longestArrivalGapMillis;

  int get stalledArrivalCount => _stalledArrivalCount;

  /// Wall-clock span from the first arrival to the last, in milliseconds.
  int get spanMillis {
    final first = _firstArrivalMillis;
    final last = _lastArrivalMillis;
    if (first == null || last == null) return 0;
    return math.max(0, last - first);
  }

  /// Mean interval between arrivals. Compared against the 5 seconds the app
  /// asks for, this says whether the stream ran at the rate requested.
  double get meanArrivalGapMillis =>
      _recordedCount < 2 ? 0 : spanMillis / (_recordedCount - 1);

  double get meanAccuracyMeters =>
      _accuracySamples == 0 ? 0 : _accuracySum / _accuracySamples;

  double get worstAccuracyMeters => _worstAccuracyMeters;

  /// Mean jitter floor a segment had to clear. Read beside
  /// [meanArrivalGapMillis] this gives the speed a car had to exceed before
  /// a single metre was counted — the number that explains the shortfall.
  double get meanNoiseFloorMeters =>
      _noiseFloorSamples == 0 ? 0 : _noiseFloorSum / _noiseFloorSamples;

  /// Speed, in km/h, a vehicle had to beat for its movement to be billed at
  /// all, on average, given how often fixes actually arrived.
  ///
  /// This is the single most useful figure in the report. At a 5-second
  /// interval and a +/-15m fix the floor is 30m, so anything under 21.6 km/h
  /// scored zero distance — and Ulaanbaatar traffic lives below that.
  double get billingSpeedThresholdKmh {
    final gapSeconds = meanArrivalGapMillis / 1000;
    if (gapSeconds <= 0 || meanNoiseFloorMeters <= 0) return 0;
    return meanNoiseFloorMeters / gapSeconds * 3.6;
  }

  bool get isEmpty => _recordedCount == 0;
}
