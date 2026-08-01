// SPDX-License-Identifier: AGPL-3.0-or-later

/// What the meter did with one GPS fix, and why.
///
/// This exists because of a bug nobody could see. A driver ran Takhi beside
/// a commercial app on the same two rides and Takhi's odometer read 26% and
/// 13% short (5.2km against 7.023km; 3.7km against 4.27km). Every one of
/// those missing metres was discarded deliberately, by rules that are each
/// defensible on their own — and `MeterSession` kept no record of having
/// discarded anything, so from the outside the shortfall looked like the
/// GPS being bad rather than like the app throwing readings away.
///
/// A meter that decides money from a GPS stream has to be able to answer
/// "where did that kilometre go". These types are that answer.
library;

/// Which rule decided a fix's fate.
enum MeterFixOutcome {
  /// First fix of the run: it opens the track, and there is no previous
  /// reading to measure against yet.
  opened,

  /// The fix did not advance the clock — a duplicate delivery, or a reading
  /// that arrived after the device clock stepped backwards. Dropped whole,
  /// leaving the open segment intact.
  noTimeAdvance,

  /// The segment straddled a `pause()` or `resume()` call and was discarded
  /// rather than charged at whichever mode happened to win.
  pauseBoundary,

  /// The meter was off. Only paused seconds accrued.
  paused,

  /// The segment implied a speed no taxi does, so the fix is wrong rather
  /// than the car fast. Neither distance nor time credited.
  implausible,

  /// The fix's own reported accuracy was worse than
  /// [kMaxUsableAccuracyMeters], so it says too little about where the car
  /// is to measure against. Distance discarded, seconds billed as waiting.
  ///
  /// Kept apart from [belowNoiseFloor] because the two look identical in a
  /// total and mean opposite things: this one is the GPS admitting it does
  /// not know, the other is the app deciding a known movement was too small
  /// to trust.
  accuracyTooPoor,

  /// The displacement did not clear the jitter floor, so the distance was
  /// discarded and the seconds were billed as waiting.
  ///
  /// **This is the outcome that ate the driver's kilometres.** At the
  /// default five-second fix interval the floor is `max(8m, accuracy x 2)`,
  /// so a fix reporting +/-15m needs the car to cover more than 30m in five
  /// seconds — over 21 km/h — before a single metre is counted. Ulaanbaatar
  /// traffic spends a great deal of its time below that, and every metre of
  /// it scored zero.
  belowNoiseFloor,

  /// The displacement cleared the jitter floor but the segment's average
  /// speed was under [kWaitingSpeedThresholdKmh], so the meter treated it
  /// as waiting and the distance was discarded too.
  ///
  /// A second, independent filter on top of [belowNoiseFloor]: distance is
  /// only ever counted when a segment clears *both*.
  belowWaitingSpeed,

  /// Real travel. The distance reached the odometer.
  travelled,
}

/// One fix's outcome, with the numbers the decision was made from.
///
/// Carries [rawMeters] as well as [countedMeters] on purpose: the gap
/// between them is the whole diagnostic. A run where they match is a run
/// where the filters cost nothing; a run where they diverge names exactly
/// how much distance the app decided not to bill, and under which rule.
class MeterFixVerdict {
  final MeterFixOutcome outcome;

  /// Seconds this segment spanned. Zero for [MeterFixOutcome.opened] and
  /// [MeterFixOutcome.noTimeAdvance].
  final int seconds;

  /// Great-circle displacement between the two fixes, before any judgement
  /// was applied to it.
  final double rawMeters;

  /// What actually reached the odometer — [rawMeters] for
  /// [MeterFixOutcome.travelled], zero for every other outcome.
  final double countedMeters;

  /// The threshold [rawMeters] was measured against, so a reading that was
  /// rejected can be re-checked against the rule that rejected it rather
  /// than against a constant that may since have changed.
  final double noiseFloorMeters;

  /// Average speed across the segment, km/h. Zero when no time elapsed.
  final double speedKmh;

  const MeterFixVerdict({
    required this.outcome,
    this.seconds = 0,
    this.rawMeters = 0,
    this.countedMeters = 0,
    this.noiseFloorMeters = 0,
    this.speedKmh = 0,
  });

  /// The distance this fix measured and the meter then threw away.
  double get discardedMeters => rawMeters - countedMeters;

  /// Whether a real displacement was measured and then not billed. Used by
  /// the diagnostic summary to separate "the GPS saw nothing" from "the GPS
  /// saw something and we dropped it", which look identical in a total.
  bool get isDiscardedDistance =>
      discardedMeters > 0 &&
      (outcome == MeterFixOutcome.belowNoiseFloor ||
          outcome == MeterFixOutcome.belowWaitingSpeed ||
          outcome == MeterFixOutcome.accuracyTooPoor ||
          outcome == MeterFixOutcome.implausible ||
          outcome == MeterFixOutcome.pauseBoundary);

  @override
  String toString() =>
      'MeterFixVerdict(${outcome.name}, ${seconds}s, '
      'raw ${rawMeters.toStringAsFixed(1)}m, '
      'counted ${countedMeters.toStringAsFixed(1)}m, '
      'floor ${noiseFloorMeters.toStringAsFixed(1)}m, '
      '${speedKmh.toStringAsFixed(1)}km/h)';
}
