// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/driver_photo_rules.dart';
import 'package:takhi/profile/driver_photo_service.dart';
import 'package:takhi/profile/driver_photo_store.dart';

Uint8List _photo(int width, int height) {
  final rng = math.Random(3);
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
  image = img.gaussianBlur(image, radius: 6);
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

DetectedFace _goodFace() => const DetectedFace(
  score: 0.95,
  left: 0.25,
  top: 0.2,
  width: 0.5,
  height: 0.5,
);

class _FakeDetector implements FaceDetector {
  List<DetectedFace> faces;
  Object? throws;
  Uint8List? sawBytes;
  _FakeDetector(this.faces, {this.throws});

  @override
  Future<List<DetectedFace>> detect(Uint8List jpegBytes) async {
    sawBytes = jpegBytes;
    final error = throws;
    if (error != null) throw error;
    return faces;
  }
}

void main() {
  late Uint8List bigPhoto;
  setUpAll(() => bigPhoto = _photo(1200, 900));

  group('DriverPhotoService.replacePhoto accepts', () {
    test('a portrait with one clear face, and stores it', () async {
      final store = InMemoryDriverPhotoStore();
      final service = DriverPhotoService(_FakeDetector([_goodFace()]), store);

      expect(await service.replacePhoto(bigPhoto), isNull);

      final stored = await store.load();
      expect(stored, isNotNull);
      expect(stored!.length, lessThanOrEqualTo(kDriverPhotoMaxBytes));
    });

    test('storing the compressed copy, not the original bytes', () async {
      final store = InMemoryDriverPhotoStore();
      final service = DriverPhotoService(_FakeDetector([_goodFace()]), store);
      await service.replacePhoto(bigPhoto);

      final stored = (await store.load())!;
      expect(stored.length, lessThan(bigPhoto.length));
      final decoded = img.decodeJpg(stored)!;
      expect(math.max(decoded.width, decoded.height), kDriverPhotoMaxEdgePx);
    });

    // Checking the 12-megapixel original and then shipping a shrunken copy
    // would be checking something other than what the passenger sees.
    test('running the face check on the compressed bytes, which are what '
        'actually get sent', () async {
      final detector = _FakeDetector([_goodFace()]);
      final service = DriverPhotoService(detector, InMemoryDriverPhotoStore());
      await service.replacePhoto(bigPhoto);

      expect(detector.sawBytes, isNotNull);
      expect(
        detector.sawBytes!.length,
        lessThanOrEqualTo(kDriverPhotoMaxBytes),
      );
      final decoded = img.decodeJpg(detector.sawBytes!)!;
      expect(math.max(decoded.width, decoded.height), kDriverPhotoMaxEdgePx);
    });
  });

  group('DriverPhotoService.replacePhoto refuses', () {
    Future<DriverPhotoRejection?> reject(
      Uint8List raw,
      _FakeDetector detector,
    ) async {
      final service = DriverPhotoService(detector, InMemoryDriverPhotoStore());
      return service.replacePhoto(raw);
    }

    test('a file that is not an image', () async {
      expect(
        await reject(
          Uint8List.fromList('not a photo'.codeUnits),
          _FakeDetector([_goodFace()]),
        ),
        DriverPhotoRejection.undecodable,
      );
    });

    test('a picture of a mountain, with a reason of its own', () async {
      expect(
        await reject(bigPhoto, _FakeDetector([])),
        DriverPhotoRejection.noFaceFound,
      );
    });

    test('a group photo, with a reason of its own', () async {
      expect(
        await reject(bigPhoto, _FakeDetector([_goodFace(), _goodFace()])),
        DriverPhotoRejection.multipleFaces,
      );
    });

    test('a face too far away, with a reason of its own', () async {
      const distant = DetectedFace(
        score: 0.9,
        left: 0.48,
        top: 0.48,
        width: 0.04,
        height: 0.04,
      );
      expect(
        await reject(bigPhoto, _FakeDetector([distant])),
        DriverPhotoRejection.faceTooSmall,
      );
    });

    test('everything, while the checker itself is broken', () async {
      expect(
        await reject(
          bigPhoto,
          _FakeDetector(
            const [],
            throws: const FaceDetectorUnavailableException('no model'),
          ),
        ),
        DriverPhotoRejection.faceCheckUnavailable,
      );
    });

    test(
      'every refusal is a distinct reason the UI can word differently',
      () async {
        final reasons = <DriverPhotoRejection?>{
          await reject(
            Uint8List.fromList('x'.codeUnits),
            _FakeDetector([_goodFace()]),
          ),
          await reject(bigPhoto, _FakeDetector([])),
          await reject(bigPhoto, _FakeDetector([_goodFace(), _goodFace()])),
          await reject(
            bigPhoto,
            _FakeDetector(const [], throws: Exception('boom')),
          ),
        };
        expect(reasons.length, 4);
      },
    );
  });

  // The one that matters after the first photo is set. A driver with a
  // working portrait who then picks a blurry one by mistake must not be
  // left with nothing -- that would silently take away their ability to
  // send offers until they find another photo.
  group('a refused photo leaves the stored one alone', () {
    test('when the new file is unreadable', () async {
      final store = InMemoryDriverPhotoStore();
      final detector = _FakeDetector([_goodFace()]);
      final service = DriverPhotoService(detector, store);
      await service.replacePhoto(bigPhoto);
      final good = await store.load();

      expect(
        await service.replacePhoto(Uint8List.fromList('garbage'.codeUnits)),
        DriverPhotoRejection.undecodable,
      );
      expect(await store.load(), good);
    });

    test('when the new photo has no face in it', () async {
      final store = InMemoryDriverPhotoStore();
      final detector = _FakeDetector([_goodFace()]);
      final service = DriverPhotoService(detector, store);
      await service.replacePhoto(bigPhoto);
      final good = await store.load();

      detector.faces = [];
      expect(
        await service.replacePhoto(bigPhoto),
        DriverPhotoRejection.noFaceFound,
      );
      expect(await store.load(), good);
    });

    test('when the checker has broken since the first photo was set', () async {
      final store = InMemoryDriverPhotoStore();
      final detector = _FakeDetector([_goodFace()]);
      final service = DriverPhotoService(detector, store);
      await service.replacePhoto(bigPhoto);
      final good = await store.load();

      detector.throws = const FaceDetectorUnavailableException('model gone');
      expect(
        await service.replacePhoto(bigPhoto),
        DriverPhotoRejection.faceCheckUnavailable,
      );
      expect(await store.load(), good);
    });
  });

  group('FileDriverPhotoStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('takhi_photo_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips bytes through a real file', () async {
      final store = FileDriverPhotoStore(() async => dir.path);
      final bytes = Uint8List.fromList([1, 2, 3, 250, 251]);
      await store.save(bytes);
      expect(await store.load(), bytes);
    });

    test('reads back nothing before anything is saved', () async {
      expect(await FileDriverPhotoStore(() async => dir.path).load(), isNull);
    });

    test(
      'clear removes the photo, and clearing twice is not an error',
      () async {
        final store = FileDriverPhotoStore(() async => dir.path);
        await store.save(Uint8List.fromList([9]));
        await store.clear();
        expect(await store.load(), isNull);
        await store.clear();
        expect(await store.load(), isNull);
      },
    );

    test('a second save replaces the first', () async {
      final store = FileDriverPhotoStore(() async => dir.path);
      await store.save(Uint8List.fromList([1, 1, 1, 1]));
      await store.save(Uint8List.fromList([2, 2]));
      expect(await store.load(), Uint8List.fromList([2, 2]));
    });
  });
}
