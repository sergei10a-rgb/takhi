// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'driver_photo_rules.dart';

/// What [compressDriverPhoto] produced.
sealed class DriverPhotoCompression {
  const DriverPhotoCompression();
}

/// A portrait small enough to store and to carry inside an encrypted offer.
final class DriverPhotoCompressed extends DriverPhotoCompression {
  /// Baked upright, stripped of metadata, and re-encoded as JPEG.
  final Uint8List jpegBytes;

  final int width, height;

  /// Which rung of [kDriverPhotoJpegQualityLadder] this stopped on. Carried
  /// out of the function purely so a test -- and a bug report -- can tell
  /// "fitted immediately" from "only just fitted at the bottom".
  final int quality;

  const DriverPhotoCompressed({
    required this.jpegBytes,
    required this.width,
    required this.height,
    required this.quality,
  });
}

final class DriverPhotoCompressionRejected extends DriverPhotoCompression {
  final DriverPhotoRejection reason;
  const DriverPhotoCompressionRejected(this.reason);
}

/// Turns whatever the image picker handed over into a portrait that is
/// upright, anonymous in its metadata, no larger than
/// [kDriverPhotoMaxEdgePx] on its longest edge, and under [maxBytes].
///
/// Pure and synchronous: no plugin, no file system, no network. That is
/// what lets the size ladder -- the part that decides whether an offer is
/// small enough for a relay to accept at all -- be tested in `flutter test`
/// rather than only discovered on a device, and it is why this uses the
/// pure-Dart `image` package instead of a native compressor plugin.
///
/// [maxBytes] and [qualityLadder] default to the shipped rules and are
/// injectable only so the "walks down the ladder" and "runs out of rungs"
/// branches can be exercised; production callers pass neither.
DriverPhotoCompression compressDriverPhoto(
  Uint8List raw, {
  int maxBytes = kDriverPhotoMaxBytes,
  List<int> qualityLadder = kDriverPhotoJpegQualityLadder,
}) {
  // `decodeImage` sniffs the format, so a HEIC the decoder does not know, a
  // renamed text file and a half-downloaded JPEG all land here as null
  // rather than as an exception somewhere further down.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(raw);
  } on Object {
    // The decoders are fed attacker-adjacent bytes -- a file the user picked
    // from a share sheet, ultimately from anywhere -- and a malformed one
    // must be a refusal, never a crash on the profile screen.
    return const DriverPhotoCompressionRejected(
      DriverPhotoRejection.undecodable,
    );
  }
  if (decoded == null) {
    return const DriverPhotoCompressionRejected(
      DriverPhotoRejection.undecodable,
    );
  }

  // Rotate first. The EXIF orientation tag is about to be thrown away with
  // the rest of the metadata, so if the rotation is not applied to the
  // pixels here, every photo taken with the phone held upright is stored on
  // its side.
  final upright = img.bakeOrientation(decoded);

  final longestEdge = upright.width > upright.height
      ? upright.width
      : upright.height;
  // Only ever down. Enlarging a small photo spends bytes to add nothing.
  final scaled = longestEdge <= kDriverPhotoMaxEdgePx
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? kDriverPhotoMaxEdgePx : null,
          height: upright.height > upright.width ? kDriverPhotoMaxEdgePx : null,
          interpolation: img.Interpolation.average,
        );

  // Everything the camera wrote about where and when and with what: the
  // model, the timestamp, and the GPS coordinates a driver's home portrait
  // would otherwise carry to every passenger they ever offered a ride to.
  // Replaced wholesale rather than filtered tag by tag -- an allow-list of
  // "harmless" tags is a list somebody has to keep correct forever.
  scaled.exif = img.ExifData();

  for (final quality in qualityLadder) {
    final encoded = img.encodeJpg(scaled, quality: quality);
    if (encoded.length <= maxBytes) {
      return DriverPhotoCompressed(
        jpegBytes: Uint8List.fromList(encoded),
        width: scaled.width,
        height: scaled.height,
        quality: quality,
      );
    }
  }

  // Out of rungs. Unreachable at 512px with a 60KB cap, and kept as a real
  // outcome rather than a silent oversized return so that tightening either
  // number later fails loudly instead of shipping offers relays drop.
  return const DriverPhotoCompressionRejected(
    DriverPhotoRejection.tooLargeAfterCompression,
  );
}
