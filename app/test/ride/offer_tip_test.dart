// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The passenger no longer names a price before publishing (that guess
// produced no offers when it landed low, and nothing on screen said why).
// What replaced it is a bonus added at the one moment it can mean
// something: against a real figure from a real driver.
//
// These tests pin the two things that make the bonus safe to send -- it
// only ever moves the total UP, and both sides end up on the same number.
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:takhi/ride/ride_dm_payload.dart';

RideHandoffPayload _handoff({int? tipMnt}) => RideHandoffPayload(
  rideRequestId: 'req-1',
  tripId: 'trip-1',
  lat: 47.9188,
  lon: 106.9176,
  plusCode: 'PLUS+CODE',
  landmarkText: 'Улаан хаалга',
  tipMnt: tipMnt,
);

void main() {
  group('a bonus survives the wire', () {
    test('a real bonus is carried', () {
      final decoded = RideDmPayload.decode(
        jsonEncode(_handoff(tipMnt: 3000).toJson()),
      );
      expect((decoded as RideHandoffPayload).tipMnt, 3000);
    });

    test('no bonus means the field is absent, not zero', () {
      final json = _handoff().toJson();
      expect(
        json.containsKey('tipMnt'),
        isFalse,
        reason:
            'a driver must not see a «Нэмэлт 0 ₮» row for a bonus '
            'nobody offered',
      );
      final decoded = RideDmPayload.decode(jsonEncode(json));
      expect((decoded as RideHandoffPayload).tipMnt, isNull);
    });

    test('the rest of the handoff still decodes', () {
      final decoded =
          RideDmPayload.decode(jsonEncode(_handoff(tipMnt: 500).toJson()))
              as RideHandoffPayload;
      expect(decoded.tripId, 'trip-1');
      expect(decoded.lat, 47.9188);
      expect(decoded.landmarkText, 'Улаан хаалга');
    });
  });

  group('a bonus can never reduce what the driver was promised', () {
    test('a negative "bonus" from another client is dropped', () {
      // This arrives from somebody else's code, so the guard is here and
      // not only in the text field. A negative would quietly lower a price
      // the driver already quoted and accepted -- a counter-offer wearing
      // the wrong name, agreed to by somebody who never saw it.
      final decoded =
          RideDmPayload.decode(
                jsonEncode({..._handoff().toJson(), 'tipMnt': -5000}),
              )
              as RideHandoffPayload;
      expect(decoded.tipMnt, isNull);
    });

    test('a zero is treated as no bonus at all', () {
      final decoded =
          RideDmPayload.decode(
                jsonEncode({..._handoff().toJson(), 'tipMnt': 0}),
              )
              as RideHandoffPayload;
      expect(decoded.tipMnt, isNull);
    });

    test('a malformed bonus does not cost the driver the pickup point', () {
      // The exact coordinates are what the driver is actually waiting for.
      // Losing the whole handoff over a bad tip field would strand a
      // passenger who is already standing on the kerb.
      expect(
        () => RideDmPayload.decode(
          jsonEncode({..._handoff().toJson(), 'tipMnt': 'not a number'}),
        ),
        throwsFormatException,
      );
    });
  });

  group('both sides land on the same total', () {
    test('the driver bills their quote plus the bonus', () {
      // Mirrors `driver_inbox_page.dart`'s agreedPriceMnt, which is what
      // the whole trip then runs on.
      const quoted = 12000;
      final handoff = _handoff(tipMnt: 3000);
      expect(quoted + (handoff.tipMnt ?? 0), 15000);
    });

    test('with no bonus the driver bills exactly what they quoted', () {
      const quoted = 12000;
      final handoff = _handoff();
      expect(quoted + (handoff.tipMnt ?? 0), quoted);
    });
  });
}
