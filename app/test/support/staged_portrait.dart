// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The ground, the shoulders and the head of one staged portrait, as
/// `0xRRGGBB`.
///
/// Plain integers rather than `img.ColorRgb8` values because that class has
/// no const constructor, and a table of stand-in colours that cannot be
/// `const` is a table that gets rebuilt on every call for no reason.
typedef _PortraitPalette = (int ground, int body, int head);

/// Enough distinct portraits for one offer list.
///
/// Different drivers get visibly different pictures on purpose: a list in
/// which every face is the same image proves nothing about whether a rider
/// can tell two drivers apart, which is the entire job of the column those
/// circles sit in. The palettes stay inside the app's own sand/steppe/clay
/// families so a screenshot does not acquire a colour the design system
/// never uses.
const _kPalettes = <_PortraitPalette>[
  (0xE7DEC9, 0x9A8C6E, 0xB6A582),
  (0xD8DFD6, 0x5F7163, 0x8C9C8E),
  (0xEEDACE, 0x8B624A, 0xC09374),
];

/// The edge length of a staged portrait, matching `kDriverPhotoMaxEdgePx`.
///
/// The same size the real compressor outputs, so a picture taken through
/// this helper is cropped and scaled by exactly the arithmetic a stored
/// photograph goes through.
const int kStagedPortraitEdgePx = 512;

/// Centre and radius of the shoulders, and of the head over them, in the
/// [kStagedPortraitEdgePx] frame. Sized so the head alone clears
/// `kMinFaceAreaFraction`, i.e. so the silhouette is framed the way a
/// portrait that would actually pass the face check is framed.
const _kBodyCentreY = 470, _kBodyRadius = 190;
const _kHeadCentreY = 200, _kHeadRadius = 110;

/// A stand-in portrait: a head-and-shoulders silhouette on a tinted ground,
/// drawn here rather than vendored as a file.
///
/// **Deliberately not a photograph of anybody.** What the pictures need to
/// show is that a circle crops to a face-sized subject, that two drivers do
/// not collapse into one another, and that the surrounding copy sits
/// correctly around the image -- none of which needs a real face, and
/// putting a real person's face into a repository screenshot would be a
/// permission nobody granted. It is a genuine JPEG, so `Image.memory`
/// decodes it exactly as it decodes a stored portrait, and small enough
/// (flat fills at quality 80) to ride inside a gift-wrapped offer well
/// under `kDriverPhotoMaxBytes`.
///
/// [variant] picks one of the palettes and wraps around, so a caller can
/// index it by driver without bounds-checking.
Uint8List stagedPortraitJpeg({int variant = 0}) {
  final (ground, body, head) = _kPalettes[variant % _kPalettes.length];
  final image = img.Image(
    width: kStagedPortraitEdgePx,
    height: kStagedPortraitEdgePx,
  );
  img.fill(image, color: _rgb(ground));
  // Shoulders first, then the head over them: drawn in the order a person
  // occludes themselves, so the two discs read as one figure rather than as
  // two circles.
  img.fillCircle(
    image,
    x: kStagedPortraitEdgePx ~/ 2,
    y: _kBodyCentreY,
    radius: _kBodyRadius,
    color: _rgb(body),
  );
  img.fillCircle(
    image,
    x: kStagedPortraitEdgePx ~/ 2,
    y: _kHeadCentreY,
    radius: _kHeadRadius,
    color: _rgb(head),
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

img.ColorRgb8 _rgb(int hex) =>
    img.ColorRgb8((hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF);
