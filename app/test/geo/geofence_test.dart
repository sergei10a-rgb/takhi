// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The pickup gate decides whether a meter is allowed to start. Getting it
// wrong strands a driver who is genuinely at the pickup, or lets a fare run
// up on one who is not — so both sides of the boundary are tested, plus the
// mocked-fix case the gate exists to refuse.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geofence.dart';
import 'package:takhi/geo/gps_fix.dart';

const double _kMetreInDegrees = 1 / 111320.0;
const double _pickupLat = 47.9188;
const double _pickupLon = 106.9176;

GpsFix _fixNorthOfPickup(double metres, {bool isMocked = false}) => GpsFix(
  lat: _pickupLat + metres * _kMetreInDegrees,
  lon: _pickupLon,
  timestampSeconds: 0,
  accuracyMeters: 5,
  isMocked: isMocked,
);

void main() {
  group('isWithinRadius', () {
    test('a point on top of the target is within any positive radius', () {
      expect(
        isWithinRadius(_fixNorthOfPickup(0), _pickupLat, _pickupLon, 60),
        isTrue,
      );
    });

    test('a point well outside the radius is not within it', () {
      expect(
        isWithinRadius(_fixNorthOfPickup(200), _pickupLat, _pickupLon, 60),
        isFalse,
      );
    });
  });

  group('hasReachedPickup', () {
    test('a driver 40m away has arrived (inside the 60m default)', () {
      expect(
        hasReachedPickup(_fixNorthOfPickup(40), _pickupLat, _pickupLon),
        isTrue,
      );
    });

    test('a driver 100m away has not arrived', () {
      expect(
        hasReachedPickup(_fixNorthOfPickup(100), _pickupLat, _pickupLon),
        isFalse,
      );
    });

    test(
      'a mocked fix never satisfies the gate, even sitting on the point',
      () {
        expect(
          hasReachedPickup(
            _fixNorthOfPickup(0, isMocked: true),
            _pickupLat,
            _pickupLon,
          ),
          isFalse,
          reason: 'a faked "arrival" is exactly what the gate must refuse',
        );
      },
    );

    test('the radius is configurable for a tighter gate', () {
      expect(
        hasReachedPickup(
          _fixNorthOfPickup(40),
          _pickupLat,
          _pickupLon,
          radiusMeters: 20,
        ),
        isFalse,
      );
    });
  });
}
