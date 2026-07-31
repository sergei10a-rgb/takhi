// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/face/blaze_face_letterbox.dart';

DetectedFace _box({
  required double left,
  required double top,
  required double width,
  required double height,
}) => DetectedFace(
  score: 0.9,
  left: left,
  top: top,
  width: width,
  height: height,
);

void main() {
  group('a square photo', () {
    final geometry = LetterboxGeometry.forImage(512, 512);

    test('needs no padding at all', () {
      expect(geometry.padFractionX, 0);
      expect(geometry.padFractionY, 0);
      expect(geometry.spanFractionX, 1);
      expect(geometry.spanFractionY, 1);
    });

    test('so boxes come back exactly as they went in', () {
      final mapped = geometry.toOriginalFrame(
        _box(left: 0.25, top: 0.25, width: 0.5, height: 0.5),
      );
      expect(mapped.left, closeTo(0.25, 1e-12));
      expect(mapped.top, closeTo(0.25, 1e-12));
      expect(mapped.width, closeTo(0.5, 1e-12));
      expect(mapped.height, closeTo(0.5, 1e-12));
    });
  });

  group('a 16:9 landscape photo', () {
    // 512x288 is what the codec hands over for a phone photo taken
    // sideways: longest edge capped at 512, aspect preserved.
    final geometry = LetterboxGeometry.forImage(512, 288);

    test('is padded top and bottom only', () {
      expect(geometry.padFractionX, 0);
      expect(geometry.spanFractionX, 1);
      // 288/512 of the square is image, the rest split evenly above/below.
      expect(geometry.spanFractionY, closeTo(288 / 512, 1e-12));
      expect(geometry.padFractionY, closeTo((1 - 288 / 512) / 2, 1e-12));
    });

    test('a face filling the photo top-to-bottom reads as filling it, not '
        'as a third of it', () {
      // This is the bug the letterbox exists to prevent. In the padded
      // square the face occupies only the middle 56% vertically; in the
      // driver's actual photograph it occupies all of it. Measuring the
      // former is how an honest close-up portrait gets refused as
      // "face too small".
      final inSquare = _box(
        left: 0.4,
        top: geometry.padFractionY,
        width: 0.2,
        height: geometry.spanFractionY,
      );
      final mapped = geometry.toOriginalFrame(inSquare);
      expect(mapped.top, closeTo(0, 1e-12));
      expect(mapped.height, closeTo(1.0, 1e-12));
      // Horizontally untouched, because that axis was never padded.
      expect(mapped.left, closeTo(0.4, 1e-12));
      expect(mapped.width, closeTo(0.2, 1e-12));
    });

    test('a centred box stays centred', () {
      final mapped = geometry.toOriginalFrame(
        _box(left: 0.45, top: 0.45, width: 0.1, height: 0.1),
      );
      expect(mapped.left + mapped.width / 2, closeTo(0.5, 1e-12));
      expect(mapped.top + mapped.height / 2, closeTo(0.5, 1e-12));
    });
  });

  group('a tall portrait photo', () {
    final geometry = LetterboxGeometry.forImage(288, 512);

    test('is padded left and right only', () {
      expect(geometry.padFractionY, 0);
      expect(geometry.spanFractionY, 1);
      expect(geometry.spanFractionX, closeTo(288 / 512, 1e-12));
      expect(geometry.padFractionX, closeTo((1 - 288 / 512) / 2, 1e-12));
    });

    test('a face filling it side to side reads as filling it', () {
      final mapped = geometry.toOriginalFrame(
        _box(
          left: geometry.padFractionX,
          top: 0.2,
          width: geometry.spanFractionX,
          height: 0.5,
        ),
      );
      expect(mapped.left, closeTo(0, 1e-12));
      expect(mapped.width, closeTo(1.0, 1e-12));
      expect(mapped.top, closeTo(0.2, 1e-12));
      expect(mapped.height, closeTo(0.5, 1e-12));
    });
  });

  group('the round trip preserves what the size rule measures', () {
    test('a face covering a quarter of a wide photo still measures a '
        'quarter after mapping', () {
      final geometry = LetterboxGeometry.forImage(512, 256);
      // Half the width and half the height of the ORIGINAL photo = a
      // quarter of its area.
      final mapped = geometry.toOriginalFrame(
        _box(
          left: 0.25,
          top: geometry.padFractionY + geometry.spanFractionY * 0.25,
          width: 0.5,
          height: geometry.spanFractionY * 0.5,
        ),
      );
      expect(mapped.visibleAreaFraction, closeTo(0.25, 1e-9));
    });
  });

  group('a degenerate image', () {
    test('is refused rather than dividing by zero', () {
      expect(() => LetterboxGeometry.forImage(0, 100), throwsArgumentError);
      expect(() => LetterboxGeometry.forImage(100, 0), throwsArgumentError);
      expect(() => LetterboxGeometry.forImage(-1, 10), throwsArgumentError);
    });
  });
}
