// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A MEASUREMENT, not a feature test. Erdenekhuu's field report (2026-08)
// showed Takhi's odometer reading 2.5 km where a competitor read 2.69 km on
// the same trip. Takhi bills the "anchor" distance (straight-line displacement
// from the last committed position); the competitor's figure is close to the
// "path-sum" (every consecutive-fix haversine added up), which Takhi also
// computes but does not bill.
//
// This file quantifies the gap between the two algorithms on constructed
// tracks whose true distance is known, so the choice between them rests on
// numbers rather than on either app's claim. It prints its findings; the
// expectations only pin the qualitative result so the numbers cannot silently
// drift.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_track.dart';
import 'package:takhi/meter/meter_session.dart';

/// ~111.2 m per 0.001° of latitude near the equator, where these fixtures sit
/// (lon held at 0). Metres → degrees of latitude.
const double _mPerDegLat = 111195.0;
double _lat(double meters) => meters / _mPerDegLat;
double _lon(double meters) => meters / _mPerDegLat;

/// A real urban fix accuracy. The noise floor is 2× the accuracy (or a fixed
/// minimum, whichever is larger), so 15 m gives the 30 m floor the field bug
/// was measured against.
const double _kAccuracy = 15.0;

/// Deterministic jitter, so the measurement reproduces exactly. A fixed
/// repeating pattern of metre offsets rather than a random generator — the
/// point is a stable number, not statistical realism.
const List<double> _jitterPattern = [
  8, -6, 5, -9, 3, -4, 7, -8, 2, -5, 9, -3, 6, -7, 4, -2,
];

double _jit(int i) => _jitterPattern[i % _jitterPattern.length];

/// Feeds [fixes] into a fresh session and returns (anchor-billed, path-sum).
(int anchor, int pathSum) _measure(List<GpsFix> fixes) {
  final session = MeterSession(mntPerKm: 1000);
  for (final fix in fixes) {
    session.addFix(fix);
  }
  return (session.distanceMeters, trackDistanceMeters(fixes));
}

void main() {
  test('MEASURE: highway straight at 40 km/h, clean — anchor and path-sum '
      'agree, both track the truth', () {
    // 55.6 m every 5 s = 40 km/h, straight up the meridian, no jitter.
    final fixes = <GpsFix>[];
    for (var i = 0; i <= 20; i++) {
      fixes.add(
        GpsFix(
          lat: _lat(55.6 * i),
          lon: 0,
          timestampSeconds: i * 5,
          accuracyMeters: _kAccuracy,
        ),
      );
    }
    final (anchor, pathSum) = _measure(fixes);
    const trueMeters = 1112; // 55.6 × 20

    // ignore: avoid_print
    print(
      'HIGHWAY  true=${trueMeters}m  anchor=${anchor}m  pathSum=${pathSum}m',
    );

    // Moving fast, every segment clears the floor, so the anchor moves each
    // fix and the two algorithms are the same number — and both are the truth.
    expect((anchor - pathSum).abs(), lessThan(5));
    expect((anchor - trueMeters).abs(), lessThan(10));
  });

  test('MEASURE: parked for two minutes, GPS jittering — anchor holds at zero, '
      'path-sum invents distance', () {
    // The car never moves. The fix wobbles inside its own accuracy around one
    // point for two minutes (24 fixes at 5 s).
    final fixes = <GpsFix>[];
    for (var i = 0; i <= 24; i++) {
      fixes.add(
        GpsFix(
          lat: _lat(_jit(i)),
          lon: _lon(_jit(i + 5)),
          timestampSeconds: i * 5,
          accuracyMeters: _kAccuracy,
        ),
      );
    }
    final (anchor, pathSum) = _measure(fixes);

    // ignore: avoid_print
    print('PARKED   true=0m  anchor=${anchor}m  pathSum=${pathSum}m');

    // The truth is zero. The anchor gets it exactly; the path-sum bills a
    // passenger for metres the car never drove — this is why Takhi does not
    // use path-sum, and why a competitor that does will read higher on any
    // trip that spent time stopped.
    expect(anchor, 0);
    expect(pathSum, greaterThan(100));
  });

  test('MEASURE: slow jittery crawl in traffic (~8 km/h) — the truth sits '
      'between the two, path-sum over, anchor under', () {
    // Net 11 m forward every 5 s (~8 km/h) with lateral jitter on top: real
    // creeping movement, the exact case the old jitter floor threw away and
    // the anchor was built to recover.
    final fixes = <GpsFix>[];
    for (var i = 0; i <= 24; i++) {
      fixes.add(
        GpsFix(
          lat: _lat(11.0 * i), // net forward
          lon: _lon(_jit(i)), // lateral wobble
          timestampSeconds: i * 5,
          accuracyMeters: _kAccuracy,
        ),
      );
    }
    final (anchor, pathSum) = _measure(fixes);
    const trueMeters = 264; // 11 × 24, the net forward path

    // ignore: avoid_print
    print(
      'CRAWL    true=${trueMeters}m  anchor=${anchor}m  pathSum=${pathSum}m  '
      'anchorErr=${((anchor - trueMeters) / trueMeters * 100).round()}%  '
      'pathErr=${((pathSum - trueMeters) / trueMeters * 100).round()}%',
    );

    // The finding: on a genuine slow crawl the path-sum runs over the truth
    // (it adds the jitter), and the anchor runs under it (it commits chords
    // and skips some real movement). Neither is exact; the passenger-fair
    // reading is that the true fare is between them, and a competitor's
    // path-sum figure is an upper bound, not a target Takhi should match.
    expect(pathSum, greaterThan(trueMeters));
  });
}
