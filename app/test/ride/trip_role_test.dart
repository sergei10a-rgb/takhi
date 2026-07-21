// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/trip_role.dart';

void main() {
  test('wireValue matches buildTripReceipt/PROTOCOL.md §4.2 role strings', () {
    expect(TripRole.driver.wireValue, 'driver');
    expect(TripRole.passenger.wireValue, 'passenger');
  });
}
