// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// Vertical padding inside the capsule.
const _kVerticalPadding = 17.0;

/// Floor on the button's height -- comfortably past [TakhiTouch.minTarget],
/// since this is the one control on the screen the user is meant to hit.
const _kMinHeight = 54.0;

/// Diameter of the in-place spinner.
const _kSpinnerSize = 20.0;

/// The single primary call-to-action button style used across onboarding
/// and identity flows: solid gold fill, a fully rounded capsule, a dimmed
/// disabled state, and a spinner that replaces the label while [loading]
/// is true. The button is disabled -- dimmed via `disabledBackgroundColor`
/// and untappable -- whenever [onPressed] is null *or* [loading] is true,
/// so callers can express "nothing to do yet" (e.g. no input picked) by
/// passing `null` instead of a no-op closure that would leave the button
/// looking active while doing nothing on tap.
///
/// Its shape comes from the design system rather than from its own
/// constants: [TakhiRadius.pill] and [TakhiType.title] are the same tokens
/// [PillField] and every other capsule in the app read, so the primary
/// action and the field above it share one silhouette. The API is
/// unchanged -- this is a restyle, not a new component.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: TakhiColors.gold,
        foregroundColor: TakhiColors.ink,
        disabledBackgroundColor: TakhiColors.gold.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(vertical: _kVerticalPadding),
        // A minimum rather than a fixed height: a Mongolian label long
        // enough to wrap has to be allowed to make the button taller.
        minimumSize: const Size.fromHeight(_kMinHeight),
        shape: const RoundedRectangleBorder(borderRadius: TakhiRadius.pillAll),
      ),
      onPressed: (loading || onPressed == null) ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: _kSpinnerSize,
              width: _kSpinnerSize,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: TakhiColors.ink,
              ),
            )
          : Text(label, textAlign: TextAlign.center, style: TakhiType.title),
    ),
  );
}
