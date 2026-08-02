// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/meter/fare_calc.dart';

void main() {
  test('computeFareMnt multiplies tariff by kilometers', () {
    expect(computeFareMnt(mntPerKm: 500, distanceMeters: 3000), 1500);
  });

  test('computeFareMnt charges the kilometre figure the receipt prints, so '
      'the printed arithmetic can be checked', () {
    // 1234m reads as «1.2 км» on every screen, and 1.2 × 1000 is 1200₮.
    // Before v0.4.0 this returned 1234₮ — the display rounded and the fare
    // did not, so a receipt said «1.2 км × 1 000 ₮/км» and then asked for
    // 1 234₮ beside it. A passenger who checks that is told the meter is
    // wrong; a passenger who does not check has learned nothing.
    expect(computeFareMnt(mntPerKm: 1000, distanceMeters: 1234), 1200);
  });

  test('the rounding is to the nearest tenth, not downwards', () {
    // 1250m -> 1.3 км, not 1.2: the driver is not shaved on every trip.
    expect(computeFareMnt(mntPerKm: 1000, distanceMeters: 1250), 1300);
    expect(billedKm(1249), 1.2);
    expect(billedKm(1250), 1.3);
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
    // Distance part: 900 × 1.2 км = 1080₮ (1234m bills as the 1.2 km the
    // receipt prints — see `billedKm`).
    // Waiting part:  100 × 10 / 60 = 16.66… → 17₮.
    // Summed as two already-rounded rows, so the breakdown a passenger
    // reads adds up to the total they are asked for.
    expect(
      computeTotalFareMnt(
        mntPerKm: 900,
        distanceMeters: 1234,
        mntPerMinute: 100,
        waitingSeconds: 10,
      ),
      1097,
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
