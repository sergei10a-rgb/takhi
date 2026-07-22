// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/meter_session.dart';

void main() {
  test('MeterSession accumulates distance/duration/fare from fed fixes', () {
    final session = MeterSession(mntPerKm: 1000);
    session.addFix(const GpsFix(lat: 0, lon: 0, timestampSeconds: 0));
    session.addFix(const GpsFix(lat: 0, lon: 1, timestampSeconds: 60));
    expect(session.distanceMeters, closeTo(111195, 2));
    expect(session.durationSeconds, 60);
    expect(session.fareMnt, closeTo(111195, 2));
  });

  test('MeterSession starts at zero before any fix', () {
    final session = MeterSession(mntPerKm: 500);
    expect(session.distanceMeters, 0);
    expect(session.durationSeconds, 0);
    expect(session.fareMnt, 0);
  });
}
