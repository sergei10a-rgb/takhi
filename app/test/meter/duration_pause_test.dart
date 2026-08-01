// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two money bugs the duration rate shipped with, and the guards that keep
// them from coming back. Both were found by an adversarial review and then
// reproduced by running the meter, not by reading it.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/meter_session.dart';

GpsFix _fix(int t) =>
    GpsFix(lat: 47.9188, lon: 106.9176, timestampSeconds: t, accuracyMeters: 5);

void main() {
  group('a paused meter charges nothing at all', () {
    test('the trip-duration rate stops with the other two', () {
      // Reproduces the shipped bug exactly: a 3-minute run of which 2
      // minutes were paused billed 1800₮ at 600₮/мин, while the
      // stopped-time meter correctly billed 0. «Түр зогсоох» announced it
      // had stopped the meter and then kept taking money.
      final session = MeterSession(
        mntPerKm: 2000,
        waitTariffMntPerMinute: 60,
        durationTariffMntPerMinute: 600,
      );
      session.addFix(_fix(0));
      session.pause();
      session.addFix(_fix(60));
      session.addFix(_fix(180));

      expect(session.pausedSeconds, 120);
      expect(session.waitingSeconds, 0);
      expect(
        session.durationFareMnt,
        0,
        reason: 'a pause both sides agreed to is nobody\'s fare',
      );
      expect(session.fareMnt, 0);
    });

    test('but the trip still REPORTS its true wall-clock length', () {
      // The receipt must say how long the trip actually took. Only the
      // billable subset shrinks.
      final session = MeterSession(
        mntPerKm: 2000,
        durationTariffMntPerMinute: 600,
      );
      session.addFix(_fix(0));
      session.pause();
      session.addFix(_fix(60));
      session.addFix(_fix(180));

      expect(session.durationSeconds, 180, reason: 'honest wall clock');
      // Zero, not 60. The 0->60 segment straddles the pause() call and is
      // discarded rather than counted as paused, so a
      // `durationSeconds - pausedSeconds` implementation would have billed
      // it. Counting up from the segments that were genuinely on the clock
      // is what closes that leak.
      expect(session.billableDurationSeconds, 0);
    });

    test('time before and after a pause is still charged', () {
      final session = MeterSession(mntPerKm: 0, durationTariffMntPerMinute: 60);
      session.addFix(_fix(0));
      session.addFix(_fix(60)); // 60s running
      session.pause();
      session.addFix(_fix(120)); // straddling segment, discarded
      session.addFix(_fix(240)); // 120s paused
      session.resume();
      session.addFix(_fix(300)); // straddling segment, discarded
      session.addFix(_fix(360)); // 60s running again

      // 360s wall clock. 120s explicitly paused, plus TWO 60s straddling
      // segments (one entering the pause, one leaving it) which `pause()`
      // discards on purpose -- it cannot know where inside them the call
      // fell, and the class always resolves that doubt for the passenger.
      // So 360 - 120 - 120 = 120 billable, and a naive subtraction would
      // have charged 240.
      expect(session.durationSeconds, 360);
      expect(session.pausedSeconds, 120);
      expect(session.billableDurationSeconds, 120);
      expect(session.durationFareMnt, 120);
    });

    test('a run paused end to end bills zero, never a negative', () {
      final session = MeterSession(
        mntPerKm: 0,
        durationTariffMntPerMinute: 900,
      );
      session.addFix(_fix(0));
      session.pause();
      for (var t = 60; t <= 600; t += 60) {
        session.addFix(_fix(t));
      }
      expect(session.billableDurationSeconds, greaterThanOrEqualTo(0));
      expect(session.durationFareMnt, 0);
      expect(session.fareMnt, 0);
    });
  });

  group('a negative rate can never produce a negative charge', () {
    // Both rate boxes refuse a minus sign, but a rate reaches the core from
    // places no text field guards: a profile cached by an older build, and
    // a kind-0 event published by somebody else's client.
    test('a negative trip-duration rate charges zero', () {
      expect(
        computeDurationFareMnt(mntPerMinute: -500, durationSeconds: 120),
        0,
      );
    });

    test('a negative stopped-time rate charges zero', () {
      expect(computeWaitingFareMnt(mntPerMinute: -500, waitingSeconds: 120), 0);
    });

    test('through a whole session, the total never goes below zero', () {
      final session = MeterSession(
        mntPerKm: 2000,
        waitTariffMntPerMinute: -100,
        durationTariffMntPerMinute: -500,
      );
      session.addFix(_fix(0));
      session.addFix(_fix(120));

      expect(session.durationFareMnt, 0);
      expect(session.waitingFareMnt, 0);
      expect(
        session.fareMnt,
        greaterThanOrEqualTo(0),
        reason: 'a fare below zero is not a price and no screen can show it',
      );
    });

    test('negative seconds are floored too -- a clock that stepped backwards '
        'is not a discount', () {
      expect(
        computeDurationFareMnt(mntPerMinute: 600, durationSeconds: -60),
        0,
      );
      expect(computeWaitingFareMnt(mntPerMinute: 600, waitingSeconds: -60), 0);
    });
  });

  group('the rows still add up to the total', () {
    test('with all three rates and a pause in the middle', () {
      final session = MeterSession(
        mntPerKm: 2000,
        waitTariffMntPerMinute: 60,
        durationTariffMntPerMinute: 120,
      );
      session.addFix(_fix(0));
      session.addFix(_fix(60));
      session.pause();
      session.addFix(_fix(120));
      session.addFix(_fix(180));
      session.resume();
      session.addFix(_fix(240));
      session.addFix(_fix(300));

      expect(
        session.fareMnt,
        session.distanceFareMnt +
            session.waitingFareMnt +
            session.durationFareMnt,
        reason:
            'a passenger who adds the rows must get the number they pay -- a '
            'one-төгрөг gap is small in money and large in trust',
      );
    });
  });
}
