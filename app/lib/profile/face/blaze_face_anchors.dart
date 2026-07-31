// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

/// One SSD anchor: the point in the 128x128 input the model regresses a box
/// *relative to*.
///
/// Only the centre is carried. The bundled model
/// (`assets/models/blaze_face_short_range.tflite`) was generated with
/// MediaPipe's `fixed_anchor_size: true`, which pins every anchor's width
/// and height to 1.0 -- so storing them would be storing the constant 1
/// eight hundred and ninety-six times, and, worse, would invite a decoder
/// to multiply by it and look as though it were doing something.
///
/// Coordinates are fractions of the input square, 0..1, not pixels. That is
/// what makes [decodeBlazeFace] able to hand [DetectedFace] normalized
/// boxes without ever being told the image's real size.
class BlazeAnchor {
  final double xCenter;
  final double yCenter;
  const BlazeAnchor(this.xCenter, this.yCenter);
}

/// The anchor layout the bundled BlazeFace-front model was trained against,
/// transcribed from MediaPipe's `face_detection_front.pbtxt`:
///
/// ```
/// num_layers: 4          min_scale: 0.1484375   max_scale: 0.75
/// input_size: 128x128    strides: [8, 16, 16, 16]
/// aspect_ratios: [1.0]   interpolated_scale_aspect_ratio: 1.0
/// anchor_offset_x/y: 0.5 fixed_anchor_size: true
/// ```
///
/// These numbers are not tunable. They are a property of the *file*: the
/// model emits 896 rows in a fixed order, and row `i` is only meaningful
/// against anchor `i` of exactly this layout. Changing any constant here
/// without replacing the model silently shifts every box -- which is a
/// failure that looks like "the face check got worse" rather than like a
/// bug, so it is worth saying plainly.
const int kBlazeFaceInputEdge = 128;
const double _kMinScale = 0.1484375;
const double _kMaxScale = 0.75;
const int _kNumLayers = 4;
const List<int> _kStrides = [8, 16, 16, 16];
const double _kAnchorOffset = 0.5;

/// How many anchors the layout above produces, and therefore how many rows
/// the model's two output tensors carry.
///
/// Stated as a constant so the generator can be *checked against* it rather
/// than trusted: 16x16x2 (stride 8) + 8x8x6 (the three stride-16 layers)
/// = 512 + 384.
const int kBlazeFaceAnchorCount = 896;

/// Builds the 896 anchors in the exact order the model's output rows follow.
///
/// A faithful port of MediaPipe's `SsdAnchorsCalculator`, kept as ordinary
/// pure Dart with no dependency on the interpreter, the model file, or a
/// device -- which is the whole point. The native side of this feature is a
/// black box that cannot run in `flutter test`; the arithmetic that decides
/// where a face *is* must therefore live out here, where it can be tested.
/// The bug this app already shipped once was a face check whose engine was
/// never exercised by any test, and the answer to that is not a better
/// engine, it is less untested code around it.
List<BlazeAnchor> generateBlazeFaceAnchors() {
  final anchors = <BlazeAnchor>[];
  var layerId = 0;

  while (layerId < _kNumLayers) {
    // Layers that share a stride share a feature map, so their anchors are
    // emitted together at that map's resolution. Strides [8,16,16,16] mean
    // one pass for layer 0 and one pass covering layers 1..3.
    var anchorsPerCell = 0;
    var lastSameStrideLayer = layerId;
    while (lastSameStrideLayer < _kNumLayers &&
        _kStrides[lastSameStrideLayer] == _kStrides[layerId]) {
      // One anchor for aspect ratio 1.0, plus one for the interpolated
      // scale (`interpolated_scale_aspect_ratio: 1.0`). Their *sizes*
      // would differ, but `fixed_anchor_size` discards both, so all that
      // survives is the count -- two per layer.
      anchorsPerCell += 2;
      lastSameStrideLayer++;
    }

    final stride = _kStrides[layerId];
    final featureMapHeight = (kBlazeFaceInputEdge / stride).ceil();
    final featureMapWidth = (kBlazeFaceInputEdge / stride).ceil();

    // Row-major over the feature map, innermost loop over the anchors of a
    // single cell. This nesting order *is* the contract with the model's
    // output rows; transposing any two of these loops would produce the
    // right number of anchors paired with the wrong predictions.
    for (var y = 0; y < featureMapHeight; y++) {
      for (var x = 0; x < featureMapWidth; x++) {
        for (var i = 0; i < anchorsPerCell; i++) {
          anchors.add(
            BlazeAnchor(
              (x + _kAnchorOffset) / featureMapWidth,
              (y + _kAnchorOffset) / featureMapHeight,
            ),
          );
        }
      }
    }

    layerId = lastSameStrideLayer;
  }

  return List.unmodifiable(anchors);
}

/// The scale schedule MediaPipe would have computed for each layer.
///
/// Unused by the decoder -- `fixed_anchor_size: true` throws these away --
/// and kept only so the test suite can demonstrate *that* it throws them
/// away, rather than the file quietly implying anchor sizes are involved.
double blazeFaceLayerScale(int layerId) =>
    _kMinScale + (_kMaxScale - _kMinScale) * layerId / (_kNumLayers - 1);

/// Numerically safe logistic. The model emits raw logits, and a saturated
/// one (`-inf` after a bad decode, or a large magnitude from a confident
/// negative) would otherwise produce `NaN` through `exp`, which compares
/// false against every threshold and so reads as "not a face" instead of
/// as a broken input.
double blazeFaceSigmoid(double logit) {
  final clipped = logit.clamp(-100.0, 100.0);
  return 1.0 / (1.0 + math.exp(-clipped));
}
