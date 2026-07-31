// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/profile/driver_photo_rules.dart';
import 'package:takhi/ride/ride_dm_payload.dart';

/// A stand-in for a compressed portrait: [bytes] long, base64'd.
String _photo(int bytes) =>
    base64Encode(Uint8List.fromList(List<int>.filled(bytes, 0x42)));

RideOfferPayload _decodeOffer(Map<String, dynamic> json) =>
    RideDmPayload.decode(jsonEncode(json)) as RideOfferPayload;

Map<String, dynamic> _baseOffer() => <String, dynamic>{
  'type': 'offer',
  'rideRequestId': 'req-1',
  'priceMnt': 9000,
  'etaMinutes': 5,
  'vehicleDescription': 'цагаан Prius',
};

void main() {
  group('a driver identity round-trips through the encrypted offer', () {
    test('name and photo survive encode then decode', () {
      final photo = _photo(1024);
      final sent = RideOfferPayload(
        rideRequestId: 'req-1',
        priceMnt: 9000,
        etaMinutes: 5,
        vehicleDescription: 'цагаан Prius',
        driverFamilyName: 'Б.',
        driverGivenName: 'Батбаяр',
        driverPhotoJpegBase64: photo,
      );
      final back = RideDmPayload.decode(sent.encode()) as RideOfferPayload;

      expect(back.driverFamilyName, 'Б.');
      expect(back.driverGivenName, 'Батбаяр');
      expect(back.driverFullName, 'Б. Батбаяр');
      expect(back.driverPhotoJpegBase64, photo);
      expect(back.driverPhotoBytes, hasLength(1024));
    });

    test('the rest of the offer is untouched by the new fields', () {
      final back =
          RideDmPayload.decode(
                RideOfferPayload(
                  rideRequestId: 'req-9',
                  priceMnt: 12000,
                  etaMinutes: 7,
                  vehicleDescription: 'хар Sonata',
                  kmTariffMnt: 1500,
                  waitTariffMntPerMinute: 300,
                  driverFamilyName: 'Ц.',
                  driverGivenName: 'Сараа',
                  driverPhotoJpegBase64: _photo(512),
                ).encode(),
              )
              as RideOfferPayload;
      expect(back.rideRequestId, 'req-9');
      expect(back.priceMnt, 12000);
      expect(back.etaMinutes, 7);
      expect(back.vehicleDescription, 'хар Sonata');
      expect(back.kmTariffMnt, 1500);
      expect(back.waitTariffMntPerMinute, 300);
    });
  });

  group('an offer from a client that predates driver identity', () {
    // The whole point of the fields being nullable. A rider running a newer
    // build must not lose every offer sent by an older one.
    test('still decodes, with no name and no photo', () {
      final back = _decodeOffer(_baseOffer());
      expect(back.driverFamilyName, isNull);
      expect(back.driverGivenName, isNull);
      expect(back.driverFullName, isNull);
      expect(back.driverPhotoJpegBase64, isNull);
      expect(back.driverPhotoBytes, isNull);
      expect(back.priceMnt, 9000);
    });

    test('an offer without identity omits the keys rather than sending '
        'nulls', () {
      final offer = RideOfferPayload(
        rideRequestId: 'req-1',
        priceMnt: 9000,
        etaMinutes: 5,
        vehicleDescription: 'цагаан Prius',
      );
      final json = offer.toJson();
      expect(json.containsKey('driverFamilyName'), isFalse);
      expect(json.containsKey('driverGivenName'), isFalse);
      expect(json.containsKey('driverPhotoJpeg'), isFalse);
    });
  });

  // Everything below arrives from a stranger who chose every byte of it.
  // The rule throughout: drop the field that cannot be trusted, keep the
  // offer. Throwing would let anyone delete a competitor's offer from a
  // passenger's screen by sending a malformed one of their own.
  group('a hostile offer loses the bad field, never the whole offer', () {
    test('a name carrying markup is dropped', () {
      final back = _decodeOffer(
        _baseOffer()..['driverGivenName'] = '<script>alert(1)</script>',
      );
      expect(back.driverGivenName, isNull);
      expect(back.priceMnt, 9000, reason: 'the offer itself was lost');
    });

    test('a name carrying a newline that would break the row is dropped or '
        'repaired, never passed through raw', () {
      final back = _decodeOffer(
        _baseOffer()..['driverGivenName'] = 'Бат\nБаяр',
      );
      expect(back.driverGivenName, isNot(contains('\n')));
    });

    test('a name of ten thousand characters is dropped', () {
      final back = _decodeOffer(
        _baseOffer()..['driverGivenName'] = 'а' * 10000,
      );
      expect(back.driverGivenName, isNull);
      expect(back.priceMnt, 9000);
    });

    test('a wrong-typed name is dropped', () {
      final back = _decodeOffer(_baseOffer()..['driverFamilyName'] = 42);
      expect(back.driverFamilyName, isNull);
      expect(back.priceMnt, 9000);
    });

    test('a name is normalized on the way in, not stored as typed', () {
      final back = _decodeOffer(
        _baseOffer()..['driverGivenName'] = '  Мөнх-Эрдэнэ  ',
      );
      expect(back.driverGivenName, 'Мөнх-Эрдэнэ');
    });

    test('half a name does not become a full name', () {
      final back = _decodeOffer(_baseOffer()..['driverGivenName'] = 'Батбаяр');
      expect(back.driverGivenName, 'Батбаяр');
      expect(back.driverFamilyName, isNull);
      expect(back.driverFullName, isNull);
    });

    test('a photo over the size cap is dropped', () {
      final back = _decodeOffer(
        _baseOffer()..['driverPhotoJpeg'] = _photo(kDriverPhotoMaxBytes + 1),
      );
      expect(back.driverPhotoJpegBase64, isNull);
      expect(back.driverPhotoBytes, isNull);
      expect(back.priceMnt, 9000);
    });

    test('a photo exactly at the size cap is kept', () {
      final back = _decodeOffer(
        _baseOffer()..['driverPhotoJpeg'] = _photo(kDriverPhotoMaxBytes),
      );
      expect(back.driverPhotoBytes, hasLength(kDriverPhotoMaxBytes));
    });

    // The memory-exhaustion case. Deciding by string length *before*
    // decoding is the whole defence: expanding a fifty-megabyte string to
    // measure it is doing the attack for the attacker.
    test('a fifty-megabyte photo field is dropped without being decoded', () {
      final huge = 'A' * (50 * 1024 * 1024);
      final back = _decodeOffer(_baseOffer()..['driverPhotoJpeg'] = huge);
      expect(back.driverPhotoJpegBase64, isNull);
      expect(back.priceMnt, 9000);
    });

    test('a photo that is not valid base64 is dropped', () {
      final back = _decodeOffer(
        _baseOffer()..['driverPhotoJpeg'] = 'not!!base64!!at!!all',
      );
      expect(back.driverPhotoJpegBase64, isNull);
      expect(back.driverPhotoBytes, isNull);
      expect(back.priceMnt, 9000);
    });

    test('an empty photo string is dropped', () {
      final back = _decodeOffer(_baseOffer()..['driverPhotoJpeg'] = '');
      expect(back.driverPhotoJpegBase64, isNull);
    });

    test('a wrong-typed photo field is dropped', () {
      final back = _decodeOffer(_baseOffer()..['driverPhotoJpeg'] = 12345);
      expect(back.driverPhotoJpegBase64, isNull);
      expect(back.priceMnt, 9000);
    });

    test('a photo and a name that are both hostile lose both, and keep the '
        'offer', () {
      final back = _decodeOffer(
        _baseOffer()
          ..['driverGivenName'] = 'Бат🚕'
          ..['driverFamilyName'] = ''
          ..['driverPhotoJpeg'] = _photo(kDriverPhotoMaxBytes * 2),
      );
      expect(back.driverGivenName, isNull);
      expect(back.driverFamilyName, isNull);
      expect(back.driverPhotoJpegBase64, isNull);
      expect(back.vehicleDescription, 'цагаан Prius');
      expect(back.etaMinutes, 5);
    });
  });

  group('driverPhotoBytes stays defensive for hand-built payloads', () {
    test('returns null for a photo built in code that is too big', () {
      final offer = RideOfferPayload(
        rideRequestId: 'req-1',
        priceMnt: 1,
        etaMinutes: 1,
        vehicleDescription: 'x',
        driverPhotoJpegBase64: _photo(kDriverPhotoMaxBytes + 1000),
      );
      expect(offer.driverPhotoBytes, isNull);
    });

    test('returns null for base64 nonsense built in code', () {
      final offer = RideOfferPayload(
        rideRequestId: 'req-1',
        priceMnt: 1,
        etaMinutes: 1,
        vehicleDescription: 'x',
        driverPhotoJpegBase64: '@@@@',
      );
      expect(offer.driverPhotoBytes, isNull);
    });
  });

  // Not a micro-optimisation, and not testable through the widgets that
  // depend on it: Flutter's image cache keys a `MemoryImage` on the
  // *identity* of its byte list, so a getter that decoded afresh on every
  // call handed each rebuild of an offer row a key the cache had never seen.
  // The visible result was a portrait that blanked and re-decoded whenever
  // a new offer arrived. Asserting identity here is the only place that
  // rule can be stated mechanically.
  group('the decoded portrait is the same list every time', () {
    test('two reads of the same payload return an identical list', () {
      final offer = RideOfferPayload(
        rideRequestId: 'req-1',
        priceMnt: 1,
        etaMinutes: 1,
        vehicleDescription: 'x',
        driverPhotoJpegBase64: _photo(1024),
      );
      expect(identical(offer.driverPhotoBytes, offer.driverPhotoBytes), isTrue);
    });

    test('a payload with no photo answers null without redeciding', () {
      final offer = RideOfferPayload(
        rideRequestId: 'req-1',
        priceMnt: 1,
        etaMinutes: 1,
        vehicleDescription: 'x',
      );
      expect(offer.driverPhotoBytes, isNull);
      expect(offer.driverPhotoBytes, isNull);
    });

    test('a rejected photo stays rejected on the second read', () {
      final offer = RideOfferPayload(
        rideRequestId: 'req-1',
        priceMnt: 1,
        etaMinutes: 1,
        vehicleDescription: 'x',
        driverPhotoJpegBase64: _photo(kDriverPhotoMaxBytes + 1000),
      );
      expect(offer.driverPhotoBytes, isNull);
      expect(offer.driverPhotoBytes, isNull);
    });
  });
}
