// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/meter/fare_calc.dart';

void main() {
  test('computeFareMnt multiplies tariff by kilometers', () {
    expect(computeFareMnt(mntPerKm: 500, distanceMeters: 3000), 1500);
  });

  test('computeFareMnt rounds to the nearest төгрөг', () {
    expect(computeFareMnt(mntPerKm: 1000, distanceMeters: 1234), 1234);
  });

  test('computeFareMnt is zero at zero distance', () {
    expect(computeFareMnt(mntPerKm: 900, distanceMeters: 0), 0);
  });

  test('estimateFareMntOffline applies the urban-inflation factor', () {
    expect(
      estimateFareMntOffline(
        mntPerKm: 1000,
        straightLineDistanceMeters: 10000,
        urbanFactor: 1.35,
      ),
      13500,
    );
  });

  test('estimateFareMntOffline defaults urbanFactor to 1.35', () {
    expect(
      estimateFareMntOffline(mntPerKm: 1000, straightLineDistanceMeters: 10000),
      13500,
    );
  });

  test('computeWaitingFareMnt charges a whole minute at the minute rate', () {
    expect(computeWaitingFareMnt(mntPerMinute: 300, waitingSeconds: 60), 300);
  });

  test('computeWaitingFareMnt charges a part-minute proportionally, by the '
      'second', () {
    expect(computeWaitingFareMnt(mntPerMinute: 300, waitingSeconds: 30), 150);
    expect(computeWaitingFareMnt(mntPerMinute: 300, waitingSeconds: 90), 450);
  });

  test('computeWaitingFareMnt rounds to the nearest төгрөг', () {
    // 100 × 10 / 60 = 16.66… ₮
    expect(computeWaitingFareMnt(mntPerMinute: 100, waitingSeconds: 10), 17);
  });

  test('computeWaitingFareMnt is zero for a driver who charges no waiting '
      'rate', () {
    expect(computeWaitingFareMnt(mntPerMinute: 0, waitingSeconds: 3600), 0);
  });

  test('computeWaitingFareMnt is zero before any waiting has accrued', () {
    expect(computeWaitingFareMnt(mntPerMinute: 300, waitingSeconds: 0), 0);
  });

  test('computeTotalFareMnt is the sum of the two rounded parts, so a shown '
      'breakdown always adds up to the shown total', () {
    // Distance part: 900 × 1234 / 1000 = 1110.6 → 1111₮.
    // Waiting part:  100 × 10 / 60     =   16.66… →  17₮.
    // Summing first and rounding once would give 1127₮ — one төгрөг less
    // than the two rows a passenger can read off the screen.
    expect(
      computeTotalFareMnt(
        mntPerKm: 900,
        distanceMeters: 1234,
        mntPerMinute: 100,
        waitingSeconds: 10,
      ),
      1128,
    );
  });

  test('computeTotalFareMnt equals the distance fare alone when nothing was '
      'waited', () {
    expect(
      computeTotalFareMnt(
        mntPerKm: 1000,
        distanceMeters: 3000,
        mntPerMinute: 300,
        waitingSeconds: 0,
      ),
      computeFareMnt(mntPerKm: 1000, distanceMeters: 3000),
    );
  });

  // The 5 km/h waiting-speed threshold that used to be asserted here was
  // retired in v0.4.0. It was the second of two per-segment filters that
  // each discarded a segment's distance permanently, and between them they
  // cost a real driver a quarter of a measured ride. `MeterSession` now
  // decides travel-versus-waiting against an anchor, and
  // `meter_session_test.dart` owns that boundary.
}
