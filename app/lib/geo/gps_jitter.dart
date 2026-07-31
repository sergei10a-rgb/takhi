// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'gps_fix.dart';
import 'gps_track.dart';

/// The smallest movement this app is willing to call travel, in metres,
/// when the platform reports no accuracy at all.
///
/// A parked car is not still as far as its GPS is concerned. Sitting under
/// a windscreen in a street with buildings on both sides, consecutive fixes
/// wander several metres apart with nothing moving, and each wander is
/// indistinguishable — from the numbers alone — from a car creeping
/// forward in a queue.
///
/// 8m is chosen against the failure it has to stop rather than as a
/// tolerance for its own sake: the meter's waiting threshold is 5 km/h,
/// which over a 5-second fix interval is 6.9m, so drift only slightly
/// larger than this floor is what was being billed as distance.
const double kGpsNoiseFloorMeters = 8.0;

/// No taxi in Ulaanbaatar does this. A segment implying more is a bad fix
/// — a cell-tower fallback position, or the first reading after a tunnel —
/// not a journey, and integrating it adds hundreds of phantom metres to a
/// fare in one step.
const double kMaxPlausibleSpeedKmh = 200.0;

/// How many accuracy radii a displacement must clear before it counts as
/// movement.
///
/// Two, because a GPS accuracy figure is about a one-sigma confidence
/// radius: a fix claiming +/-5m is saying "probably within 5m", not "never
/// more than 5m out". Two independent fixes of one parked car can each be
/// well inside their stated accuracy and still sit 10m apart, and that gap
/// is exactly what was being sold to passengers as distance travelled.
///
/// It is a deliberately blunt instrument, and it has a cost worth stating:
/// a car genuinely creeping forward by less than two accuracy radii per
/// fix is billed as stopped. That lands on the passenger's side, matches
/// how `pause()` already resolves the same kind of doubt, and is the right
/// way round -- the driver loses a few metres, rather than the passenger
/// paying for a journey nobody made.
const double kAccuracyNoiseFactor = 2.0;

/// A fix this poor says almost nothing about where the car is. Accepting it
/// pollutes both the distance and the position pin; the previous fix is a
/// better estimate of the truth than this one is.
const double kMaxUsableAccuracyMeters = 100.0;

/// What the movement between two consecutive fixes actually is.
enum GpsMovement {
  /// Real travel: bill it by distance.
  travelled,

  /// Within the noise floor, or too poor a fix to tell. The time still
  /// counts — a car that is stopped is still occupying the driver — but no
  /// distance does.
  ///
  /// This is deliberately NOT "discard the fix". Dropping it would freeze
  /// the clock as well as the odometer, so a genuinely stationary car in a
  /// jam would accrue neither distance nor waiting time and the driver
  /// would be paid nothing for sitting in it.
  stationary,

  /// Physically impossible, so the fix is wrong rather than the car fast.
  /// Neither distance nor time is credited to it.
  implausible,
}

/// Classifies the segment from [from] to [to].
///
/// Pure, and takes the two fixes rather than a stream, so every boundary
/// below is testable without a device — which matters more here than
/// almost anywhere else in the app, because getting it wrong takes money
/// off a passenger who has no way to audit it.
///
/// The displacement is judged against the fixes' OWN reported accuracy, not
/// against a fixed distance. That is the whole idea: 10 metres is
/// convincing travel from a fix good to ±3m and is meaningless from one
/// good to ±40m, and a single constant cannot express both. A threshold
/// large enough to absorb the worst fixes would also swallow a car
/// genuinely crawling in traffic.
GpsMovement classifyMovement(GpsFix from, GpsFix to) {
  final seconds = to.timestampSeconds - from.timestampSeconds;
  if (seconds <= 0) return GpsMovement.stationary;

  final accuracy = to.accuracyMeters;
  if (accuracy != null && accuracy > kMaxUsableAccuracyMeters) {
    return GpsMovement.stationary;
  }

  final meters = haversineMeters(from.lat, from.lon, to.lat, to.lon);
  if (meters / seconds * 3.6 > kMaxPlausibleSpeedKmh) {
    return GpsMovement.implausible;
  }

  return meters > noiseFloorMeters(from, to)
      ? GpsMovement.travelled
      : GpsMovement.stationary;
}

/// How far the car must appear to have moved before that movement counts
/// as travel rather than as the two fixes disagreeing about one spot.
///
/// Uses the *better* of the two accuracies rather than the average or the
/// worse one. Two fixes 10m apart, one good to ±3m and one to ±30m, are
/// genuinely ambiguous — but the sharp fix pins one end of the segment, so
/// taking the worse figure would throw away the good reading and reject
/// real movement every time a single poor fix landed mid-journey.
///
/// Scaled by [kAccuracyNoiseFactor] rather than taken raw, because a
/// reported accuracy is a *confidence radius*, not a maximum error. Two
/// fixes each honestly claiming ±5m routinely land 9-10m apart with the car
/// parked -- both readings are inside their stated accuracy, and the
/// apparent movement between them is still entirely noise. Requiring the
/// displacement to clear roughly two of those radii is the difference
/// between absorbing that and billing it.
///
/// Never below [kGpsNoiseFloorMeters]: a phone reporting ±1m parked in a
/// street still drifts further than a metre, and the reported accuracy is
/// itself an estimate the platform is often optimistic about.
double noiseFloorMeters(GpsFix from, GpsFix to) {
  final a = from.accuracyMeters;
  final b = to.accuracyMeters;
  final best = switch ((a, b)) {
    (null, null) => null,
    (final x?, null) => x,
    (null, final y?) => y,
    (final x?, final y?) => math.min(x, y),
  };
  if (best == null) return kGpsNoiseFloorMeters;
  return math.max(kGpsNoiseFloorMeters, best * kAccuracyNoiseFactor);
}
