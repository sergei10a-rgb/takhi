// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The minimum fare is the sixth rate a driver may set: the least they will
// run the meter for. It is applied as a visible top-up, never by silently
// flooring the total, so the fare's rows still add up to the number paid —
// the invariant the whole meter is built around. These tests pin both the
// arithmetic and that invariant.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/meter_run_snapshot.dart';
import 'package:takhi/meter/meter_session.dart';
import 'package:takhi/meter/tariff_store.dart';

const double _kMetreInDegrees = 1 / 111320.0;

GpsFix _fix({required int t, double northMetres = 0}) => GpsFix(
  lat: 47.9188 + northMetres * _kMetreInDegrees,
  lon: 106.9176,
  timestampSeconds: t,
  accuracyMeters: 5,
);

void main() {
  group('minimumFareTopUpMnt', () {
    test('is zero when no floor is set', () {
      expect(minimumFareTopUpMnt(minFareMnt: 0, fareBeforeMinimumMnt: 500), 0);
    });

    test('is zero when the metered charges already clear the floor', () {
      expect(
        minimumFareTopUpMnt(minFareMnt: 2000, fareBeforeMinimumMnt: 2500),
        0,
      );
    });

    test('lifts a short fare exactly up to the floor', () {
      expect(
        minimumFareTopUpMnt(minFareMnt: 2000, fareBeforeMinimumMnt: 1200),
        800,
      );
    });

    test('a fare exactly on the floor needs no top-up', () {
      expect(
        minimumFareTopUpMnt(minFareMnt: 2000, fareBeforeMinimumMnt: 2000),
        0,
      );
    });
  });

  group('MeterSession minimum fare', () {
    test('a short run is lifted to the floor, and the rows still sum', () {
      // 1000₮/km. ~450m of travel is under half a km, so distance bills
      // 0.5km × 1000 = 500₮ (billedKm rounds to the tenth). Floor 2000₮.
      final meter = MeterSession(mntPerKm: 1000, minFareMnt: 2000)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 30, northMetres: 450));
      expect(meter.fareMnt, 2000);
      expect(meter.minFareTopUpMnt, greaterThan(0));
      // The invariant: boarding + distance + waiting + duration + top-up.
      expect(
        meter.boardingFareMnt +
            meter.distanceFareMnt +
            meter.waitingFareMnt +
            meter.durationFareMnt +
            meter.minFareTopUpMnt,
        meter.fareMnt,
      );
    });

    test('a long run past the floor charges the meter, no top-up', () {
      final meter = MeterSession(mntPerKm: 1000, minFareMnt: 2000)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 120, northMetres: 3000));
      expect(meter.fareMnt, greaterThan(2000));
      expect(meter.minFareTopUpMnt, 0);
    });

    test('no floor behaves exactly as before the rate existed', () {
      final floored = MeterSession(mntPerKm: 1000, minFareMnt: 0)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 30, northMetres: 450));
      final plain = MeterSession(mntPerKm: 1000)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 30, northMetres: 450));
      expect(floored.fareMnt, plain.fareMnt);
      expect(floored.minFareTopUpMnt, 0);
    });

    test('the floor survives a snapshot round-trip', () {
      final snapshot = MeterRunSnapshot(
        mntPerKm: 1000,
        waitTariffMntPerMinute: 0,
        durationTariffMntPerMinute: 0,
        startedAtSeconds: 0,
        distanceMeters: 200,
        waitingSeconds: 0,
        billableDurationSeconds: 0,
        pausedSeconds: 0,
        isPaused: false,
        lastFixSeconds: 0,
        minFareMnt: 2000,
      );
      final restored = MeterRunSnapshot.decode(snapshot.encode());
      expect(restored?.minFareMnt, 2000);
      final meter = MeterSession.resumed(snapshot);
      expect(meter.minFareMnt, 2000);
      expect(meter.fareMnt, 2000); // 200m ≈ 200₮ distance, floored to 2000
    });
  });

  group('DriverTariff minFareMnt', () {
    test(
      'defaults to zero and round-trips through the in-memory store',
      () async {
        const tariff = DriverTariff(mntPerKm: 1500, minFareMnt: 2500);
        final store = InMemoryTariffStore();
        await store.save(tariff);
        final loaded = await store.load();
        expect(loaded?.minFareMnt, 2500);
        expect(const DriverTariff(mntPerKm: 1500).minFareMnt, 0);
      },
    );

    test('is part of value equality', () {
      expect(
        const DriverTariff(mntPerKm: 1500, minFareMnt: 2000),
        isNot(const DriverTariff(mntPerKm: 1500, minFareMnt: 3000)),
      );
      expect(
        const DriverTariff(mntPerKm: 1500, minFareMnt: 2000),
        const DriverTariff(mntPerKm: 1500, minFareMnt: 2000),
      );
    });
  });
}
