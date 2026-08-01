// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where the missing kilometres went.
//
// A driver ran Takhi beside a commercial meter on two real rides and ours
// read 26% and 13% short. These tests do two jobs: they pin the diagnostic
// that answers *why*, and — in `the shortfall, reproduced` below — they
// reproduce the shortfall itself from nothing but a plausible city drive,
// so the fix that follows has something to be measured against.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/meter_diagnostics.dart';
import 'package:takhi/meter/meter_diagnostics_report.dart';
import 'package:takhi/meter/meter_fix_verdict.dart';
import 'package:takhi/meter/meter_session.dart';

/// Metres per degree of latitude — close enough at Ulaanbaatar's latitude
/// for a test that only needs its own arithmetic to be consistent.
const double _metersPerDegreeLat = 111320.0;

const _start = GpsFix(
  lat: 47.9186,
  lon: 106.9176,
  timestampSeconds: 1000,
  accuracyMeters: 10,
);

GpsFix _north(
  GpsFix from, {
  required double meters,
  required int seconds,
  double? accuracy,
}) => GpsFix(
  lat: from.lat + meters / _metersPerDegreeLat,
  lon: from.lon,
  timestampSeconds: from.timestampSeconds + seconds,
  accuracyMeters: accuracy ?? from.accuracyMeters,
);

void main() {
  group('MeterSession reports what it did with each fix', () {
    test('the first fix opens the run and measures nothing', () {
      final session = MeterSession(mntPerKm: 1500);
      final verdict = session.addFix(_start);

      expect(verdict.outcome, MeterFixOutcome.opened);
      expect(verdict.rawMeters, 0);
      expect(verdict.countedMeters, 0);
    });

    test('a clear run of travel is counted and says so', () {
      final session = MeterSession(mntPerKm: 1500);
      session.addFix(_start);
      // 100m in 5s is 72 km/h: well clear of the 20m floor a +/-10m fix
      // sets, and well clear of the 5 km/h waiting rule.
      final verdict = session.addFix(_north(_start, meters: 100, seconds: 5));

      expect(verdict.outcome, MeterFixOutcome.travelled);
      expect(verdict.countedMeters, closeTo(100, 1));
      expect(verdict.discardedMeters, closeTo(0, 0.001));
      expect(session.distanceMeters, closeTo(100, 1));
    });

    test('movement inside the jitter floor is discarded, and the verdict '
        'still carries the metres that were thrown away', () {
      final session = MeterSession(mntPerKm: 1500);
      session.addFix(_start);
      // +/-10m fixes set a 20m floor. 15m of real movement is under it.
      final verdict = session.addFix(_north(_start, meters: 15, seconds: 5));

      expect(verdict.outcome, MeterFixOutcome.belowNoiseFloor);
      expect(verdict.rawMeters, closeTo(15, 1));
      expect(verdict.countedMeters, 0);
      expect(verdict.discardedMeters, closeTo(15, 1));
      expect(verdict.noiseFloorMeters, 20);
      // The odometer is the whole point: this movement earned nothing.
      expect(session.distanceMeters, 0);
    });

    test('a fix too poor to measure against is named separately from one '
        'whose movement was merely small', () {
      final session = MeterSession(mntPerKm: 1500);
      session.addFix(_start);
      final verdict = session.addFix(
        _north(_start, meters: 40, seconds: 5, accuracy: 150),
      );

      // Both land on the same billing branch; only the verdict tells them
      // apart, which is the entire reason the outcome exists.
      expect(verdict.outcome, MeterFixOutcome.accuracyTooPoor);
      expect(session.distanceMeters, 0);
    });

    test('slow movement is counted once it has genuinely gone somewhere, '
        'rather than being discarded for being slow', () {
      final session = MeterSession(mntPerKm: 1500);
      const sharp = GpsFix(
        lat: 47.9186,
        lon: 106.9176,
        timestampSeconds: 1000,
        accuracyMeters: 1,
      );
      session.addFix(sharp);
      // 9m in 10s is 3.24 km/h — a crawl in a jam. Until v0.4.0 a second
      // rule threw this away for being under 5 km/h, on top of the jitter
      // floor. The car had still moved nine metres.
      final verdict = session.addFix(_north(sharp, meters: 9, seconds: 10));

      expect(verdict.outcome, MeterFixOutcome.travelled);
      expect(verdict.countedMeters, closeTo(9, 1));
      expect(session.distanceMeters, closeTo(9, 1));
    });

    test('a car parked under a wall accrues no distance however long it '
        'sits there', () {
      // The property the anchor must never lose. Jitter wanders around one
      // spot; it does not displace from it. Sixty fixes of drift, five
      // minutes of it, and the odometer must not move a metre.
      final session = MeterSession(mntPerKm: 1500);
      var fix = _start;
      session.addFix(fix);
      for (var i = 1; i <= 60; i++) {
        // +/-6m of wander, alternating, on top of a +/-10m fix.
        fix = GpsFix(
          lat: _start.lat + (i.isEven ? 6 : -6) / _metersPerDegreeLat,
          lon: _start.lon,
          timestampSeconds: _start.timestampSeconds + i * 5,
          accuracyMeters: 10,
        );
        session.addFix(fix);
      }

      expect(session.distanceMeters, 0);
      expect(session.waitingSeconds, 300);
    });

    test('a duplicate fix does not advance the clock and changes nothing', () {
      final session = MeterSession(mntPerKm: 1500);
      session.addFix(_start);
      final verdict = session.addFix(_start);

      expect(verdict.outcome, MeterFixOutcome.noTimeAdvance);
      expect(session.fixes.length, 1);
    });

    test('a paused meter says it is paused', () {
      final session = MeterSession(mntPerKm: 1500);
      session.addFix(_start);
      session.pause();
      // First segment after pause() straddles the call and is discarded.
      final straddle = session.addFix(
        _north(_start, meters: 100, seconds: 5),
      );
      expect(straddle.outcome, MeterFixOutcome.pauseBoundary);

      final paused = session.addFix(
        _north(_start, meters: 200, seconds: 10),
      );
      expect(paused.outcome, MeterFixOutcome.paused);
      expect(session.distanceMeters, 0);
    });
  });

  group('MeterDiagnosticLog', () {
    test('separates what the GPS measured from what the meter billed', () {
      final log = MeterDiagnosticLog();
      log.record(
        fix: _start,
        arrivalMillis: 0,
        verdict: const MeterFixVerdict(
          outcome: MeterFixOutcome.travelled,
          seconds: 5,
          rawMeters: 100,
          countedMeters: 100,
          noiseFloorMeters: 20,
        ),
      );
      log.record(
        fix: _start,
        arrivalMillis: 5000,
        verdict: const MeterFixVerdict(
          outcome: MeterFixOutcome.belowNoiseFloor,
          seconds: 5,
          rawMeters: 15,
          countedMeters: 0,
          noiseFloorMeters: 20,
        ),
      );

      expect(log.rawMeters, 115);
      expect(log.countedMeters, 100);
      expect(log.discardedMeters, 15);
      expect(
        log.discardedMetersBy(MeterFixOutcome.belowNoiseFloor),
        15,
      );
      expect(log.countOf(MeterFixOutcome.travelled), 1);
    });

    test('a long gap between arrivals is recorded as a stall', () {
      final log = MeterDiagnosticLog();
      // Three fixes at the requested 5-second cadence: 0s, 5s, 10s.
      for (final arrival in [0, 5000, 10000]) {
        log.record(
          fix: _start,
          arrivalMillis: arrival,
          verdict: const MeterFixVerdict(outcome: MeterFixOutcome.travelled),
        );
      }
      // The app went to the background here and Android stopped delivering
      // for 62 seconds.
      log.record(
        fix: _start,
        arrivalMillis: 10000 + 62000,
        verdict: const MeterFixVerdict(outcome: MeterFixOutcome.travelled),
      );

      expect(log.longestArrivalGapMillis, 62000);
      expect(log.stalledArrivalCount, 1);
    });

    test('trimming old rows never costs a totals figure', () {
      final log = MeterDiagnosticLog(maxRetainedSamples: 2);
      for (var i = 0; i < 5; i++) {
        log.record(
          fix: _start,
          arrivalMillis: i * 5000,
          verdict: const MeterFixVerdict(
            outcome: MeterFixOutcome.travelled,
            seconds: 5,
            rawMeters: 10,
            countedMeters: 10,
          ),
        );
      }

      expect(log.samples.length, 2);
      expect(log.trimmedCount, 3);
      // Accumulated, not derived from the surviving rows — the whole reason
      // the counters live outside the ring buffer.
      expect(log.recordedCount, 5);
      expect(log.rawMeters, 50);
      expect(log.countedMeters, 50);
    });

    test('names the speed a car had to beat before a metre counted', () {
      final log = MeterDiagnosticLog();
      for (var i = 0; i < 5; i++) {
        log.record(
          fix: _start,
          arrivalMillis: i * 5000,
          verdict: const MeterFixVerdict(
            outcome: MeterFixOutcome.belowNoiseFloor,
            seconds: 5,
            rawMeters: 25,
            noiseFloorMeters: 30,
          ),
        );
      }

      // 30m per 5s is 6 m/s is 21.6 km/h.
      expect(log.billingSpeedThresholdKmh, closeTo(21.6, 0.2));
    });
  });

  group('the shortfall, fixed', () {
    test('ten minutes of real city driving at 18 km/h is billed in full', () {
      // This is the field report, rebuilt from first principles. Nothing
      // here is a pathological case: 18 km/h is ordinary Ulaanbaatar
      // traffic, +/-15m is an ordinary fix between buildings, and 5 seconds
      // is the interval the app itself asks for.
      final session = MeterSession(mntPerKm: 1500);
      final log = MeterDiagnosticLog();

      var fix = const GpsFix(
        lat: 47.9186,
        lon: 106.9176,
        timestampSeconds: 1000,
        accuracyMeters: 15,
      );
      log.record(
        fix: fix,
        arrivalMillis: 0,
        verdict: session.addFix(fix),
      );

      // 18 km/h = 5 m/s = 25 metres per 5-second fix. 120 fixes = 10 min.
      for (var i = 1; i <= 120; i++) {
        fix = _north(fix, meters: 25, seconds: 5);
        log.record(
          fix: fix,
          arrivalMillis: i * 5000,
          verdict: session.addFix(fix),
        );
      }

      // The car covered three kilometres.
      expect(log.rawMeters, closeTo(3000, 20));
      // Before v0.4.0 the passenger was billed for NONE of them: every
      // 25-metre segment fell under the 30-metre floor a +/-15m fix sets,
      // and each one was discarded for good. Now the anchor holds until the
      // car has genuinely gone somewhere, so almost all of it is billed.
      //
      // Not every last metre: whatever has not yet cleared the floor when
      // the run ends stays uncounted, which is at most one anchor's worth
      // and lands on the passenger's side of the doubt on purpose.
      expect(session.distanceMeters, greaterThan(2900));
      expect(session.distanceMeters, lessThanOrEqualTo(3000));
    });

    test('the same drive above the threshold bills all of it', () {
      // The control. Same accuracy, same interval, faster car: every metre
      // counts. So the filter is not broken in general — it is calibrated
      // against a speed most city driving never reaches.
      final session = MeterSession(mntPerKm: 1500);
      var fix = const GpsFix(
        lat: 47.9186,
        lon: 106.9176,
        timestampSeconds: 1000,
        accuracyMeters: 15,
      );
      session.addFix(fix);
      for (var i = 1; i <= 120; i++) {
        // 40 m per 5 s = 28.8 km/h.
        fix = _north(fix, meters: 40, seconds: 5);
        session.addFix(fix);
      }

      expect(session.distanceMeters, closeTo(4800, 30));
    });
  });

  group('the report', () {
    test('leads with the distance that was refused', () {
      final log = MeterDiagnosticLog();
      log.record(
        fix: _start,
        arrivalMillis: 0,
        verdict: const MeterFixVerdict(
          outcome: MeterFixOutcome.travelled,
          seconds: 5,
          rawMeters: 100,
          countedMeters: 100,
          noiseFloorMeters: 20,
        ),
      );
      log.record(
        fix: _start,
        arrivalMillis: 5000,
        verdict: const MeterFixVerdict(
          outcome: MeterFixOutcome.belowNoiseFloor,
          seconds: 5,
          rawMeters: 400,
          noiseFloorMeters: 20,
        ),
      );

      final report = formatMeterDiagnosticReport(log, appVersion: '0.4.0');

      expect(report, contains('ЗАЙ'));
      expect(report, contains('Хаягдсан'));
      expect(report, contains('донслолтын босго'));
      expect(report, contains('400'));
      expect(report, contains('20%'));
    });

    test('says out loud when delivery stalled', () {
      final log = MeterDiagnosticLog();
      log.record(
        fix: _start,
        arrivalMillis: 0,
        verdict: const MeterFixVerdict(outcome: MeterFixOutcome.travelled),
      );
      log.record(
        fix: _start,
        arrivalMillis: 90000,
        verdict: const MeterFixVerdict(outcome: MeterFixOutcome.travelled),
      );

      final report = formatMeterDiagnosticReport(log, appVersion: '0.4.0');
      expect(report, contains('тасалдал'));
    });

    test('an empty log does not pretend to have measured anything', () {
      final report = formatMeterDiagnosticReport(
        MeterDiagnosticLog(),
        appVersion: '0.4.0',
      );
      expect(report, contains('Бичигдсэн цэг алга'));
    });

    test('csv carries one row per retained fix, with the verdict', () {
      final log = MeterDiagnosticLog();
      log.record(
        fix: _start,
        arrivalMillis: 0,
        verdict: const MeterFixVerdict(
          outcome: MeterFixOutcome.belowNoiseFloor,
          seconds: 5,
          rawMeters: 15,
          noiseFloorMeters: 20,
          speedKmh: 10.8,
        ),
      );

      final csv = formatMeterDiagnosticCsv(log);
      final lines = csv.trim().split('\n');
      expect(lines.length, 2);
      expect(lines.first, startsWith('i,arrival_ms'));
      expect(lines[1], contains('belowNoiseFloor'));
      expect(lines[1], contains('47.918600'));
    });
  });
}
