// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The third rate: whole trip duration, billed per minute, on top of the
// distance and the stopped-time charges.
//
// The overlap with the stopped-time rate is INTENTIONAL and was confirmed
// by the app's author on 2026-08-01 after being asked directly. A driver
// who fills in both charges stopped time twice, because stopped seconds
// are part of the trip's duration as well. These tests pin that down so a
// later reader does not "fix" it.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/meter_session.dart';

const double _kMetreInDegrees = 1 / 111320.0;

GpsFix _fix({required int t, double northMetres = 0, double accuracy = 5}) =>
    GpsFix(
      lat: 47.9188 + northMetres * _kMetreInDegrees,
      lon: 106.9176,
      timestampSeconds: t,
      accuracyMeters: accuracy,
    );

void main() {
  group('computeDurationFareMnt', () {
    test('bills a whole minute at the rate', () {
      expect(
        computeDurationFareMnt(mntPerMinute: 100, durationSeconds: 60),
        100,
      );
    });

    test('prorates part-minutes by the second, so the running total never '
        'leaps while a passenger is watching it', () {
      expect(
        computeDurationFareMnt(mntPerMinute: 100, durationSeconds: 30),
        50,
      );
      expect(computeDurationFareMnt(mntPerMinute: 100, durationSeconds: 1), 2);
    });

    test('an unset rate charges nothing at all', () {
      expect(computeDurationFareMnt(mntPerMinute: 0, durationSeconds: 3600), 0);
    });
  });

  group('the three rates are independent', () {
    test('a driver who sets only the km rate is billed only for distance', () {
      final session = MeterSession(mntPerKm: 2000);
      for (var i = 0; i <= 12; i++) {
        session.addFix(_fix(t: i * 5, northMetres: i * 40.0));
      }
      expect(session.waitingFareMnt, 0);
      expect(session.durationFareMnt, 0);
      expect(session.fareMnt, session.distanceFareMnt);
    });

    test(
      'a driver who sets only the duration rate is billed only for time',
      () {
        final session = MeterSession(
          mntPerKm: 0,
          durationTariffMntPerMinute: 120,
        );
        for (var i = 0; i <= 12; i++) {
          session.addFix(_fix(t: i * 5, northMetres: i * 40.0));
        }
        // A minute of trip at 120₮/min.
        expect(session.durationSeconds, 60);
        expect(session.durationFareMnt, 120);
        expect(session.distanceFareMnt, 0);
        expect(session.fareMnt, 120);
      },
    );

    test('a driver who sets all three is charged all three, stopped time '
        'counted under BOTH time rates -- confirmed intentional', () {
      final session = MeterSession(
        mntPerKm: 2000,
        waitTariffMntPerMinute: 60,
        durationTariffMntPerMinute: 30,
      );
      // Fixes every 5s for a minute. The first 30s drives 40m per step
      // (240m); the last 30s sits still at 240m, drifting 6m -- inside the
      // noise floor for a +/-8m fix, so it reads as stopped.
      for (var i = 0; i <= 6; i++) {
        session.addFix(_fix(t: i * 5, northMetres: i * 40.0));
      }
      for (var i = 7; i <= 12; i++) {
        session.addFix(
          _fix(t: i * 5, northMetres: 240 + (i.isEven ? 0 : 6), accuracy: 8),
        );
      }

      expect(session.durationSeconds, 60);
      expect(session.waitingSeconds, 30);

      // The stopped 30s is billed by the jam rate...
      expect(session.waitingFareMnt, 30);
      // ...and again inside the full 60s of trip duration.
      expect(session.durationFareMnt, 30);
      expect(
        session.fareMnt,
        session.distanceFareMnt +
            session.waitingFareMnt +
            session.durationFareMnt,
        reason: 'the rows a passenger reads must add up to what they pay',
      );
    });
  });

  group('duration covers the whole trip, not just the moving part', () {
    test('a trip that is entirely stationary still accrues duration', () {
      final session = MeterSession(
        mntPerKm: 2000,
        durationTariffMntPerMinute: 60,
      );
      for (var i = 0; i <= 24; i++) {
        session.addFix(
          _fix(t: i * 5, northMetres: i.isEven ? 0 : 6, accuracy: 8),
        );
      }
      expect(session.distanceMeters, 0);
      expect(session.durationSeconds, 120);
      expect(session.durationFareMnt, 120);
    });
  });

  group('every rate left empty means that component is simply not charged', () {
    test('the default session charges neither time rate', () {
      final session = MeterSession(mntPerKm: 1500);
      expect(session.waitTariffMntPerMinute, 0);
      expect(session.durationTariffMntPerMinute, 0);
    });
  });
}
