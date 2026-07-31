// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// The quiet, full-width second choice that sits under a `PrimaryButton`.
///
/// Every sheet in this app that offers two answers offers them the same way:
/// one solid gold capsule for the step the user came to take, and this
/// directly under it for the other one. Having it as a component rather than
/// as a `TextButton` per call site is what keeps the pair one object -- the
/// same height, the same capsule, the same width -- instead of a button with
/// a stray link under it.
///
/// The one rule it exists to enforce is the foreground colour. Material's
/// default for a `TextButton` is `ColorScheme.primary`, which in this theme
/// is brand gold, and gold on the light sheet measures 2.28:1 -- every
/// hand-rolled secondary action in the app had inherited that. This one takes
/// [TakhiSurfaces.muted] instead, which is asserted AA on all three surfaces
/// in `theme_tokens_test.dart`.
///
/// Pass `null` to [onPressed] for "not available yet": the button stays in
/// place, dimmed, so the sheet does not reflow when an answer becomes
/// unavailable.
class SecondaryButton extends StatelessWidget {
  /// The label. Never truncated -- a Mongolian label long enough to wrap
  /// makes the button taller instead ([TakhiTouch.minTarget] is a floor).
  ///
  /// User-visible: pass a localised string.
  final String label;

  final VoidCallback? onPressed;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: surfaces.muted,
        disabledForegroundColor: surfaces.muted.withValues(alpha: 0.45),
        minimumSize: const Size.fromHeight(TakhiTouch.minTarget),
        shape: const RoundedRectangleBorder(borderRadius: TakhiRadius.pillAll),
        // Never the bare token: `ButtonStyle.textStyle` replaces the
        // inherited style rather than merging onto it, and the bundled
        // Cyrillic family would go with it (see `takhiButtonTextStyle`).
        textStyle: takhiButtonTextStyle(context, TakhiType.title),
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
