// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import '../driver_photo_face_check.dart';
import 'blaze_face_anchors.dart';

/// How a portrait of arbitrary shape is fitted into the model's 128x128
/// input square, and how to read the resulting boxes back out.
///
/// The model takes a square. A stored portrait is *not* square --
/// `compressDriverPhoto` caps the longest edge at 512px and leaves the
/// aspect ratio alone, so a driver who picks a landscape photo from their
/// gallery hands this layer a 512x288 image. Stretching that to 128x128
/// squashes every face in it by nearly half horizontally, and BlazeFace was
/// never trained on squashed faces: the honest driver gets "no face found"
/// and no idea why.
///
/// So the image is scaled to fit and centred, with the leftover margin
/// padded. That keeps faces the shape the model expects -- and moves the
/// problem to arithmetic, where it can be tested, instead of leaving it in
/// the interpreter call, where it cannot.
class LetterboxGeometry {
  /// Multiplier taking original pixels to padded-square pixels.
  final double scale;

  /// Where the image starts inside the square, as a fraction of the square.
  final double padFractionX;
  final double padFractionY;

  /// How much of the square the image actually covers, per axis.
  final double spanFractionX;
  final double spanFractionY;

  const LetterboxGeometry({
    required this.scale,
    required this.padFractionX,
    required this.padFractionY,
    required this.spanFractionX,
    required this.spanFractionY,
  });

  /// The geometry for fitting a [width] x [height] image into the model's
  /// input square.
  factory LetterboxGeometry.forImage(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'image must have a positive size, got ${width}x$height',
      );
    }
    final longest = math.max(width, height);
    final scale = kBlazeFaceInputEdge / longest;
    final scaledWidth = width * scale;
    final scaledHeight = height * scale;
    return LetterboxGeometry(
      scale: scale,
      padFractionX:
          (kBlazeFaceInputEdge - scaledWidth) / 2 / kBlazeFaceInputEdge,
      padFractionY:
          (kBlazeFaceInputEdge - scaledHeight) / 2 / kBlazeFaceInputEdge,
      spanFractionX: scaledWidth / kBlazeFaceInputEdge,
      spanFractionY: scaledHeight / kBlazeFaceInputEdge,
    );
  }

  /// Rewrites [face] from "fraction of the padded square" into "fraction of
  /// the driver's actual photograph".
  ///
  /// Without this the size rule would be measuring faces against a frame
  /// that includes the grey bars -- so a face filling a wide photo top to
  /// bottom would measure as covering only part of the picture, and be
  /// refused as too small in a photograph it actually dominates.
  DetectedFace toOriginalFrame(DetectedFace face) => DetectedFace(
    score: face.score,
    left: (face.left - padFractionX) / spanFractionX,
    top: (face.top - padFractionY) / spanFractionY,
    width: face.width / spanFractionX,
    height: face.height / spanFractionY,
  );
}
