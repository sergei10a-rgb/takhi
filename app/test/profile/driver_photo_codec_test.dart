// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:takhi/profile/driver_photo_codec.dart';
import 'package:takhi/profile/driver_photo_rules.dart';

/// A photograph-shaped test input.
///
/// Full-range random pixels put through a gaussian blur. The blur is the
/// part that matters: *raw* RGB noise is not a hard photograph, it is an
/// impossible one -- 512x512 of it encodes to 445KB at quality 88 and 185KB
/// at quality 40, because JPEG's whole premise is that neighbouring pixels
/// are related and in white noise they are not. Every size assertion below
/// would then be measuring a case no camera can produce. Blurring restores
/// the mostly-low-frequency spectrum a real photo has: at [blurRadius] 4
/// this fixture measures 64KB at quality 88 falling to 23KB at quality 40,
/// which is squarely where a detailed 512px portrait actually lands.
///
/// Bigger [blurRadius] means a softer, more compressible photograph.
Uint8List _photoJpeg(
  int width,
  int height, {
  int blurRadius = 4,
  int seed = 7,
}) {
  final rng = Random(seed);
  var image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        rng.nextInt(256),
        rng.nextInt(256),
        rng.nextInt(256),
      );
    }
  }
  image = img.gaussianBlur(image, radius: blurRadius);
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

/// The two big fixtures, built once -- generating and blurring a couple of
/// million pixels per test case would dominate the runtime of this file.
final Uint8List _landscape = _photoJpeg(1600, 1200, blurRadius: 6);
final Uint8List _portrait = _photoJpeg(1200, 1600, blurRadius: 6);

/// A busy 512x512 photograph: the case that actually presses on the byte
/// cap, since nothing is scaled away before it is encoded.
final Uint8List _detailedSquare = _photoJpeg(
  kDriverPhotoMaxEdgePx,
  kDriverPhotoMaxEdgePx,
  blurRadius: 4,
);

void _expectJpeg(Uint8List bytes) {
  expect(bytes.length, greaterThan(2));
  expect(bytes[0], 0xFF, reason: 'not a JPEG: bad SOI marker');
  expect(bytes[1], 0xD8, reason: 'not a JPEG: bad SOI marker');
}

DriverPhotoCompressed _accepted(DriverPhotoCompression result) {
  expect(
    result,
    isA<DriverPhotoCompressed>(),
    reason: result is DriverPhotoCompressionRejected
        ? 'rejected as ${result.reason}'
        : 'unexpected result',
  );
  return result as DriverPhotoCompressed;
}

void main() {
  group('compressDriverPhoto scales', () {
    test('a big landscape photo down so its longest edge is the limit, '
        'keeping the aspect ratio', () {
      final out = _accepted(compressDriverPhoto(_landscape));
      expect(out.width, kDriverPhotoMaxEdgePx);
      expect(out.height, (kDriverPhotoMaxEdgePx * 1200 / 1600).round());
    });

    test('a big portrait photo by its height, not blindly by its width', () {
      final out = _accepted(compressDriverPhoto(_portrait));
      expect(out.height, kDriverPhotoMaxEdgePx);
      expect(out.width, (kDriverPhotoMaxEdgePx * 1200 / 1600).round());
    });

    // Enlarging adds bytes and no information. A driver who hands over a
    // small photo should get their small photo back, not a blurry upscale.
    test('never up: a photo already smaller than the limit keeps its size', () {
      final out = _accepted(compressDriverPhoto(_photoJpeg(200, 150)));
      expect(out.width, 200);
      expect(out.height, 150);
    });

    test('a square photo exactly at the limit keeps its dimensions', () {
      final out = _accepted(compressDriverPhoto(_detailedSquare));
      expect(out.width, kDriverPhotoMaxEdgePx);
      expect(out.height, kDriverPhotoMaxEdgePx);
    });
  });

  group('compressDriverPhoto output', () {
    test('is a JPEG', () {
      _expectJpeg(_accepted(compressDriverPhoto(_landscape)).jpegBytes);
    });

    // The contract the whole ladder exists to keep. A relay silently
    // dropping an oversized gift-wrap is an offer that never arrives, with
    // nothing on either screen to say why -- so the cap is not advisory.
    test('fits under the byte cap for a detailed photo at full size', () {
      final out = _accepted(compressDriverPhoto(_detailedSquare));
      expect(out.jpegBytes.length, lessThanOrEqualTo(kDriverPhotoMaxBytes));
    });

    test('fits under the byte cap for an oversized photo', () {
      final out = _accepted(compressDriverPhoto(_landscape));
      expect(out.jpegBytes.length, lessThanOrEqualTo(kDriverPhotoMaxBytes));
    });

    test('reports the quality rung it actually stopped on', () {
      final out = _accepted(compressDriverPhoto(_landscape));
      expect(kDriverPhotoJpegQualityLadder, contains(out.quality));
    });

    test('takes the first rung when the photo already fits there', () {
      // A small, flat image fits at the top of the ladder, so the walk must
      // stop immediately rather than degrading quality it did not need to.
      final flat = img.Image(width: 64, height: 64);
      img.fill(flat, color: img.ColorRgb8(120, 90, 60));
      final out = _accepted(
        compressDriverPhoto(Uint8List.fromList(img.encodeJpg(flat))),
      );
      expect(out.quality, kDriverPhotoJpegQualityLadder.first);
    });

    test('walks down the ladder when the top rung is too big', () {
      // A tightened cap rather than the shipped one, so the rung this lands
      // on is decided by the ladder and not by how compressible today's
      // fixture happens to be.
      const tightCap = 30 * 1024;
      final out = _accepted(
        compressDriverPhoto(_detailedSquare, maxBytes: tightCap),
      );
      expect(out.jpegBytes.length, lessThanOrEqualTo(tightCap));
      expect(out.quality, lessThan(kDriverPhotoJpegQualityLadder.first));
    });
  });

  group('compressDriverPhoto rejects', () {
    test('bytes that are not an image at all', () {
      final result = compressDriverPhoto(
        Uint8List.fromList('this is not a photograph'.codeUnits),
      );
      expect(result, isA<DriverPhotoCompressionRejected>());
      expect(
        (result as DriverPhotoCompressionRejected).reason,
        DriverPhotoRejection.undecodable,
      );
    });

    test('an empty file', () {
      final result = compressDriverPhoto(Uint8List(0));
      expect(
        (result as DriverPhotoCompressionRejected).reason,
        DriverPhotoRejection.undecodable,
      );
    });

    test('a truncated JPEG', () {
      final half = Uint8List.sublistView(_landscape, 0, _landscape.length ~/ 3);
      expect(compressDriverPhoto(half), isA<DriverPhotoCompressionRejected>());
    });

    // Unreachable with the shipped numbers, which is exactly why it needs a
    // test: the branch only ever runs if somebody later tightens the cap.
    test('a photo that will not fit even on the bottom rung', () {
      final result = compressDriverPhoto(_detailedSquare, maxBytes: 64);
      expect(
        (result as DriverPhotoCompressionRejected).reason,
        DriverPhotoRejection.tooLargeAfterCompression,
      );
    });
  });

  group('compressDriverPhoto strips what a photo carries invisibly', () {
    test('camera metadata does not survive into the stored image', () {
      // A phone photo carries the camera model, the timestamp and, unless
      // the owner turned it off, the GPS coordinates of where it was taken.
      // A driver's portrait taken at home would otherwise ship their home
      // address to every passenger they ever offer a ride to.
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(200, 180, 160));
      image.exif.imageIfd['Model'] = 'SECRETCAMERAMODEL';
      image.exif.imageIfd['Software'] = 'SECRETSOFTWARETAG';
      final withExif = Uint8List.fromList(img.encodeJpg(image));
      // Guard the guard: if the encoder stopped writing EXIF, this test
      // would pass while proving nothing.
      expect(
        String.fromCharCodes(withExif).contains('SECRETCAMERAMODEL'),
        isTrue,
        reason: 'test fixture carries no EXIF, so it cannot prove stripping',
      );

      final out = _accepted(compressDriverPhoto(withExif));
      final text = String.fromCharCodes(out.jpegBytes);
      expect(text.contains('SECRETCAMERAMODEL'), isFalse);
      expect(text.contains('SECRETSOFTWARETAG'), isFalse);
      expect(img.decodeJpg(out.jpegBytes)!.exif.imageIfd.isEmpty, isTrue);
    });

    test('an EXIF rotation is baked into the pixels, not carried along', () {
      // Orientation 6 means "the camera was held sideways; rotate 90° CW to
      // view". Since the tag is dropped along with the rest of the
      // metadata, the rotation has to be applied to the pixels first -- or
      // every photo taken in portrait would be stored on its side.
      final image = img.Image(width: 400, height: 200);
      img.fill(image, color: img.ColorRgb8(10, 120, 200));
      image.exif.imageIfd.orientation = 6;
      final sideways = Uint8List.fromList(img.encodeJpg(image));

      final out = _accepted(compressDriverPhoto(sideways));
      expect(
        out.width,
        200,
        reason: 'rotation was not baked in: image is still landscape',
      );
      expect(out.height, 400);
    });
  });
}
