// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The driver's position inside an offer: how precise it is allowed to be,
// what happens when it is absent, and what happens when another person's
// client sends nonsense.
//
// The precision is a privacy decision, not a display one -- see
// `RideOfferPayload.driverGeohash` and docs/design/SEQUENTIAL_DISPATCH.md.
// Publishing driver positions publicly was considered for this feature and
// refused, so the ONLY place a car's position may come from is an offer
// the driver chose to send to one passenger.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

/// Sükhbaatar Square, and a point about 300m away.
const _kSquareLat = 47.9188;
const _kSquareLon = 106.9176;

RideOfferPayload _offer({String? geohash}) => RideOfferPayload(
  rideRequestId: 'req-1',
  priceMnt: 12000,
  etaMinutes: 4,
  vehicleDescription: 'цагаан Prius',
  driverGeohash: geohash,
  driverFamilyName: 'Батбаяр',
  driverGivenName: 'Мөнх',
);

RideOfferPayload _roundTrip(RideOfferPayload offer) =>
    RideDmPayload.decode(jsonEncode(offer.toJson())) as RideOfferPayload;

void main() {
  group('precision', () {
    test('geohash-7 is what the constant says, and it is finer than the '
        'public request but coarser than a point', () {
      // The public ride request publishes geohash-6. This must be finer or
      // two drivers in one cell draw on the same pixel; it must not be a
      // coordinate or a driver answering ten requests hands their exact
      // position to nine passengers who did not pick them.
      expect(kDriverGeohashPrecision, 7);
      expect(kDriverGeohashPrecision, greaterThan(6));
    });

    test('a geohash-7 cell puts a car within about 80m of the truth', () {
      final cell = geohashEncode(
        _kSquareLat,
        _kSquareLon,
        precision: kDriverGeohashPrecision,
      );
      final centre = geohashDecodeCenter(cell);
      // Rough metres: 1 degree of latitude is ~111.3km, and at this
      // latitude a degree of longitude is ~0.67 of that.
      final dLat = (centre.lat - _kSquareLat).abs() * 111320;
      final dLon = (centre.lon - _kSquareLon).abs() * 111320 * 0.67;
      expect(dLat, lessThan(80));
      expect(dLon, lessThan(80));
    });

    test('a finer cell from a future client is truncated to ours, not '
        'trusted', () {
      final fine = geohashEncode(_kSquareLat, _kSquareLon, precision: 11);
      final decoded = _roundTrip(_offer(geohash: fine));
      expect(decoded.driverGeohash, hasLength(kDriverGeohashPrecision));
      expect(fine.startsWith(decoded.driverGeohash!), isTrue);
    });
  });

  group('a driver with no position is still a driver', () {
    test('an offer carrying none round-trips as null', () {
      expect(_roundTrip(_offer()).driverGeohash, isNull);
    });

    test('the field is omitted from the wire entirely when absent', () {
      expect(_offer().toJson().containsKey('driverGeohash'), isFalse);
    });

    test('the offer itself survives -- price, ETA and name all intact', () {
      // The passenger still sees them in the list and can still choose
      // them. A driver whose GPS was slow must never silently drop out of
      // the running.
      final decoded = _roundTrip(_offer());
      expect(decoded.priceMnt, 12000);
      expect(decoded.etaMinutes, 4);
      expect(decoded.driverFamilyName, 'Батбаяр');
    });
  });

  group('a malformed position costs the map a car and nothing else', () {
    test('a string that is not a geohash is dropped', () {
      // 'a', 'i', 'l' and 'o' are not in the geohash alphabet.
      expect(_roundTrip(_offer(geohash: 'hello!!')).driverGeohash, isNull);
      expect(_roundTrip(_offer(geohash: 'aiolaio')).driverGeohash, isNull);
    });

    test('an empty string is dropped', () {
      expect(_roundTrip(_offer(geohash: '')).driverGeohash, isNull);
      expect(_roundTrip(_offer(geohash: '   ')).driverGeohash, isNull);
    });

    test('the rest of the offer still arrives intact', () {
      final decoded = _roundTrip(_offer(geohash: 'not-a-geohash'));
      expect(decoded.driverGeohash, isNull);
      expect(
        decoded.priceMnt,
        12000,
        reason:
            'losing a real offer over a malformed optional field would '
            'be far worse than losing one car off the map',
      );
    });

    test('a non-string is refused loudly rather than guessed at', () {
      expect(
        () => RideDmPayload.decode(
          jsonEncode({..._offer().toJson(), 'driverGeohash': 12345}),
        ),
        throwsFormatException,
      );
    });
  });

  group('what an offer must never carry', () {
    test('no raw coordinates', () {
      // The whole privacy argument rests on this: the passenger receives a
      // CELL, never a point. A `lat`/`lon` pair appearing here later would
      // silently undo the decision recorded in SEQUENTIAL_DISPATCH.md.
      final json = _offer(
        geohash: geohashEncode(_kSquareLat, _kSquareLon, precision: 7),
      ).toJson();
      expect(json.containsKey('lat'), isFalse);
      expect(json.containsKey('lon'), isFalse);
      expect(json.containsKey('driverLat'), isFalse);
      expect(json.containsKey('driverLon'), isFalse);
    });
  });
}
