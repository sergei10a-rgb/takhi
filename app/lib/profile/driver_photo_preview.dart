// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';

/// Painted diameter of the portrait.
///
/// Sized from what the picture is *for* rather than from the form it sits
/// on: a passenger walking up to a car at night has to be able to match a
/// face to the person opening the door, and a driver has to be able to see,
/// before they save it, whether their own photo would survive that. A 40dp
/// avatar shows that a photo exists; it does not show whose face it is.
const _kPortraitSize = 132.0;

/// Fraction of the empty disc the placeholder glyph fills.
const _kPlaceholderGlyphRatio = 0.42;

/// The driver's own portrait as they will be seen, in both of its states.
///
/// Lives in `profile/` rather than in `widgets/` on purpose. This is the
/// *editing* view -- the driver's own face on their own settings page, at
/// the size the choice is made at. The passenger-facing portrait (in an
/// offer row, and enlarged when a rider taps a driver) is a different
/// component with different rules: it carries the "unverified" caveat a
/// rider needs and this one does not, since a driver looking at their own
/// photo is not being asked to trust anybody.
///
/// Both states are the same diameter. An empty state smaller than the photo
/// it stands in for makes every control below it jump the moment an image
/// arrives -- on a screen whose next tap is a picker button, that is a tap
/// landing somewhere the driver did not aim (the same reasoning as
/// `DriverQrCapturePage`'s preview plate).
class DriverPhotoPreview extends StatelessWidget {
  /// The stored portrait, or `null` when none has been accepted yet.
  final Uint8List? jpegBytes;

  const DriverPhotoPreview({super.key, required this.jpegBytes});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final bytes = jpegBytes;

    if (bytes != null) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: _kPortraitSize,
          height: _kPortraitSize,
          // Cover, not contain: a portrait letterboxed inside a circle
          // leaves two blank crescents and reads as a broken image. The
          // stored photo is at most 512px on its longest edge, so there is
          // always enough to fill the disc.
          fit: BoxFit.cover,
          semanticLabel: l.driverProfilePhotoSectionTitle,
        ),
      );
    }

    return Container(
      width: _kPortraitSize,
      height: _kPortraitSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: surfaces.field,
        shape: BoxShape.circle,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Icon(
        Icons.person_outline,
        size: _kPortraitSize * _kPlaceholderGlyphRatio,
        color: surfaces.muted,
      ),
    );
  }
}
