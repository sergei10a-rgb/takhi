// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The anchor layout and the box decode are the two places a face detector
// goes subtly wrong: right number of boxes in the wrong places, or right
// places at the wrong scale. Neither shows up as a crash -- it shows up as
// "the photo check seems bad", months later, from a driver who cannot
// explain it.
//
// None of this needs the interpreter, the .tflite file, or a device, which
// is exactly why the arithmetic was pulled out of the shell that does.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/face/blaze_face_anchors.dart';
import 'package:takhi/profile/face/blaze_face_decode.dart';

/// A regressor tensor of all zeros, into which single rows are written.
List<double> _emptyRegressors(int anchorCount) =>
    List<double>.filled(anchorCount * kBlazeFaceRegressorStride, 0);

/// A score tensor of large negative logits -- sigmoid(-30) is ~1e-13, so
/// every row reads as "certainly not a face" until one is overwritten.
List<double> _emptyScores(int anchorCount) =>
    List<double>.filled(anchorCount, -30);

/// Writes a box into row [index], in the model's own units: offsets from
/// the anchor centre in 128px input pixels.
void _writeBox(
  List<double> regressors,
  int index, {
  required double dxPx,
  required double dyPx,
  required double widthPx,
  required double heightPx,
}) {
  final base = index * kBlazeFaceRegressorStride;
  regressors[base] = dxPx;
  regressors[base + 1] = dyPx;
  regressors[base + 2] = widthPx;
  regressors[base + 3] = heightPx;
}

void main() {
  final anchors = generateBlazeFaceAnchors();

  group('anchor layout', () {
    test('produces exactly the 896 rows the model emits', () {
      expect(anchors.length, kBlazeFaceAnchorCount);
    });

    test('the stride-8 layer contributes 16x16x2 anchors and the three '
        'stride-16 layers 8x8x6', () {
      // The split matters, not just the total: 512 + 384 and 384 + 512 both
      // sum to 896, and only one of them lines up with the model's rows.
      // The first 512 must come from a 16x16 grid, so their distinct
      // x-centres number 16.
      final firstLayer = anchors.take(512);
      expect(firstLayer.map((a) => a.xCenter).toSet().length, 16);
      final rest = anchors.skip(512);
      expect(rest.length, 384);
      expect(rest.map((a) => a.xCenter).toSet().length, 8);
    });

    test('centres sit in the middle of their cell, not on its corner', () {
      // Half a cell in from the origin: 0.5/16 for the stride-8 map.
      expect(anchors.first.xCenter, closeTo(0.5 / 16, 1e-12));
      expect(anchors.first.yCenter, closeTo(0.5 / 16, 1e-12));
      // ...and the last stride-16 cell is half a cell short of the far edge.
      expect(anchors.last.xCenter, closeTo(7.5 / 8, 1e-12));
      expect(anchors.last.yCenter, closeTo(7.5 / 8, 1e-12));
    });

    test('every anchor lies inside the frame', () {
      for (final a in anchors) {
        expect(a.xCenter, inInclusiveRange(0, 1));
        expect(a.yCenter, inInclusiveRange(0, 1));
      }
    });

    test('consecutive anchors come in pairs sharing one cell', () {
      // Two anchors per cell, so rows 0 and 1 are the same point. If the
      // loop nesting were transposed this would fail, and a transposed
      // nesting is the single most likely way to get 896 wrong anchors.
      expect(anchors[0].xCenter, anchors[1].xCenter);
      expect(anchors[0].yCenter, anchors[1].yCenter);
      expect(anchors[2].xCenter, greaterThan(anchors[1].xCenter));
    });

    test('the interpolated scale schedule spans min to max', () {
      expect(blazeFaceLayerScale(0), closeTo(0.1484375, 1e-12));
      expect(blazeFaceLayerScale(3), closeTo(0.75, 1e-12));
    });
  });

  group('sigmoid', () {
    test('maps 0 to one half', () {
      expect(blazeFaceSigmoid(0), closeTo(0.5, 1e-12));
    });

    test('saturates without producing NaN or infinity', () {
      // A raw logit of -1e9 through a naive exp() is `Infinity`, and
      // 1/(1+Infinity) is 0 -- but +1e9 gives exp(-1e9) = 0 fine while a
      // sign slip gives NaN, which compares false against every threshold
      // and so silently reads as "not a face".
      // Clamping at -100 leaves 1/(1+e^100) ~ 3.7e-44 -- a subnormal, but a
      // real finite number, which is the whole point. What must never come
      // back is NaN or infinity.
      expect(blazeFaceSigmoid(-1e9), closeTo(0, 1e-40));
      expect(blazeFaceSigmoid(1e9), closeTo(1, 1e-40));
      expect(blazeFaceSigmoid(-1e9).isFinite, isTrue);
      expect(blazeFaceSigmoid(1e9).isFinite, isTrue);
    });
  });

  group('decode', () {
    test('places a centred, half-frame box where it was written', () {
      final regressors = _emptyRegressors(anchors.length);
      final scores = _emptyScores(anchors.length);

      // Pick an anchor near the middle of the stride-8 grid and ask for a
      // box centred exactly on it, 64px square out of a 128px input -- so
      // half the frame.
      const row = 8 * 16 * 2 + 8 * 2; // grid cell (x=8, y=8), first anchor
      _writeBox(regressors, row, dxPx: 0, dyPx: 0, widthPx: 64, heightPx: 64);
      scores[row] = 10; // sigmoid(10) ~ 0.99995

      final faces = decodeBlazeFace(
        regressors: regressors,
        scores: scores,
        anchors: anchors,
      );

      expect(faces, hasLength(1));
      final face = faces.single;
      expect(face.score, greaterThan(0.99));
      expect(face.width, closeTo(0.5, 1e-9));
      expect(face.height, closeTo(0.5, 1e-9));
      // Centre lands on the anchor: cell 8 of 16, so 8.5/16.
      expect(face.left + face.width / 2, closeTo(8.5 / 16, 1e-9));
      expect(face.top + face.height / 2, closeTo(8.5 / 16, 1e-9));
    });

    test('a regressed offset moves the box off its anchor by that many '
        'input pixels', () {
      final regressors = _emptyRegressors(anchors.length);
      final scores = _emptyScores(anchors.length);
      const row = 0;
      // 12.8px of a 128px input is exactly a tenth of the frame.
      _writeBox(
        regressors,
        row,
        dxPx: 12.8,
        dyPx: -12.8,
        widthPx: 32,
        heightPx: 32,
      );
      scores[row] = 10;

      final face = decodeBlazeFace(
        regressors: regressors,
        scores: scores,
        anchors: anchors,
      ).single;

      expect(face.left + face.width / 2, closeTo(0.5 / 16 + 0.1, 1e-9));
      expect(face.top + face.height / 2, closeTo(0.5 / 16 - 0.1, 1e-9));
    });

    test('an empty picture yields no faces at all', () {
      final faces = decodeBlazeFace(
        regressors: _emptyRegressors(anchors.length),
        scores: _emptyScores(anchors.length),
        anchors: anchors,
      );
      expect(faces, isEmpty);
    });

    test('several anchors firing on ONE face collapse to one detection', () {
      // This is the case that, left unsuppressed, turns a driver's own
      // portrait into "there are 4 people in this photo" -- a refusal that
      // looks like the group-photo policy working rather than like a
      // decoder that never suppressed anything.
      final regressors = _emptyRegressors(anchors.length);
      final scores = _emptyScores(anchors.length);
      for (final row in [100, 101, 102, 103]) {
        final anchor = anchors[row];
        // Aim every one of them at the same absolute point, so they
        // genuinely describe one face rather than four near it.
        _writeBox(
          regressors,
          row,
          dxPx: (0.5 - anchor.xCenter) * kBlazeFaceInputEdge,
          dyPx: (0.5 - anchor.yCenter) * kBlazeFaceInputEdge,
          widthPx: 64,
          heightPx: 64,
        );
        scores[row] = 8;
      }

      final faces = decodeBlazeFace(
        regressors: regressors,
        scores: scores,
        anchors: anchors,
      );
      expect(faces, hasLength(1));
    });

    test('two people standing apart stay two detections', () {
      // The other half of the same guarantee: suppression must not be so
      // eager that a real group photo passes as one person.
      final regressors = _emptyRegressors(anchors.length);
      final scores = _emptyScores(anchors.length);

      // Two rows far apart in the tensor; both must be < 896.
      for (final (row, cx) in [(200, 0.25), (800, 0.75)]) {
        final anchor = anchors[row];
        _writeBox(
          regressors,
          row,
          dxPx: (cx - anchor.xCenter) * kBlazeFaceInputEdge,
          dyPx: (0.5 - anchor.yCenter) * kBlazeFaceInputEdge,
          widthPx: 32,
          heightPx: 32,
        );
        scores[row] = 8;
      }

      final faces = decodeBlazeFace(
        regressors: regressors,
        scores: scores,
        anchors: anchors,
      );
      expect(faces, hasLength(2));
    });

    test('the most confident of an overlapping pair is the one kept', () {
      final regressors = _emptyRegressors(anchors.length);
      final scores = _emptyScores(anchors.length);
      for (final (row, logit) in [(300, 2.0), (301, 6.0)]) {
        final anchor = anchors[row];
        _writeBox(
          regressors,
          row,
          dxPx: (0.5 - anchor.xCenter) * kBlazeFaceInputEdge,
          dyPx: (0.5 - anchor.yCenter) * kBlazeFaceInputEdge,
          widthPx: 64,
          heightPx: 64,
        );
        scores[row] = logit;
      }

      final face = decodeBlazeFace(
        regressors: regressors,
        scores: scores,
        anchors: anchors,
      ).single;
      expect(face.score, closeTo(blazeFaceSigmoid(6), 1e-9));
    });

    test('a box regressed off the edge is kept unclamped, so the size rule '
        'can see how little of it is showing', () {
      final regressors = _emptyRegressors(anchors.length);
      final scores = _emptyScores(anchors.length);
      const row = 0;
      // Huge box centred on the very first anchor, i.e. mostly off frame.
      _writeBox(regressors, row, dxPx: 0, dyPx: 0, widthPx: 256, heightPx: 256);
      scores[row] = 10;

      final face = decodeBlazeFace(
        regressors: regressors,
        scores: scores,
        anchors: anchors,
      ).single;

      // Unclamped: the box really is twice the frame wide and starts well
      // outside it. Clamping here would have thrown away the very
      // information `visibleAreaFraction` exists to weigh.
      expect(face.width, closeTo(2.0, 1e-9));
      expect(face.height, closeTo(2.0, 1e-9));
      expect(face.left, closeTo(0.5 / 16 - 1.0, 1e-9));
      expect(face.top, closeTo(0.5 / 16 - 1.0, 1e-9));
      // The raw area is 4.0 -- four times the picture. What the app's rule
      // actually weighs is the part inside the frame, which saturates at 1.
      expect(face.width * face.height, closeTo(4.0, 1e-9));
      expect(face.visibleAreaFraction, closeTo(1.0, 1e-9));
    });

    test('a row that decodes to a negative extent is dropped, not squared '
        'into a positive area', () {
      final regressors = _emptyRegressors(anchors.length);
      final scores = _emptyScores(anchors.length);
      _writeBox(regressors, 0, dxPx: 0, dyPx: 0, widthPx: -64, heightPx: -64);
      scores[0] = 10;

      expect(
        decodeBlazeFace(
          regressors: regressors,
          scores: scores,
          anchors: anchors,
        ),
        isEmpty,
      );
    });
  });

  group('a model that is not the one this decoder was written for', () {
    test('is refused rather than decoded into confident nonsense', () {
      expect(
        () => decodeBlazeFace(
          regressors: _emptyRegressors(10),
          scores: _emptyScores(10),
          anchors: anchors,
        ),
        throwsStateError,
      );
    });

    test('a score tensor of the right length but regressors of the wrong '
        'one is caught too', () {
      expect(
        () => decodeBlazeFace(
          regressors: _emptyRegressors(anchors.length - 1),
          scores: _emptyScores(anchors.length),
          anchors: anchors,
        ),
        throwsStateError,
      );
    });
  });

  group('the decoder hands results the app policy can judge', () {
    test('one confident, large, centred face passes faceCheckProblem', () {
      final regressors = _emptyRegressors(anchors.length);
      final scores = _emptyScores(anchors.length);
      const row = 8 * 16 * 2 + 8 * 2;
      final anchor = anchors[row];
      _writeBox(
        regressors,
        row,
        dxPx: (0.5 - anchor.xCenter) * kBlazeFaceInputEdge,
        dyPx: (0.5 - anchor.yCenter) * kBlazeFaceInputEdge,
        widthPx: 80,
        heightPx: 80,
      );
      scores[row] = 10;

      final faces = decodeBlazeFace(
        regressors: regressors,
        scores: scores,
        anchors: anchors,
      );
      expect(faceCheckProblem(faces), isNull);
    });
  });
}
