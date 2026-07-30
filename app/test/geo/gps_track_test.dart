// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_track.dart';

void main() {
  test(
    'haversineMeters: one degree of longitude at the equator is ~111.19km',
    () {
      final d = haversineMeters(0, 0, 0, 1);
      expect(d, closeTo(111194.9, 1.0));
    },
  );

  test('haversineMeters: same point is zero distance', () {
    expect(haversineMeters(47.9186, 106.9176, 47.9186, 106.9176), 0);
  });

  test('trackDistanceMeters sums consecutive-fix distances', () {
    final fixes = [
      const GpsFix(lat: 0, lon: 0, timestampSeconds: 0),
      const GpsFix(lat: 0, lon: 1, timestampSeconds: 60),
      const GpsFix(lat: 0, lon: 2, timestampSeconds: 120),
    ];
    // Two equal ~111,195m legs.
    expect(trackDistanceMeters(fixes), closeTo(222390, 4));
  });

  test('trackDistanceMeters is zero for fewer than 2 fixes', () {
    expect(trackDistanceMeters([]), 0);
    expect(
      trackDistanceMeters([const GpsFix(lat: 0, lon: 0, timestampSeconds: 0)]),
      0,
    );
  });

  test('trackDurationSeconds is last minus first timestamp', () {
    final fixes = [
      const GpsFix(lat: 0, lon: 0, timestampSeconds: 100),
      const GpsFix(lat: 0, lon: 0, timestampSeconds: 250),
    ];
    expect(trackDurationSeconds(fixes), 150);
  });

  test('trackDurationSeconds is zero for fewer than 2 fixes', () {
    expect(trackDurationSeconds([]), 0);
  });

  test('GpsTrackAccumulator exposes a growing, unmodifiable fix list', () {
    final acc = GpsTrackAccumulator();
    acc.addFix(const GpsFix(lat: 0, lon: 0, timestampSeconds: 0));
    acc.addFix(const GpsFix(lat: 0, lon: 1, timestampSeconds: 60));
    expect(acc.fixes.length, 2);
    expect(
      () => acc.fixes.add(const GpsFix(lat: 0, lon: 0, timestampSeconds: 0)),
      throwsUnsupportedError,
    );
    expect(acc.distanceMeters, closeTo(111195, 2));
    expect(acc.durationSeconds, 60);
  });

  test('segmentSpeedKmh derives speed from the distance and elapsed time '
      'between two fixes', () {
    // 0.001° of latitude is ~111.2 m; covering it in 10 s is ~40 km/h.
    expect(
      segmentSpeedKmh(
        const GpsFix(lat: 0, lon: 0, timestampSeconds: 0),
        const GpsFix(lat: 0.001, lon: 0, timestampSeconds: 10),
      ),
      closeTo(40.0, 0.1),
    );
  });

  test('segmentSpeedKmh reports the small speed of a parked vehicle whose '
      'fixes only jitter', () {
    // ~2.2 m of GPS drift over 10 s — under 1 km/h.
    expect(
      segmentSpeedKmh(
        const GpsFix(lat: 0, lon: 0, timestampSeconds: 0),
        const GpsFix(lat: 0.00002, lon: 0, timestampSeconds: 10),
      ),
      closeTo(0.8, 0.05),
    );
  });

  test('segmentSpeedKmh is zero when no time separates the two fixes', () {
    expect(
      segmentSpeedKmh(
        const GpsFix(lat: 0, lon: 0, timestampSeconds: 30),
        const GpsFix(lat: 0.001, lon: 0, timestampSeconds: 30),
      ),
      0,
    );
  });

  test('segmentSpeedKmh is zero when the second fix predates the first', () {
    expect(
      segmentSpeedKmh(
        const GpsFix(lat: 0, lon: 0, timestampSeconds: 30),
        const GpsFix(lat: 0.001, lon: 0, timestampSeconds: 20),
      ),
      0,
    );
  });
}
