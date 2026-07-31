// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../driver_photo_face_check.dart';
import 'blaze_face_anchors.dart';
import 'blaze_face_decode.dart';
import 'blaze_face_letterbox.dart';

/// Where the bundled MediaPipe model lives. Apache-2.0, ~224KB, shipped in
/// the APK -- never fetched. `driver_photo_offline_test.dart` enforces that
/// this whole path stays free of network calls, because a face check that
/// phones home would turn a driver setting up their profile into a tracked
/// event and would stop working the moment they were out of coverage,
/// which in Mongolia is most of the country.
const String kBlazeFaceAssetPath =
    'assets/models/blaze_face_short_range.tflite';

/// The grey the letterbox margin is filled with.
///
/// Mid-grey rather than black or white: the padding must read as "nothing
/// here" to the model, and a hard black bar against a bright portrait is a
/// strong edge that a detector can find structure in.
const int _kPadLevel = 128;

/// A real on-device face detector, replacing [UnavailableFaceDetector].
///
/// **This class is deliberately almost empty.** Everything that can be
/// wrong in an interesting way -- the anchor layout, the box decode,
/// non-maximum suppression, the letterbox mapping -- lives in the three
/// pure-Dart files beside it, under test. What is left here is loading a
/// file, resizing an image and calling an interpreter, none of which
/// `flutter test` can execute on a desktop VM.
///
/// That split is not tidiness. The bug this replaces was a face check whose
/// engine threw on every photo while 848 tests passed, because every one of
/// them substituted the engine. The lesson taken from it is that the
/// untestable part of a feature must be made as small and as boring as
/// possible, not that it needs better tests -- it cannot have any.
class TfliteFaceDetector implements FaceDetector {
  final List<BlazeAnchor> _anchors;
  Interpreter? _interpreter;

  TfliteFaceDetector() : _anchors = generateBlazeFaceAnchors();

  /// Test seam: lets a caller supply an already-built interpreter (for an
  /// integration test running on a real device) instead of loading the
  /// bundled asset.
  TfliteFaceDetector.withInterpreter(Interpreter interpreter)
    : _anchors = generateBlazeFaceAnchors(),
      _interpreter = interpreter;

  Future<Interpreter> _ensureInterpreter() async {
    final existing = _interpreter;
    if (existing != null) return existing;
    try {
      // Kept for the life of the app: loading is the expensive part, and a
      // driver correcting a rejected photo runs this two or three times in
      // a row.
      return _interpreter = await Interpreter.fromAsset(kBlazeFaceAssetPath);
    } on Object catch (e) {
      // Anything at all -- a missing asset in a mis-packaged build, an
      // unsupported ABI, a native library that will not load. The contract
      // `checkDriverPhotoFace` expects for "the machinery is broken" is
      // this exception; anything else escaping here would reach the driver
      // as a crash instead of a sentence.
      throw FaceDetectorUnavailableException(
        'could not load $kBlazeFaceAssetPath: $e',
      );
    }
  }

  @override
  Future<List<DetectedFace>> detect(Uint8List jpegBytes) async {
    final interpreter = await _ensureInterpreter();

    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) {
      // The codec upstream has already proved this decodes, so reaching
      // here means the stored bytes and the checked bytes diverged.
      throw const FaceDetectorUnavailableException(
        'the portrait could not be decoded for face detection',
      );
    }

    final geometry = LetterboxGeometry.forImage(decoded.width, decoded.height);
    final input = _letterboxedInput(decoded);

    // Shapes are read from the model rather than hard-coded, and matched by
    // their trailing dimension rather than by output index: BlazeFace emits
    // regressors [1,896,16] and classificators [1,896,1], and which comes
    // first is a property of how the file was converted, not of the format.
    final outputs = <int, Object>{};
    final regressorTensor = interpreter.getOutputTensors().indexWhere(
      (t) => t.shape.last == kBlazeFaceRegressorStride,
    );
    final scoreTensor = interpreter.getOutputTensors().indexWhere(
      (t) => t.shape.last == 1,
    );
    if (regressorTensor < 0 || scoreTensor < 0) {
      throw const FaceDetectorUnavailableException(
        'the bundled model does not have the expected BlazeFace outputs',
      );
    }

    final regressors = [
      List.generate(
        kBlazeFaceAnchorCount,
        (_) => List<double>.filled(kBlazeFaceRegressorStride, 0),
      ),
    ];
    final scores = [
      List.generate(kBlazeFaceAnchorCount, (_) => List<double>.filled(1, 0)),
    ];
    outputs[regressorTensor] = regressors;
    outputs[scoreTensor] = scores;

    interpreter.runForMultipleInputs([input], outputs);

    final faces = decodeBlazeFace(
      regressors: [for (final row in regressors[0]) ...row],
      scores: [for (final row in scores[0]) row[0]],
      anchors: _anchors,
    );

    // Back into the driver's own frame before the policy layer measures
    // anything, or a face filling a wide photo would be judged against the
    // grey bars as well as the picture.
    return [for (final face in faces) geometry.toOriginalFrame(face)];
  }

  /// Builds the `[1,128,128,3]` float input: the portrait scaled to fit,
  /// centred on a grey square, and normalized to -1..1 the way BlazeFace
  /// was trained.
  List<List<List<List<double>>>> _letterboxedInput(img.Image source) {
    final square = img.Image(
      width: kBlazeFaceInputEdge,
      height: kBlazeFaceInputEdge,
    );
    img.fill(square, color: img.ColorRgb8(_kPadLevel, _kPadLevel, _kPadLevel));
    final scaled = img.copyResize(
      source,
      width: (source.width * (kBlazeFaceInputEdge / _longestEdge(source)))
          .round()
          .clamp(1, kBlazeFaceInputEdge),
      height: (source.height * (kBlazeFaceInputEdge / _longestEdge(source)))
          .round()
          .clamp(1, kBlazeFaceInputEdge),
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(
      square,
      scaled,
      dstX: (kBlazeFaceInputEdge - scaled.width) ~/ 2,
      dstY: (kBlazeFaceInputEdge - scaled.height) ~/ 2,
    );

    return [
      List.generate(kBlazeFaceInputEdge, (y) {
        return List.generate(kBlazeFaceInputEdge, (x) {
          final p = square.getPixel(x, y);
          return [p.r / 127.5 - 1.0, p.g / 127.5 - 1.0, p.b / 127.5 - 1.0];
        });
      }),
    ];
  }

  int _longestEdge(img.Image image) =>
      image.width > image.height ? image.width : image.height;

  /// Releases the native interpreter. Called when the app shuts the
  /// provider down; a leaked interpreter holds native memory that Dart's
  /// GC cannot see.
  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}
