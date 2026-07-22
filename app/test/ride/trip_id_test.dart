// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/trip_id.dart';

void main() {
  test('generates a 32-hex-char id from 16 bytes', () {
    final id = generateTripId(List<int>.filled(16, 7));
    expect(id.length, 32);
  });

  test('two calls without fixed bytes produce different ids', () {
    expect(generateTripId(), isNot(generateTripId()));
  });

  test('rejects a seed that is not exactly 16 bytes', () {
    expect(() => generateTripId(List<int>.filled(8, 1)), throwsArgumentError);
  });
}
