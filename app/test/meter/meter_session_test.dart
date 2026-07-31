// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/meter_session.dart';

/// A fix on the prime meridian at [lat] degrees north, [t] seconds in.
/// 0.001° of latitude is ~111.2 m, so a 0.001 step per 10 s is ~40 km/h
/// (moving) and a 0.00002 step per 10 s is ~0.8 km/h (parked, jittering).
GpsFix at(double lat, int t) => GpsFix(lat: lat, lon: 0, timestampSeconds: t);

void main() {
  test('MeterSession accumulates distance/duration/fare from fed fixes', () {
    // A kilometre in a minute -- 60 km/h, which is a car.
    //
    // This used to step a whole degree of longitude in 60s: 111 km, or
    // 6,672 km/h. It passed because nothing checked, and it stopped passing
    // when `classifyMovement` started rejecting physically impossible
    // segments as bad fixes rather than integrating them. The guard is
    // right and the fixture was never a journey, so the fixture moved.
    final session = MeterSession(mntPerKm: 1000);
    session.addFix(const GpsFix(lat: 0, lon: 0, timestampSeconds: 0));
    session.addFix(const GpsFix(lat: 0.009, lon: 0, timestampSeconds: 60));
    expect(session.distanceMeters, closeTo(1001, 2));
    expect(session.durationSeconds, 60);
    expect(session.fareMnt, closeTo(1001, 2));
  });

  test('MeterSession starts at zero before any fix', () {
    final session = MeterSession(mntPerKm: 500);
    expect(session.distanceMeters, 0);
    expect(session.durationSeconds, 0);
    expect(session.fareMnt, 0);
    expect(session.waitingSeconds, 0);
    expect(session.pausedSeconds, 0);
    expect(session.isWaiting, isFalse);
    expect(session.isPaused, isFalse);
  });

  test('a moving segment accumulates distance and no waiting time', () {
    final session = MeterSession(mntPerKm: 1000, waitTariffMntPerMinute: 300);
    session.addFix(at(0, 0));
    session.addFix(at(0.001, 10));
    expect(session.distanceMeters, closeTo(111, 1));
    expect(session.waitingSeconds, 0);
    expect(session.isWaiting, isFalse);
  });

  test('a parked segment accumulates waiting time and no distance, so GPS '
      'jitter is never billed as travel', () {
    final session = MeterSession(mntPerKm: 1000, waitTariffMntPerMinute: 300);
    session.addFix(at(0, 0));
    session.addFix(at(0.00002, 10));
    session.addFix(at(0, 20));
    expect(session.distanceMeters, 0);
    expect(session.waitingSeconds, 20);
    expect(session.isWaiting, isTrue);
  });

  test('no segment is ever counted as both travel and waiting — a stop '
      'inside a trip is charged exactly once', () {
    final session = MeterSession(mntPerKm: 1000, waitTariffMntPerMinute: 300);
    session.addFix(at(0, 0)); // no previous fix: nothing to measure yet
    session.addFix(at(0.001, 10)); // ~40 km/h  -> moving
    session.addFix(at(0.00102, 20)); // jitter   -> waiting
    session.addFix(at(0.001, 30)); // jitter   -> waiting
    session.addFix(at(0.00102, 40)); // jitter   -> waiting
    session.addFix(at(0.00202, 50)); // ~40 km/h -> moving

    expect(session.distanceMeters, closeTo(222, 2));
    expect(session.waitingSeconds, 30);
    // Total elapsed is the whole run; the two meters partition the 40 s of
    // *measured* segments between them (the first fix opens no segment).
    expect(session.durationSeconds, 50);
    expect(session.isWaiting, isFalse);
  });

  test('fareMnt is the distance fare plus the waiting fare, and the two '
      'parts are separately readable for the receipt', () {
    final session = MeterSession(mntPerKm: 1000, waitTariffMntPerMinute: 300);
    session.addFix(at(0, 0));
    session.addFix(at(0.001, 10)); // ~111 m moving
    session.addFix(at(0.00102, 20)); // waiting
    session.addFix(at(0.001, 30)); // waiting
    session.addFix(at(0.00102, 40)); // waiting

    expect(session.distanceFareMnt, closeTo(111, 2));
    expect(session.waitingFareMnt, 150); // 300₮/мин × 30 сек
    expect(session.fareMnt, session.distanceFareMnt + session.waitingFareMnt);
  });

  test('waiting is free for a driver who set no waiting tariff (the '
      'pre-existing behaviour every saved tariff migrates to)', () {
    final session = MeterSession(mntPerKm: 1000);
    session.addFix(at(0, 0));
    session.addFix(at(0.00002, 10));
    session.addFix(at(0, 600));
    expect(session.waitingSeconds, 600);
    expect(session.waitingFareMnt, 0);
    expect(session.fareMnt, session.distanceFareMnt);
  });

  test('pause() stops both meters — a paused run bills neither distance nor '
      'waiting', () {
    final session = MeterSession(mntPerKm: 1000, waitTariffMntPerMinute: 300);
    session.addFix(at(0, 0));
    session.addFix(at(0.001, 10)); // moving, ~111 m
    session.pause();
    session.addFix(at(0.002, 20)); // straddles the pause: discarded
    session.addFix(at(0.003, 30)); // fully paused
    session.addFix(at(0.003, 40)); // fully paused

    expect(session.isPaused, isTrue);
    expect(session.distanceMeters, closeTo(111, 1));
    expect(session.waitingSeconds, 0);
    expect(session.pausedSeconds, 20);
    expect(session.fareMnt, session.distanceFareMnt);
  });

  test('resume() puts the meter back on the clock', () {
    final session = MeterSession(mntPerKm: 1000, waitTariffMntPerMinute: 300);
    session.addFix(at(0, 0));
    session.addFix(at(0.001, 10)); // moving, ~111 m
    session.pause();
    session.addFix(at(0.001, 20)); // straddles the pause: discarded
    session.addFix(at(0.001, 30)); // fully paused
    session.resume();
    session.addFix(at(0.001, 40)); // straddles the resume: discarded
    session.addFix(at(0.002, 50)); // moving again, ~111 m

    expect(session.isPaused, isFalse);
    expect(session.distanceMeters, closeTo(222, 2));
    expect(session.pausedSeconds, 10);
  });

  test('the segment straddling a pause/resume is discarded rather than '
      'charged, so a pause never costs the passenger', () {
    final session = MeterSession(mntPerKm: 1000, waitTariffMntPerMinute: 300);
    session.addFix(at(0, 0));
    session.pause();
    // Without the discard this 10 s would land in `pausedSeconds` only
    // because the pause happened to be requested first; with it, neither
    // meter claims a segment whose mode changed halfway through.
    session.addFix(at(0.00002, 10));
    expect(session.pausedSeconds, 0);
    expect(session.waitingSeconds, 0);
    expect(session.distanceMeters, 0);
  });

  test('a fix that does not advance the clock is ignored entirely, so a '
      'duplicate or out-of-order reading cannot inflate the fare', () {
    final session = MeterSession(mntPerKm: 1000, waitTariffMntPerMinute: 300);
    session.addFix(at(0, 0));
    session.addFix(at(0.001, 10)); // moving, ~111 m
    session.addFix(at(0.5, 10)); // same second: rejected
    session.addFix(at(0.9, 5)); // earlier: rejected
    session.addFix(at(0.002, 20)); // measured against the t=10 fix

    expect(session.fixes.length, 3);
    expect(session.distanceMeters, closeTo(222, 2));
    expect(session.durationSeconds, 20);
  });

  test('MeterSession exposes an unmodifiable fix list', () {
    final session = MeterSession(mntPerKm: 1000);
    session.addFix(at(0, 0));
    expect(() => session.fixes.add(at(0, 1)), throwsUnsupportedError);
  });
}
