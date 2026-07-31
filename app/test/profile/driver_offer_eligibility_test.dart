// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/profile/driver_offer_eligibility.dart';
import 'package:takhi/profile/driver_photo_rules.dart';

Uint8List _photo([int bytes = 1024]) =>
    Uint8List.fromList(List<int>.filled(bytes, 0x42));

DriverOfferBlock? _block({
  String? family = 'Б.',
  String? given = 'Батбаяр',
  Uint8List? photo,
}) => driverOfferBlock(
  familyName: family,
  givenName: given,
  photoJpeg: photo ?? _photo(),
);

void main() {
  test('a driver with both name parts and a photo may send offers', () {
    expect(_block(), isNull);
  });

  group('blocks on the name', () {
    test('when the family name is missing', () {
      expect(_block(family: null), DriverOfferBlock.missingName);
    });

    test('when the given name is missing', () {
      expect(_block(given: null), DriverOfferBlock.missingName);
    });

    test('when a name is blank', () {
      expect(_block(family: ''), DriverOfferBlock.missingName);
      expect(_block(given: '   '), DriverOfferBlock.missingName);
    });

    // The gate reuses the protocol's own name rule rather than only
    // checking for emptiness, so a name that could never have been typed
    // into the form cannot be smuggled in through another code path.
    test('when a name is not a name', () {
      expect(_block(given: 'Бат1'), DriverOfferBlock.missingName);
      expect(_block(given: 'Бат🚕'), DriverOfferBlock.missingName);
      expect(_block(family: '<b>'), DriverOfferBlock.missingName);
    });

    test('accepts the shapes real Mongolian names take', () {
      expect(_block(family: 'Б.', given: 'Мөнх-Эрдэнэ'), isNull);
      expect(_block(family: 'Ван Дер Берг', given: 'Сараа'), isNull);
      expect(_block(family: 'Цэрэндорж', given: 'Ganbold'), isNull);
    });
  });

  group('blocks on the photo', () {
    test('when there is none', () {
      expect(_block(photo: Uint8List(0)), DriverOfferBlock.missingPhoto);
    });

    test('when it is null', () {
      expect(
        driverOfferBlock(
          familyName: 'Б.',
          givenName: 'Батбаяр',
          photoJpeg: null,
        ),
        DriverOfferBlock.missingPhoto,
      );
    });

    test('a photo exactly at the cap is allowed', () {
      expect(_block(photo: _photo(kDriverPhotoMaxBytes)), isNull);
    });

    // Relays drop oversized events, so sending this would produce an offer
    // that simply never arrives, with nothing on either screen to say why.
    // A refusal the driver can read beats silence.
    test('a photo over the cap is refused rather than sent into the void', () {
      expect(
        _block(photo: _photo(kDriverPhotoMaxBytes + 1)),
        DriverOfferBlock.missingPhoto,
      );
    });
  });
}
