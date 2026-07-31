// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/driver_photo_rules.dart';

/// A square face covering [areaFraction] of the frame, centred, at [score].
DetectedFace _face({double score = 0.9, double areaFraction = 0.25}) {
  final side = math.sqrt(areaFraction);
  return DetectedFace(
    score: score,
    left: (1 - side) / 2,
    top: (1 - side) / 2,
    width: side,
    height: side,
  );
}

class _FakeDetector implements FaceDetector {
  final List<DetectedFace> faces;
  final Object? throws;
  int calls = 0;
  _FakeDetector(this.faces, {this.throws});

  @override
  Future<List<DetectedFace>> detect(Uint8List jpegBytes) async {
    calls++;
    final error = throws;
    if (error != null) throw error;
    return faces;
  }
}

void main() {
  group('faceCheckProblem', () {
    test('accepts exactly one confident, large-enough face', () {
      expect(faceCheckProblem([_face()]), isNull);
    });

    test('rejects a photo with no detections -- a mountain, a logo, a car', () {
      expect(faceCheckProblem([]), DriverPhotoRejection.noFaceFound);
    });

    test('rejects a group photo: a rider cannot tell which one is driving', () {
      expect(
        faceCheckProblem([_face(), _face()]),
        DriverPhotoRejection.multipleFaces,
      );
    });

    test('rejects a face too small to recognise a stranger by', () {
      expect(
        faceCheckProblem([_face(areaFraction: kMinFaceAreaFraction / 2)]),
        DriverPhotoRejection.faceTooSmall,
      );
    });

    test('accepts a face exactly on the size floor', () {
      expect(
        faceCheckProblem([_face(areaFraction: kMinFaceAreaFraction)]),
        isNull,
      );
    });

    test('accepts a face exactly on the confidence floor', () {
      expect(faceCheckProblem([_face(score: kMinFaceDetectionScore)]), isNull);
    });
  });

  group('faceCheckProblem filters by confidence before counting', () {
    // The ordering is the whole subtlety. A wall smudge scoring 0.2 next to
    // a real face must not be counted as a second person -- that would
    // reject a perfectly good portrait, and tell the driver something
    // ("there are two faces here") that is not true of their photo.
    test('a low-confidence smudge beside a real face does not make it a '
        'group photo', () {
      expect(faceCheckProblem([_face(), _face(score: 0.2)]), isNull);
    });

    test('a photo containing only low-confidence detections reads as no '
        'face, not as a face', () {
      expect(
        faceCheckProblem([_face(score: 0.3), _face(score: 0.1)]),
        DriverPhotoRejection.noFaceFound,
      );
    });

    test('two confident faces still reject even with noise around them', () {
      expect(
        faceCheckProblem([_face(), _face(), _face(score: 0.1)]),
        DriverPhotoRejection.multipleFaces,
      );
    });
  });

  group('DetectedFace.visibleAreaFraction', () {
    test('is the plain area for a box inside the frame', () {
      const face = DetectedFace(
        score: 1,
        left: 0.25,
        top: 0.25,
        width: 0.5,
        height: 0.5,
      );
      expect(face.visibleAreaFraction, closeTo(0.25, 1e-9));
    });

    // A detector that regresses a box running off the edge reports more
    // area than the picture has. Counting it raw would let a detection that
    // is mostly outside the frame clear a floor whose entire purpose is to
    // insist the face is inside it.
    test('counts only the part inside the frame', () {
      const overflowing = DetectedFace(
        score: 1,
        left: -0.5,
        top: -0.5,
        width: 1.0,
        height: 1.0,
      );
      expect(overflowing.visibleAreaFraction, closeTo(0.25, 1e-9));
    });

    test('is zero for a box entirely outside the frame', () {
      const outside = DetectedFace(
        score: 1,
        left: 2.0,
        top: 2.0,
        width: 1.0,
        height: 1.0,
      );
      expect(outside.visibleAreaFraction, 0);
    });

    test('a huge off-image box is rejected as too small, not accepted as '
        'enormous', () {
      const mostlyOutside = DetectedFace(
        score: 1,
        left: 0.98,
        top: 0.0,
        width: 4.0,
        height: 4.0,
      );
      expect(
        faceCheckProblem([mostlyOutside]),
        DriverPhotoRejection.faceTooSmall,
      );
    });
  });

  group('checkDriverPhotoFace', () {
    final bytes = Uint8List.fromList([1, 2, 3]);

    test('passes the bytes to the detector and applies the rules', () async {
      final detector = _FakeDetector([_face()]);
      expect(await checkDriverPhotoFace(detector, bytes), isNull);
      expect(detector.calls, 1);
    });

    test('reports the rule that failed', () async {
      expect(
        await checkDriverPhotoFace(_FakeDetector([]), bytes),
        DriverPhotoRejection.noFaceFound,
      );
    });

    // Fail closed. A checker that approves everything the moment its engine
    // breaks is worse than no checker: the promise stays on screen after
    // the mechanism behind it is gone, and nothing says so.
    test('a detector that cannot run rejects rather than approves', () async {
      final detector = _FakeDetector(
        const [],
        throws: const FaceDetectorUnavailableException('no model bundled'),
      );
      expect(
        await checkDriverPhotoFace(detector, bytes),
        DriverPhotoRejection.faceCheckUnavailable,
      );
    });

    test('any other failure inside the engine also rejects', () async {
      // The thrower is native, platform-specific code whose failure modes
      // this layer cannot enumerate -- what it must never do is turn "the
      // checker broke" into "the photo is fine".
      for (final error in <Object>[
        StateError('interpreter closed'),
        ArgumentError('bad tensor shape'),
        Exception('libtensorflowlite_jni.so not found'),
      ]) {
        expect(
          await checkDriverPhotoFace(
            _FakeDetector(const [], throws: error),
            bytes,
          ),
          DriverPhotoRejection.faceCheckUnavailable,
          reason: 'a $error escaped instead of becoming a rejection',
        );
      }
    });

    test('the shipped placeholder detector refuses everything', () async {
      expect(
        await checkDriverPhotoFace(const UnavailableFaceDetector(), bytes),
        DriverPhotoRejection.faceCheckUnavailable,
      );
    });
  });
}
