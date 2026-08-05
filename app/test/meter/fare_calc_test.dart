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

  group('free distance allowance', () {
    test('distance under the free allowance is not charged at all', () {
      // 800m ridden, first 1000m free -> nothing on the distance line.
      expect(
        computeFareMnt(
          mntPerKm: 1500,
          distanceMeters: 800,
          freeDistanceMeters: 1000,
        ),
        0,
      );
    });

    test('only the distance beyond the free allowance is billed', () {
      // 3000m ridden, first 1000m free -> 2.0 km billed × 1500 = 3000₮.
      expect(
        computeFareMnt(
          mntPerKm: 1500,
          distanceMeters: 3000,
          freeDistanceMeters: 1000,
        ),
        3000,
      );
    });

    test('exactly the free allowance is the boundary: nothing billed', () {
      expect(
        computeFareMnt(
          mntPerKm: 1500,
          distanceMeters: 1000,
          freeDistanceMeters: 1000,
        ),
        0,
      );
    });

    test('the default is zero free metres — billed from the first metre', () {
      expect(computeFareMnt(mntPerKm: 1500, distanceMeters: 3000), 4500);
    });
  });

  group('free duration allowance', () {
    test('duration under the free allowance is not charged', () {
      expect(
        computeDurationFareMnt(
          mntPerMinute: 120,
          durationSeconds: 30,
          freeDurationSeconds: 60,
        ),
        0,
      );
    });

    test('only the seconds beyond the free allowance are billed', () {
      // 180s ridden, first 60s free -> 120s × 120/60 = 240₮.
      expect(
        computeDurationFareMnt(
          mntPerMinute: 120,
          durationSeconds: 180,
          freeDurationSeconds: 60,
        ),
        240,
      );
    });

    test('the default is zero free seconds — billed from the first second', () {
      expect(
        computeDurationFareMnt(mntPerMinute: 120, durationSeconds: 120),
        240,
      );
    });
  });

  test('computeTotalFareMnt threads both free allowances into their rows', () {
    // Distance: 3000m, 1000m free -> 2.0km × 1500 = 3000. Duration: 180s,
    // 60s free -> 120s × 100/60 = 200. Waiting: 0. Total 3200.
    expect(
      computeTotalFareMnt(
        mntPerKm: 1500,
        distanceMeters: 3000,
        mntPerMinute: 300,
        waitingSeconds: 0,
        durationMntPerMinute: 100,
        durationSeconds: 180,
        freeDistanceMeters: 1000,
        freeDurationSeconds: 60,
      ),
      3200,
    );
  });

  group('free waiting grace', () {
    test('waiting under the grace is not charged', () {
      expect(
        computeWaitingFareMnt(
          mntPerMinute: 300,
          waitingSeconds: 90,
          freeWaitingSeconds: 120,
        ),
        0,
      );
    });

    test('only the waiting past the grace is billed', () {
      // 180s waited, first 120 free -> 60s × 300/60 = 300₮.
      expect(
        computeWaitingFareMnt(
          mntPerMinute: 300,
          waitingSeconds: 180,
          freeWaitingSeconds: 120,
        ),
        300,
      );
    });

    test('exactly the grace is the boundary: nothing billed', () {
      expect(
        computeWaitingFareMnt(
          mntPerMinute: 300,
          waitingSeconds: 120,
          freeWaitingSeconds: 120,
        ),
        0,
      );
    });

    test('the default is zero grace — billed from the first second', () {
      expect(computeWaitingFareMnt(mntPerMinute: 300, waitingSeconds: 60), 300);
    });

    test('the network-wide grace is a positive whole minute-ish', () {
      expect(kFreeWaitingSeconds, greaterThan(0));
    });
  });

  test('computeTotalFareMnt threads the free waiting grace into its row', () {
    // Waiting: 180s, 120 free -> 60s × 300/60 = 300; nothing else set.
    expect(
      computeTotalFareMnt(
        mntPerKm: 1000,
        distanceMeters: 0,
        mntPerMinute: 300,
        waitingSeconds: 180,
        freeWaitingSeconds: 120,
      ),
      300,
    );
  });
}
