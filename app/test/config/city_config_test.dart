// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/config/city_config.dart';

void main() {
  test('defaultCityConfig is Ulaanbaatar, Sukhbaatar Square', () {
    expect(defaultCityConfig.name, 'Улаанбаатар');
    expect(defaultCityConfig.centerLat, closeTo(47.9186, 0.001));
    expect(defaultCityConfig.centerLon, closeTo(106.9176, 0.001));
  });
}
