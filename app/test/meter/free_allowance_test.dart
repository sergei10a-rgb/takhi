// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The free distance and time allowances fold a short opening stretch into
// the base fare: the km- and duration-tariffs bill only what is beyond them.
// They add no row — they shrink the distance and duration shares — so the
// breakdown still sums to the total, the invariant the whole meter is built
// around. These tests pin the arithmetic, that invariant, persistence across
// a crash, and that a zero allowance is exactly the meter before it existed.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
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
  group('MeterSession free distance', () {
    test('distance within the free allowance is not billed', () {
      // ~800m travelled, first 1000m free -> nothing on the distance line.
      final meter = MeterSession(mntPerKm: 1500, freeDistanceMeters: 1000)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 60, northMetres: 800));
      expect(meter.distanceMeters, greaterThan(0));
      expect(meter.distanceFareMnt, 0);
      expect(meter.fareMnt, 0);
    });

    test('only the distance beyond the allowance is billed', () {
      // ~3000m travelled, first 1000m free -> ~2.0km × 1500 = 3000₮.
      final meter = MeterSession(mntPerKm: 1500, freeDistanceMeters: 1000)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 120, northMetres: 3000));
      expect(meter.distanceFareMnt, 3000);
    });

    test('a zero allowance bills exactly as before the rate existed', () {
      final free = MeterSession(mntPerKm: 1500, freeDistanceMeters: 0)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 120, northMetres: 3000));
      final plain = MeterSession(mntPerKm: 1500)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 120, northMetres: 3000));
      expect(free.distanceFareMnt, plain.distanceFareMnt);
    });
  });

  group('MeterSession free duration', () {
    test('time within the allowance is left off the duration line', () {
      // One 120s segment, first 60s free -> 60s billed × 100/60 = 100₮.
      final meter =
          MeterSession(
              mntPerKm: 1500,
              durationTariffMntPerMinute: 100,
              freeDurationSeconds: 60,
            )
            ..addFix(_fix(t: 0))
            ..addFix(_fix(t: 120, northMetres: 3000));
      expect(meter.billableDurationSeconds, 120);
      expect(meter.durationFareMnt, 100);
    });

    test('a zero allowance bills the whole duration as before', () {
      final meter =
          MeterSession(mntPerKm: 1500, durationTariffMntPerMinute: 100)
            ..addFix(_fix(t: 0))
            ..addFix(_fix(t: 120, northMetres: 3000));
      expect(meter.durationFareMnt, 200);
    });
  });

  test('both allowances still leave the breakdown summing to the total', () {
    final meter =
        MeterSession(
            mntPerKm: 1500,
            durationTariffMntPerMinute: 100,
            boardingMnt: 500,
            freeDistanceMeters: 1000,
            freeDurationSeconds: 60,
          )
          ..addFix(_fix(t: 0))
          ..addFix(_fix(t: 120, northMetres: 3000));
    expect(
      meter.boardingFareMnt +
          meter.distanceFareMnt +
          meter.waitingFareMnt +
          meter.durationFareMnt +
          meter.minFareTopUpMnt,
      meter.fareMnt,
    );
  });

  test('a free distance shrinks the metered charge a min-fare then tops up', () {
    // 3000m at 1500/km is 4500₮ on its own; 2000m free leaves the metered
    // charge at 1500₮, so a 2000₮ floor tops up, and the rows still sum.
    final meter =
        MeterSession(
            mntPerKm: 1500,
            freeDistanceMeters: 2000,
            minFareMnt: 2000,
          )
          ..addFix(_fix(t: 0))
          ..addFix(_fix(t: 120, northMetres: 3000));
    expect(meter.distanceFareMnt, 1500); // (3000-2000) ≈ 1.0km × 1500
    expect(meter.fareMnt, 2000);
    expect(meter.minFareTopUpMnt, 500);
    expect(meter.distanceFareMnt + meter.minFareTopUpMnt, meter.fareMnt);
  });

  group('snapshot round-trip', () {
    test('preserves both allowances and re-applies them on resume', () {
      final snapshot = MeterRunSnapshot(
        mntPerKm: 1500,
        waitTariffMntPerMinute: 0,
        durationTariffMntPerMinute: 100,
        startedAtSeconds: 0,
        distanceMeters: 3000,
        waitingSeconds: 0,
        billableDurationSeconds: 120,
        pausedSeconds: 0,
        isPaused: false,
        lastFixSeconds: 0,
        freeDistanceMeters: 1000,
        freeDurationSeconds: 60,
      );
      final restored = MeterRunSnapshot.decode(snapshot.encode());
      expect(restored?.freeDistanceMeters, 1000);
      expect(restored?.freeDurationSeconds, 60);
      final meter = MeterSession.resumed(snapshot);
      expect(meter.freeDistanceMeters, 1000);
      expect(meter.freeDurationSeconds, 60);
      // 3000m, 1000m free -> 2.0km × 1500 = 3000; 120-60=60s × 100/60 = 100.
      expect(meter.distanceFareMnt, 3000);
      expect(meter.durationFareMnt, 100);
    });

    test('defaults both to zero for a snapshot written before they existed', () {
      final snapshot = MeterRunSnapshot(
        mntPerKm: 1500,
        waitTariffMntPerMinute: 0,
        durationTariffMntPerMinute: 0,
        startedAtSeconds: 0,
        distanceMeters: 0,
        waitingSeconds: 0,
        billableDurationSeconds: 0,
        pausedSeconds: 0,
        isPaused: false,
        lastFixSeconds: 0,
      );
      final restored = MeterRunSnapshot.decode(snapshot.encode());
      expect(restored?.freeDistanceMeters, 0);
      expect(restored?.freeDurationSeconds, 0);
    });
  });

  group('DriverTariff free allowances', () {
    test('default to zero and round-trip through the store', () async {
      const tariff = DriverTariff(
        mntPerKm: 1500,
        freeDistanceMeters: 500,
        freeDurationSeconds: 120,
      );
      final store = InMemoryTariffStore();
      await store.save(tariff);
      final loaded = await store.load();
      expect(loaded?.freeDistanceMeters, 500);
      expect(loaded?.freeDurationSeconds, 120);
      expect(const DriverTariff(mntPerKm: 1500).freeDistanceMeters, 0);
      expect(const DriverTariff(mntPerKm: 1500).freeDurationSeconds, 0);
    });

    test('are part of value equality', () {
      expect(
        const DriverTariff(mntPerKm: 1500, freeDistanceMeters: 500),
        isNot(const DriverTariff(mntPerKm: 1500, freeDistanceMeters: 600)),
      );
      expect(
        const DriverTariff(mntPerKm: 1500, freeDurationSeconds: 60),
        isNot(const DriverTariff(mntPerKm: 1500, freeDurationSeconds: 120)),
      );
      expect(
        const DriverTariff(
          mntPerKm: 1500,
          freeDistanceMeters: 500,
          freeDurationSeconds: 60,
        ),
        const DriverTariff(
          mntPerKm: 1500,
          freeDistanceMeters: 500,
          freeDurationSeconds: 60,
        ),
      );
    });
  });
}
