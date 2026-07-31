// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proof, on real hardware, that a driver can set a profile photo.
//
// This is the test that had to exist. v0.2.0 shipped a MANDATORY portrait
// gate (`driverOfferBlock`, enforced by `OfferService.sendOffer`) wired to
// `UnavailableFaceDetector`, which throws for every image -- so no driver
// anywhere could send a single offer. 848 unit tests passed, because every
// one of them replaced the detector with a stub that accepts.
//
// The lesson is not "write more unit tests". A unit test on a desktop VM
// physically cannot run TFLite: it is a native library with no Android .so
// to load. The only place the claim "a driver can set a portrait" can be
// checked is on a device, so that is where it is checked.
//
// Run with:  flutter test integration_test/face_detector_device_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:takhi/profile/driver_photo_codec.dart';
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/driver_photo_rules.dart';
import 'package:takhi/profile/face/tflite_face_detector.dart';

import 'synthetic_face.dart';

/// A landscape with no person in it: sky gradient over a dark ridge.
///
/// One of the exact cases the driver asked for -- «уул ус мод» -- and the
/// reason the check exists at all. Drawn rather than downloaded so it needs
/// no fixture and cannot rot.
Uint8List _mountainJpeg() {
  final image = img.Image(width: 256, height: 256);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      // Sky: pale at the horizon, deeper blue at the top.
      image.setPixelRgb(x, y, 120 + y ~/ 4, 160 + y ~/ 6, 220 - y ~/ 8);
    }
  }
  // Two overlapping ridges.
  for (var x = 0; x < 256; x++) {
    final ridge = 150 + ((x - 128).abs() ~/ 2);
    for (var y = ridge; y < 256; y++) {
      image.setPixelRgb(x, y, 70, 78, 66);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late TfliteFaceDetector detector;

  setUp(() => detector = TfliteFaceDetector());
  tearDown(() => detector.close());

  group('the bundled model on this device', () {
    testWidgets('loads and runs at all', (tester) async {
      // The single most important assertion in the file. If the asset is
      // missing from the bundle, or the native library will not load on
      // this ABI, this throws FaceDetectorUnavailableException -- which is
      // precisely what every driver hit in v0.2.0.
      final faces = await detector.detect(_mountainJpeg());
      expect(faces, isA<List<DetectedFace>>());
    });

    testWidgets('finds a face in a portrait, and the app accepts it', (
      tester,
    ) async {
      final jpeg = base64Decode(kSyntheticFaceJpegBase64);
      final faces = await detector.detect(jpeg);

      expect(
        faces,
        hasLength(1),
        reason: 'a plain frontal headshot must read as exactly one person',
      );
      expect(faces.single.score, greaterThan(kMinFaceDetectionScore));
      expect(
        faceCheckProblem(faces),
        isNull,
        reason:
            'this is the photo a driver takes of themselves; if the app '
            'refuses it, the app is unusable for drivers',
      );
    });

    testWidgets('finds no face in a mountain landscape', (tester) async {
      final faces = await detector.detect(_mountainJpeg());
      expect(
        faceCheckProblem(faces),
        DriverPhotoRejection.noFaceFound,
        reason:
            'уул ус мод -- the case the driver explicitly asked to be '
            'rejected',
      );
    });
  });

  group('the whole portrait pipeline, end to end', () {
    testWidgets('a portrait survives compression and is still accepted', (
      tester,
    ) async {
      // The real path: `DriverPhotoService.replacePhoto` compresses first
      // and checks the COMPRESSED bytes, so the thing proved acceptable
      // here must be the thing that actually gets stored and sent.
      final compressed = compressDriverPhoto(
        base64Decode(kSyntheticFaceJpegBase64),
      );
      expect(compressed, isA<DriverPhotoCompressed>());
      final jpeg = (compressed as DriverPhotoCompressed).jpegBytes;

      expect(
        await checkDriverPhotoFace(detector, jpeg),
        isNull,
        reason: 'compression must not destroy the face the check needs',
      );
      expect(jpeg.length, lessThanOrEqualTo(kDriverPhotoMaxBytes));
    });

    testWidgets('a wide photo with an off-centre face is still found', (
      tester,
    ) async {
      // Guards the letterbox path specifically. A driver whose gallery
      // photo is landscape used to be squashed to a square before the model
      // saw it; a squashed face is one BlazeFace was never trained on.
      final portrait = img.decodeImage(base64Decode(kSyntheticFaceJpegBase64))!;
      final wide = img.Image(width: 512, height: 288);
      img.fill(wide, color: img.ColorRgb8(200, 200, 200));
      img.compositeImage(
        wide,
        img.copyResize(portrait, width: 240, height: 240),
        dstX: 40,
        dstY: 24,
      );

      final faces = await detector.detect(
        Uint8List.fromList(img.encodeJpg(wide, quality: 88)),
      );
      expect(faces, hasLength(1));
      // And it must land where the face actually is -- left of centre --
      // rather than somewhere the padding put it.
      expect(faces.single.left + faces.single.width / 2, lessThan(0.5));
    });
  });
}
