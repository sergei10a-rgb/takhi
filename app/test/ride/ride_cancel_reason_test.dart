// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The cancel reason is decoded from whatever a peer sent — an old client, a
// newer one, or a malformed message. The one behaviour that must never bend
// is that decoding a reason cannot throw, because the cancel it rides on
// (tearing a dead ride down) has to arrive regardless.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/ride_cancel_reason.dart';

void main() {
  group('RideCancelReason.wireValue', () {
    test('every member has a distinct, stable wire token', () {
      final tokens = RideCancelReason.values.map((r) => r.wireValue).toList();
      expect(tokens.toSet().length, tokens.length, reason: 'no duplicates');
      // Pin the spellings so a future refactor cannot quietly change them.
      expect(RideCancelReason.unknown.wireValue, 'unknown');
      expect(
        RideCancelReason.passengerChangedMind.wireValue,
        'passenger_changed_mind',
      );
      expect(RideCancelReason.driverTooFar.wireValue, 'driver_too_far');
      expect(RideCancelReason.passengerNoShow.wireValue, 'passenger_no_show');
      expect(RideCancelReason.other.wireValue, 'other');
    });
  });

  group('RideCancelReason.fromWire', () {
    test('returns the matching member for every known token', () {
      for (final reason in RideCancelReason.values) {
        expect(RideCancelReason.fromWire(reason.wireValue), reason);
      }
    });

    test('drops an unrecognised token to unknown rather than throwing', () {
      expect(
        RideCancelReason.fromWire('some_future_reason'),
        RideCancelReason.unknown,
      );
      expect(RideCancelReason.fromWire(''), RideCancelReason.unknown);
      expect(
        RideCancelReason.fromWire('Passenger_No_Show'),
        RideCancelReason.unknown,
      );
    });
  });
}
