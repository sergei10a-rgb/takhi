// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import 'accent_dot.dart';
import 'info_chip.dart';
import 'secondary_button.dart';

/// A driver's face, as a circle, at whatever size the surface around it
/// needs.
///
/// The photograph never reaches a public relay: it travels only inside the
/// NIP-17 gift-wrapped offer addressed to one passenger (see
/// `RideOfferPayload.driverPhotoJpegBase64`). This widget is therefore the
/// only place most riders will ever see it, and everything about it is built
/// around one uncomfortable fact:
///
/// **A portrait here is a barrier, not proof.** The sending device checked
/// that a human face of a reasonable size is in the picture. Nothing checked
/// that the face belongs to the driver holding the phone, and no app without
/// a server can check it -- a friend's photo, a celebrity's, or a photograph
/// of a printed photograph all pass. That is why the enlarged view says so in
/// words rather than leaving a rider to assume a verification that does not
/// exist.
///
/// It degrades the same way [PersonRow] does and for the same reason: a
/// missing photo, an empty one, or bytes that will not decode all fall back
/// to the [initials] mark, so a rider waiting on a kerb gets a proper mark
/// instead of a grey blank or a broken-image glyph.
class DriverPortrait extends StatelessWidget {
  /// The portrait, JPEG. Null (or empty) means there is none -- an offer
  /// from a client older than this field, or one whose photo was dropped on
  /// the way in.
  final Uint8List? jpegBytes;

  /// The mark drawn when there is no usable photo. Never empty --
  /// [AccentDot] rejects a blank mark, and an assertion in front of a rider
  /// choosing a driver is the wrong way to report a missing name.
  final String initials;

  /// Diameter.
  final double size;

  /// Colour family of the fallback mark.
  final TakhiAccent accent;

  /// Whether tapping opens the photograph full screen.
  ///
  /// False on a row avatar, and not because it would be unwanted there: at
  /// row size the circle is well under [TakhiTouch.minTarget], so making it
  /// a target of its own would be a control nobody can hit reliably in a
  /// moving car. Rows put the gesture on the whole row instead.
  final bool enlargeable;

  const DriverPortrait({
    super.key,
    required this.jpegBytes,
    required this.initials,
    required this.size,
    this.accent = TakhiAccent.neutral,
    this.enlargeable = false,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = jpegBytes;
    final fallback = AccentDot(label: initials, accent: accent, size: size);
    if (bytes == null || bytes.isEmpty) return fallback;

    final photo = ClipOval(
      child: Image(
        image: MemoryImage(bytes),
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A portrait that fails to decode must not take the surface down
        // with it -- fall back to the same mark a photo-less driver gets.
        errorBuilder: (_, _, _) => fallback,
      ),
    );
    if (!enlargeable) return photo;

    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.driverPhotoEnlargeSemanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => unawaited(showDriverPhoto(context, bytes)),
          child: photo,
        ),
      ),
    );
  }
}

/// Opens [jpegBytes] full screen, over whatever route is showing.
///
/// A pushed route rather than a dialog: a face is compared at the size of the
/// screen, and a dialog would cap the photograph at a fraction of it while
/// adding a barrier that swallows the pinch gesture.
Future<void> showDriverPhoto(BuildContext context, Uint8List jpegBytes) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DriverPhotoPage(jpegBytes: jpegBytes),
      ),
    );

/// The full-screen portrait, with the truth about it underneath.
///
/// Always dark, in both app brightnesses. That is a photographic decision
/// rather than a styling one: a face is judged against a neutral dark ground,
/// and the light theme's warm paper throws its own cast over skin tones --
/// which is the exact judgement this screen exists to support. Forcing the
/// dark surface ladder (rather than hardcoding two colours) keeps the chip,
/// the sentence and the button reading at the contrast ratios
/// `theme_tokens_test.dart` already asserts for that ladder.
class DriverPhotoPage extends StatelessWidget {
  final Uint8List jpegBytes;

  const DriverPhotoPage({super.key, required this.jpegBytes});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.dark;

    return Theme(
      data: takhiTheme(Brightness.dark),
      child: Scaffold(
        backgroundColor: surfaces.canvas,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: InteractiveViewer(
                  child: Center(
                    child: Image(
                      image: MemoryImage(jpegBytes),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => _UndecodablePhoto(
                        label: l.driverPhotoMissingLabel,
                        color: surfaces.muted,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(TakhiSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      // Clay, the app's "attention without alarm" family:
                      // this is a caveat about the picture, not an accusation
                      // against the driver.
                      child: InfoChip(
                        icon: Icons.info_outline,
                        label: l.driverPhotoUnverifiedBadge,
                        accent: TakhiAccent.clay,
                      ),
                    ),
                    const SizedBox(height: TakhiSpace.xs),
                    Text(
                      l.driverPhotoUnverifiedHint,
                      style: TakhiType.support.copyWith(color: surfaces.muted),
                    ),
                    const SizedBox(height: TakhiSpace.sm),
                    // A labelled button rather than only the system back
                    // gesture: on a screen that is otherwise one photograph,
                    // an invisible way out is no way out for anyone who does
                    // not already know the gesture.
                    SecondaryButton(
                      label: l.driverPhotoCloseAction,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glyph size for the "this photo will not open" mark. Sized against the
/// empty screen it sits in the middle of rather than against a text role.
const _kUndecodableGlyphSize = 56.0;

/// What the viewer shows when the bytes it was handed are not an image after
/// all -- stated as a fact about the photo rather than left as Flutter's own
/// broken-image glyph, which reads as the app being broken.
class _UndecodablePhoto extends StatelessWidget {
  final String label;
  final Color color;

  const _UndecodablePhoto({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.no_photography_outlined,
        size: _kUndecodableGlyphSize,
        color: color,
      ),
      const SizedBox(height: TakhiSpace.sm),
      Text(label, style: TakhiType.body.copyWith(color: color)),
    ],
  );
}
