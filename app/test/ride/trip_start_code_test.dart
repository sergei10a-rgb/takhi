// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The pickup code confirms the two people are together before a meter runs.
// A local, server-less flow has no dispatcher's ride-ID to catch a wrong-car
// pickup, so this is that check — and a malformed code must never cost the
// handoff around it (the exact pickup point the driver is waiting for).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_start_code.dart';

void main() {
  group('isWellFormedStartCode', () {
    test('four digits is well-formed, leading zeros and all', () {
      expect(isWellFormedStartCode('1234'), isTrue);
      expect(isWellFormedStartCode('0000'), isTrue);
      expect(isWellFormedStartCode('0421'), isTrue);
    });

    test('anything not exactly four digits is not', () {
      expect(isWellFormedStartCode('123'), isFalse);
      expect(isWellFormedStartCode('12345'), isFalse);
      expect(isWellFormedStartCode('12a4'), isFalse);
      expect(isWellFormedStartCode(''), isFalse);
      expect(isWellFormedStartCode('12 4'), isFalse);
    });
  });

  group('generateStartCode', () {
    test('is always four digits, zero-padded', () {
      final rng = Random(1);
      for (var i = 0; i < 200; i++) {
        final code = generateStartCode(rng);
        expect(isWellFormedStartCode(code), isTrue, reason: 'got "$code"');
      }
    });

    test('a small random value still zero-pads to four digits', () {
      // Random(seed) is deterministic; whatever it produces, the code is
      // four digits — this pins the padding, not the value.
      final code = generateStartCode(Random(42));
      expect(code.length, kStartCodeDigits);
    });
  });

  group('startCodeMatches', () {
    test('an exact match passes', () {
      expect(startCodeMatches('0421', '0421'), isTrue);
    });

    test('a trailing space on the entry is forgiven', () {
      expect(startCodeMatches('0421', '0421 '), isTrue);
    });

    test('a wrong code fails', () {
      expect(startCodeMatches('0421', '0422'), isFalse);
    });

    test('a malformed expected code never matches, even a blank entry', () {
      expect(startCodeMatches('', ''), isFalse);
      expect(startCodeMatches('42', '42'), isFalse);
    });
  });

  group('RideHandoffPayload.startCode', () {
    RideHandoffPayload handoff({String? startCode}) => RideHandoffPayload(
      rideRequestId: 'req1',
      tripId: 'trip1',
      lat: 47.9,
      lon: 106.9,
      plusCode: 'PLUS',
      landmarkText: 'gate',
      startCode: startCode,
    );

    test('survives an encode/decode round-trip', () {
      final decoded =
          RideDmPayload.decode(handoff(startCode: '0421').encode())
              as RideHandoffPayload;
      expect(decoded.startCode, '0421');
    });

    test('absent stays null and the handoff still decodes', () {
      final decoded =
          RideDmPayload.decode(handoff().encode()) as RideHandoffPayload;
      expect(decoded.startCode, isNull);
      expect(decoded.tripId, 'trip1');
    });

    test('a malformed code on the wire is dropped, not thrown on', () {
      // A hostile or old client puts junk in the field; the handoff — the
      // pickup point the driver needs — must still arrive.
      const wire =
          '{"type":"handoff","rideRequestId":"r","tripId":"t","lat":47.9,'
          '"lon":106.9,"plusCode":"P","landmarkText":"L","startCode":"nope"}';
      final decoded = RideDmPayload.decode(wire) as RideHandoffPayload;
      expect(decoded.startCode, isNull);
      expect(decoded.plusCode, 'P');
    });
  });
}
