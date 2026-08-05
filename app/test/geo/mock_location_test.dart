// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A local, server-less taximeter cannot re-derive a trip from an
// independent source, so a driver running a "Fake GPS" app is a threat only
// the device-level mock flag can catch. These tests pin that the flag
// survives the trip from the platform, into a fix, into a run — and that it
// changes no charge, only the doubt shown to the passenger.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/meter_session.dart';

const double _kMetreInDegrees = 1 / 111320.0;

GpsFix _fix({required int t, double northMetres = 0, bool isMocked = false}) =>
    GpsFix(
      lat: 47.9188 + northMetres * _kMetreInDegrees,
      lon: 106.9176,
      timestampSeconds: t,
      accuracyMeters: 5,
      isMocked: isMocked,
    );

void main() {
  group('GpsFix.isMocked', () {
    test('defaults to false when the platform did not say', () {
      const fix = GpsFix(lat: 47.9, lon: 106.9, timestampSeconds: 0);
      expect(fix.isMocked, isFalse);
    });
  });

  group('MeterSession.sawMockedFix', () {
    test('is false for a run of only real fixes', () {
      final meter = MeterSession(mntPerKm: 1500);
      meter.addFix(_fix(t: 0));
      meter.addFix(_fix(t: 5, northMetres: 40));
      meter.addFix(_fix(t: 10, northMetres: 80));
      expect(meter.sawMockedFix, isFalse);
    });

    test('latches true the moment one mocked fix arrives', () {
      final meter = MeterSession(mntPerKm: 1500);
      meter.addFix(_fix(t: 0));
      meter.addFix(_fix(t: 5, northMetres: 40, isMocked: true));
      expect(meter.sawMockedFix, isTrue);
    });

    test('stays true after the driver switches the fake-GPS app back off', () {
      final meter = MeterSession(mntPerKm: 1500);
      meter.addFix(_fix(t: 0, isMocked: true));
      meter.addFix(_fix(t: 5, northMetres: 40));
      meter.addFix(_fix(t: 10, northMetres: 80));
      expect(
        meter.sawMockedFix,
        isTrue,
        reason:
            'one faked reading taints the whole run; toggling off must '
            'not launder it',
      );
    });

    test('a mocked opening fix still latches, before any distance', () {
      final meter = MeterSession(mntPerKm: 1500);
      meter.addFix(_fix(t: 0, isMocked: true));
      expect(meter.sawMockedFix, isTrue);
    });

    test('the mark changes no charge — distance is billed as measured', () {
      final real = MeterSession(mntPerKm: 1500)
        ..addFix(_fix(t: 0))
        ..addFix(_fix(t: 20, northMetres: 200));
      final mocked = MeterSession(mntPerKm: 1500)
        ..addFix(_fix(t: 0, isMocked: true))
        ..addFix(_fix(t: 20, northMetres: 200, isMocked: true));
      expect(mocked.fareMnt, real.fareMnt);
      expect(mocked.sawMockedFix, isTrue);
      expect(real.sawMockedFix, isFalse);
    });
  });
}
