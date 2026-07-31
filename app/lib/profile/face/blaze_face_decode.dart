// SPDX-License-Identifier: AGPL-3.0-or-later
import '../driver_photo_face_check.dart';
import 'blaze_face_anchors.dart';

/// How many floats the model emits per anchor row.
///
/// Four for the box, then six 2D keypoints (eyes, nose, mouth, ears) that
/// this app has no use for -- it asks "is there one recognisable person
/// here", not where their nose is. They are skipped rather than parsed,
/// but the stride has to be right or every box after the first would be
/// read out of the wrong offset.
const int kBlazeFaceRegressorStride = 16;

/// Boxes overlapping more than this are treated as the same face.
///
/// BlazeFace fires several neighbouring anchors on one face, and without
/// suppression a single driver photographed head-on becomes "there are 4
/// people in this picture" -- which `faceCheckProblem` would refuse as a
/// group photo. The failure would look like a policy being applied, not
/// like a decoder bug, which is exactly why it is worth a named constant
/// and a test.
const double kBlazeFaceNmsIouThreshold = 0.3;

/// Detections below this are dropped before suppression.
///
/// Deliberately *lower* than `kMinFaceDetectionScore`, the floor the app's
/// policy applies in `faceCheckProblem`. This one exists only to keep the
/// suppression loop from grinding over hundreds of near-zero rows; the
/// decision about what counts as a face is not made here. Raising it to
/// the policy value would move a policy into the decoder, where nothing
/// tests it as policy.
const double _kDecodeScoreFloor = 0.1;

/// Turns one BlazeFace inference into the app's own [DetectedFace] list.
///
/// [regressors] is the flattened `[1, 896, 16]` output and [scores] the
/// flattened `[1, 896, 1]` output -- raw logits, not probabilities.
/// [anchors] must be [generateBlazeFaceAnchors]' result, in that order:
/// row `i` is meaningless against any other anchor.
///
/// Everything here is ordinary arithmetic on plain lists, with no reference
/// to the interpreter, the model file, `dart:ffi` or a device. That is the
/// point of the split -- `TfliteFaceDetector` is a shell that cannot be run
/// in `flutter test`, so nothing that can be wrong in an interesting way is
/// allowed to live inside it.
List<DetectedFace> decodeBlazeFace({
  required List<double> regressors,
  required List<double> scores,
  required List<BlazeAnchor> anchors,
}) {
  // A shape mismatch means the bundled model is not the one this decoder
  // was written for. Failing loudly beats decoding garbage into confident
  // boxes: a wrong-model build must look broken, not lenient.
  if (scores.length != anchors.length) {
    throw StateError(
      'BlazeFace score tensor has ${scores.length} rows but '
      '${anchors.length} anchors were generated -- the bundled model does '
      'not match this decoder.',
    );
  }
  if (regressors.length != anchors.length * kBlazeFaceRegressorStride) {
    throw StateError(
      'BlazeFace regressor tensor has ${regressors.length} floats, expected '
      '${anchors.length * kBlazeFaceRegressorStride}.',
    );
  }

  final candidates = <DetectedFace>[];
  for (var i = 0; i < anchors.length; i++) {
    final score = blazeFaceSigmoid(scores[i]);
    if (score < _kDecodeScoreFloor) continue;

    final base = i * kBlazeFaceRegressorStride;
    final anchor = anchors[i];

    // The model regresses offsets in *input pixels* against an anchor whose
    // size is fixed at 1.0, so dividing by the 128px input edge is the whole
    // of the conversion back to fractions of the frame.
    final xCenter = regressors[base] / kBlazeFaceInputEdge + anchor.xCenter;
    final yCenter = regressors[base + 1] / kBlazeFaceInputEdge + anchor.yCenter;
    final width = regressors[base + 2] / kBlazeFaceInputEdge;
    final height = regressors[base + 3] / kBlazeFaceInputEdge;

    // A negative regressed extent is not a face turned inside out, it is a
    // row that decoded to nonsense. Dropping it is safer than handing
    // `faceCheckProblem` a box whose area computes as positive from two
    // negatives.
    if (width <= 0 || height <= 0) continue;

    candidates.add(
      DetectedFace(
        score: score,
        // `DetectedFace` is corner-based; the model is centre-based. Boxes
        // are deliberately NOT clamped to the frame here: a face cropped by
        // the edge legitimately regresses outside 0..1, and
        // `DetectedFace.visibleAreaFraction` is the thing that already knows
        // how to account for that. Clamping would quietly turn a face that
        // is half out of shot into a smaller face that is fully in it.
        left: xCenter - width / 2,
        top: yCenter - height / 2,
        width: width,
        height: height,
      ),
    );
  }

  return _suppressOverlaps(candidates);
}

/// Classic greedy non-maximum suppression: keep the most confident box,
/// discard everything that overlaps it too much, repeat.
///
/// Weighted-average NMS (what MediaPipe itself uses) would nudge the kept
/// box towards its neighbours for a slightly steadier crop. It is not worth
/// it here: nothing downstream draws this box. The only questions asked of
/// it are "how many are there" and "is it big enough", and greedy
/// suppression answers both identically.
List<DetectedFace> _suppressOverlaps(List<DetectedFace> candidates) {
  final remaining = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
  final kept = <DetectedFace>[];

  while (remaining.isNotEmpty) {
    final best = remaining.removeAt(0);
    kept.add(best);
    remaining.removeWhere(
      (other) =>
          _intersectionOverUnion(best, other) > kBlazeFaceNmsIouThreshold,
    );
  }

  return kept;
}

/// Intersection over union of two boxes, 0 when they do not touch.
double _intersectionOverUnion(DetectedFace a, DetectedFace b) {
  final left = a.left > b.left ? a.left : b.left;
  final top = a.top > b.top ? a.top : b.top;
  final right = (a.left + a.width) < (b.left + b.width)
      ? a.left + a.width
      : b.left + b.width;
  final bottom = (a.top + a.height) < (b.top + b.height)
      ? a.top + a.height
      : b.top + b.height;

  final intersectWidth = right - left;
  final intersectHeight = bottom - top;
  if (intersectWidth <= 0 || intersectHeight <= 0) return 0;

  final intersection = intersectWidth * intersectHeight;
  final union = a.width * a.height + b.width * b.height - intersection;
  // Two degenerate boxes cannot overlap "completely"; guard the divide
  // rather than returning a NaN that every comparison below would treat as
  // "does not overlap".
  if (union <= 0) return 0;
  return intersection / union;
}
