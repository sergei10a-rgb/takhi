// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A parked taxi must not run up a fare. This file is about money coming
// off a passenger who has no way to audit it, so the boundaries are tested
// from both sides: drift must never bill as distance, and a car genuinely
// crawling in traffic must never be written off as drift.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_jitter.dart';
import 'package:takhi/meter/meter_session.dart';

/// Roughly a metre of latitude, at Ulaanbaatar's latitude.
const double _kMetreInDegrees = 1 / 111320.0;

GpsFix _fix({required int t, double northMetres = 0, double? accuracy = 5}) =>
    GpsFix(
      lat: 47.9188 + northMetres * _kMetreInDegrees,
      lon: 106.9176,
      timestampSeconds: t,
      accuracyMeters: accuracy,
    );

void main() {
  group('a stationary car', () {
    test('drift of a few metres between good fixes is not travel', () {
      // 6m in 5s is 4.3 km/h -- under the 5 km/h waiting threshold, so the
      // old speed test caught this one.
      expect(
        classifyMovement(_fix(t: 0), _fix(t: 5, northMetres: 6)),
        GpsMovement.stationary,
      );
    });

    test('drift JUST over the old speed threshold is still not travel', () {
      // 7.5m in 5s is 5.4 km/h -- over the threshold, so the old code
      // billed this as distance. This is the exact overcharge reported
      // from the phone: a parked car quietly accumulating metres.
      final movement = classifyMovement(
        _fix(t: 0),
        _fix(t: 5, northMetres: 7.5),
      );
      expect(
        movement,
        GpsMovement.stationary,
        reason: 'this is the case that was overcharging passengers',
      );
    });

    test('a poor fix that appears to jump 40m is judged against its own '
        'accuracy, not against a fixed distance', () {
      // ±45m accuracy: a 40m apparent move says nothing at all.
      expect(
        classifyMovement(
          _fix(t: 0, accuracy: 45),
          _fix(t: 5, northMetres: 40, accuracy: 45),
        ),
        GpsMovement.stationary,
      );
    });

    test('a fix too inaccurate to use at all is treated as standing still', () {
      expect(
        classifyMovement(
          _fix(t: 0),
          _fix(t: 5, northMetres: 500, accuracy: 150),
        ),
        GpsMovement.stationary,
      );
    });
  });

  group('a moving car', () {
    test('a car crawling in a jam is still travelling, not written off as '
        'drift', () {
      // 20m in 5s is 14.4 km/h -- slow, real, and well clear of the noise
      // floor for a good fix. Solving the jitter bug by widening the
      // waiting threshold would have swallowed exactly this.
      expect(
        classifyMovement(_fix(t: 0), _fix(t: 5, northMetres: 20)),
        GpsMovement.travelled,
      );
    });

    test('ordinary city driving is travel', () {
      // 60m in 5s = 43 km/h.
      expect(
        classifyMovement(_fix(t: 0), _fix(t: 5, northMetres: 60)),
        GpsMovement.travelled,
      );
    });

    test('one sharp fix beside one vague fix still counts real movement', () {
      // The better accuracy pins one end of the segment. Taking the worse
      // figure would reject genuine travel every time a single poor fix
      // landed mid-journey.
      expect(
        classifyMovement(
          _fix(t: 0, accuracy: 4),
          _fix(t: 5, northMetres: 30, accuracy: 40),
        ),
        GpsMovement.travelled,
      );
    });
  });

  group('a broken fix', () {
    test('a teleport faster than any taxi is refused outright', () {
      // 500m in 5s = 360 km/h.
      expect(
        classifyMovement(_fix(t: 0), _fix(t: 5, northMetres: 500)),
        GpsMovement.implausible,
      );
    });

    test('a fix that does not advance the clock cannot be movement', () {
      expect(
        classifyMovement(_fix(t: 10), _fix(t: 10, northMetres: 50)),
        GpsMovement.stationary,
      );
    });
  });

  group('the noise floor', () {
    test('never drops below the absolute floor, however confident the fix', () {
      expect(
        noiseFloorMeters(_fix(t: 0, accuracy: 1), _fix(t: 1, accuracy: 1)),
        kGpsNoiseFloorMeters,
      );
    });

    test('rises with the better of the two accuracies, scaled', () {
      expect(
        noiseFloorMeters(_fix(t: 0, accuracy: 30), _fix(t: 1, accuracy: 50)),
        30 * kAccuracyNoiseFactor,
      );
    });

    test('falls back to the floor when the platform reports no accuracy', () {
      expect(
        noiseFloorMeters(
          _fix(t: 0, accuracy: null),
          _fix(t: 1, accuracy: null),
        ),
        kGpsNoiseFloorMeters,
      );
    });
  });

  group('the meter, end to end', () {
    test('a taxi parked for five minutes bills no distance at all', () {
      final session = MeterSession(mntPerKm: 2000, waitTariffMntPerMinute: 50);
      // 60 fixes, 5s apart, wandering within what a +/-8m fix can
      // honestly wander. Several of these steps clear the old 6.9m
      // threshold, which is exactly what made a parked taxi cost money.
      const drift = [0.0, 9.0, 3.0, -7.0, 8.0, -2.0];
      for (var i = 0; i <= 60; i++) {
        session.addFix(
          _fix(t: i * 5, northMetres: drift[i % drift.length], accuracy: 8),
        );
      }

      expect(
        session.distanceMeters,
        0,
        reason: 'a parked car must not run up a distance fare',
      );
      expect(
        session.fareMnt,
        session.waitingFareMnt,
        reason: 'every төгрөг charged must come from the waiting rate',
      );
    });

    test('the trip clock still runs while parked, so the driver is paid '
        'for their time', () {
      final session = MeterSession(
        mntPerKm: 2000,
        durationTariffMntPerMinute: 60,
      );
      for (var i = 0; i <= 24; i++) {
        session.addFix(
          _fix(t: i * 5, northMetres: i.isEven ? 0 : 8, accuracy: 8),
        );
      }
      // Two minutes of standing still, charged by the trip-duration rate:
      // a jam is part of the trip. The waiting rate is for the passenger
      // keeping the driver, and only the driver can invoke it.
      expect(session.stoppedSeconds, 120);
      expect(session.distanceMeters, 0);
      expect(session.durationFareMnt, 120);
      expect(session.waitingFareMnt, 0);
    });

    test('a real journey is still measured', () {
      final session = MeterSession(mntPerKm: 2000);
      // 40m every 5s = 28.8 km/h for a minute: 480m.
      for (var i = 0; i <= 12; i++) {
        session.addFix(_fix(t: i * 5, northMetres: i * 40.0));
      }
      expect(session.distanceMeters, closeTo(480, 2));
    });

    test('a stop in the middle of a journey adds time but no distance', () {
      final session = MeterSession(mntPerKm: 2000, waitTariffMntPerMinute: 60);
      var metres = 0.0;
      var t = 0;
      // Drive 400m.
      for (var i = 0; i < 10; i++) {
        session.addFix(_fix(t: t, northMetres: metres));
        metres += 40;
        t += 5;
      }
      // The loop left `metres` one step past the last fix it actually
      // emitted. Wind it back so the car stops where it really is, rather
      // than jumping 40m the instant it parks.
      metres -= 40;
      final afterDriving = session.distanceMeters;
      // Sit at a light for a minute, jittering by up to 9m.
      for (var i = 0; i < 12; i++) {
        session.addFix(
          _fix(t: t, northMetres: metres + (i.isEven ? 0 : 9), accuracy: 8),
        );
        t += 5;
      }
      expect(
        session.distanceMeters,
        afterDriving,
        reason: 'the stop must not add a single metre',
      );
      expect(session.stoppedSeconds, greaterThanOrEqualTo(55));
    });
  });
}
