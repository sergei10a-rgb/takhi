// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// Painted diameter when the caller does not pick one. Deliberately smaller
/// than [TakhiTouch.minTarget]: these sit on top of a live map and a 48dp
/// disc covers noticeably more of it than a 40dp one does.
const _kDefaultSize = 40.0;

/// Fraction of the disc the glyph occupies.
const _kGlyphRatio = 0.45;

/// The round control that floats over the map.
///
/// Recentre-on-me, call the driver, open the chat: small, self-contained
/// actions that belong to the map rather than to the sheet. A near-white
/// disc with a hairline edge and a soft shadow, so it stays legible over
/// map imagery of any colour without a scrim behind it.
///
/// The one rule this widget exists to enforce: **the painted circle and the
/// touch target are two different sizes.** [size] controls the artwork; the
/// gesture area is always padded out to at least [TakhiTouch.minTarget] in
/// both axes, so shrinking the visual to keep the map visible can never
/// shrink the thing a thumb has to hit in a moving car. Callers get the
/// small disc they want and the large target they need without having to
/// remember the second half.
class CircleIconButton extends StatelessWidget {
  /// The glyph.
  final IconData icon;

  /// Tapped. Null dims the control and refuses taps, keeping it in place so
  /// the map's control column does not reflow when one becomes unavailable.
  final VoidCallback? onPressed;

  /// Diameter of the painted disc. The touch target does not follow it below
  /// [TakhiTouch.minTarget].
  final double size;

  /// Tints the disc's fill and glyph with an accent family instead of
  /// leaving it neutral -- for a control that is also a status, such as a
  /// live call.
  final TakhiAccent? accent;

  /// Announced by screen readers, and shown as a long-press tooltip when
  /// [tooltip] is not given separately.
  ///
  /// User-visible: pass a localised string. Required, because an icon-only
  /// control with no label is unusable without sight.
  final String semanticLabel;

  /// Long-press tooltip text. Defaults to [semanticLabel]; pass an empty
  /// string to suppress the tooltip entirely.
  ///
  /// User-visible: pass a localised string.
  final String? tooltip;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = _kDefaultSize,
    this.accent,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final accentColors = accent == null
        ? null
        : takhiAccentColors(accent!, Theme.of(context).brightness);
    final enabled = onPressed != null;
    final target = math.max(size, TakhiTouch.minTarget);

    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accentColors?.tint ?? surfaces.sheet,
        shape: BoxShape.circle,
        border: Border.all(color: surfaces.hairline),
        boxShadow: surfaces.floatShadow,
      ),
      child: Icon(
        icon,
        size: size * _kGlyphRatio,
        color: accentColors?.onTint ?? surfaces.onSheet,
      ),
    );

    Widget button = SizedBox(
      width: target,
      height: target,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Center(
            child: Opacity(opacity: enabled ? 1 : 0.45, child: disc),
          ),
        ),
      ),
    );

    final tip = tooltip ?? semanticLabel;
    if (tip.isNotEmpty) {
      button = Tooltip(message: tip, child: button);
    }
    // Not a semantics *boundary*: these annotations merge into the node the
    // `InkWell` below already publishes, so the result is one node carrying
    // both the label and the tap action rather than a labelled wrapper
    // around a separate, anonymous tappable.
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: button,
    );
  }
}
