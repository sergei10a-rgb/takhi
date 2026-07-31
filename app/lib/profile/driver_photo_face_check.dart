// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import 'driver_photo_rules.dart';

/// One face the detector believes it found.
class DetectedFace {
  /// The detector's own confidence, 0..1.
  final double score;

  /// The bounding box, **normalized to the image**: 0..1 on both axes, so
  /// this layer never needs to know the pixel dimensions and the rules can
  /// be expressed as fractions of the frame.
  ///
  /// May legitimately fall partly outside 0..1 -- BlazeFace-style detectors
  /// regress boxes that run off the edge when a face is cropped by the
  /// frame. [visibleAreaFraction] is what deals with that.
  final double left, top, width, height;

  const DetectedFace({
    required this.score,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// How much of the frame this face actually covers, counting only the
  /// part inside it.
  ///
  /// Clamping to the frame is not pedantry: an off-image box is how a
  /// "face" occupying 400% of the picture gets reported, and taking the raw
  /// area would let a detection that is mostly outside the photo sail past
  /// the [kMinFaceAreaFraction] floor that exists to insist the face is
  /// actually *in* the picture and close enough to recognise.
  double get visibleAreaFraction {
    final visibleWidth = math.min(left + width, 1.0) - math.max(left, 0.0);
    final visibleHeight = math.min(top + height, 1.0) - math.max(top, 0.0);
    if (visibleWidth <= 0 || visibleHeight <= 0) return 0;
    return visibleWidth * visibleHeight;
  }
}

/// Thrown by a [FaceDetector] that cannot run at all -- no model in the
/// bundle, native library missing, unsupported platform. Distinct from
/// "found no faces", which is a normal answer about a photograph rather
/// than a failure of the machinery.
class FaceDetectorUnavailableException implements Exception {
  final String reason;
  const FaceDetectorUnavailableException(this.reason);
  @override
  String toString() => 'FaceDetectorUnavailableException: $reason';
}

/// Finds faces in an image. One method, deliberately: everything else about
/// the check -- the confidence floor, the exactly-one rule, the size floor
/// -- lives in [faceCheckProblem] as ordinary testable Dart, so swapping the
/// engine cannot quietly change the policy.
///
/// The shipped implementation is expected to be an on-device TFLite
/// BlazeFace model with no network access whatsoever
/// (`test/profile/driver_photo_offline_test.dart` holds that line
/// mechanically). Any implementation that reaches the network to classify a
/// driver's face would defeat the point of the feature.
abstract interface class FaceDetector {
  /// Detections in [jpegBytes], boxes normalized to the image.
  Future<List<DetectedFace>> detect(Uint8List jpegBytes);
}

/// The placeholder registered until an on-device model is bundled.
///
/// It refuses rather than approves, and that direction is the whole point.
/// A check that waves everything through when its engine is missing is
/// worse than having no check, because the promise stays on the screen
/// after the mechanism behind it is gone -- and the failure is invisible,
/// so nobody finds out. Refusing is loud: the first driver to try to set a
/// photo is told the checker is not working, which is a bug report. That is
/// the failure mode to prefer while the model is still being wired in.
class UnavailableFaceDetector implements FaceDetector {
  const UnavailableFaceDetector();

  @override
  Future<List<DetectedFace>> detect(Uint8List jpegBytes) async {
    throw const FaceDetectorUnavailableException(
      'no on-device face model is bundled in this build',
    );
  }
}

/// Applies the portrait rules to [detections]. `null` means the photo
/// passes.
///
/// Pure and synchronous, taking already-computed detections rather than an
/// image, so every rule and every boundary below is testable without a
/// model, a native library or a device.
///
/// Order matters and is deliberate: confidence filtering happens *first*,
/// so that a low-confidence smudge on a wall cannot be counted as a second
/// person and turn a perfectly good portrait into a baffling "there are two
/// faces in this photo".
DriverPhotoRejection? faceCheckProblem(List<DetectedFace> detections) {
  final confident = detections
      .where((face) => face.score >= kMinFaceDetectionScore)
      .toList(growable: false);

  if (confident.isEmpty) return DriverPhotoRejection.noFaceFound;
  if (confident.length > 1) return DriverPhotoRejection.multipleFaces;
  if (confident.single.visibleAreaFraction < kMinFaceAreaFraction) {
    return DriverPhotoRejection.faceTooSmall;
  }
  return null;
}

/// Runs [detector] over [jpegBytes] and applies [faceCheckProblem] to what
/// comes back. `null` means the photo passes.
///
/// A detector that throws -- for any reason, not only
/// [FaceDetectorUnavailableException] -- becomes
/// [DriverPhotoRejection.faceCheckUnavailable] rather than an exception
/// escaping into the profile screen. Catching broadly is right here
/// precisely because the thrower is a native, platform-specific engine
/// whose failure modes this layer cannot enumerate; what it must never do
/// is turn "the checker broke" into "the photo is fine".
Future<DriverPhotoRejection?> checkDriverPhotoFace(
  FaceDetector detector,
  Uint8List jpegBytes,
) async {
  final List<DetectedFace> detections;
  try {
    detections = await detector.detect(jpegBytes);
  } on Object {
    return DriverPhotoRejection.faceCheckUnavailable;
  }
  return faceCheckProblem(detections);
}
