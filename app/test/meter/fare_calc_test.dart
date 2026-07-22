// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/meter/fare_calc.dart';

void main() {
  test('computeFareMnt multiplies tariff by kilometers', () {
    expect(computeFareMnt(mntPerKm: 500, distanceMeters: 3000), 1500);
  });

  test('computeFareMnt rounds to the nearest төгрөг', () {
    expect(computeFareMnt(mntPerKm: 1000, distanceMeters: 1234), 1234);
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
}
