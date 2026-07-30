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
/// and identity flows: solid gold fill, a fully rounded capsule, a legible
/// disabled state, and a spinner that replaces the label while [loading]
/// is true. The button is disabled -- greyed and untappable -- whenever
/// [onPressed] is null *or* [loading] is true, so callers can express
/// "nothing to do yet" (e.g. no input picked) by passing `null` instead of
/// a no-op closure that would leave the button looking active while doing
/// nothing on tap.
///
/// Its shape comes from the design system rather than from its own
/// constants: [TakhiRadius.pill] and [TakhiType.title] are the same tokens
/// [PillField] and every other capsule in the app read, so the primary
/// action and the field above it share one silhouette. The API is
/// unchanged -- this is a restyle, not a new component.
///
/// **The disabled state greys out rather than fading the gold.** A faded
/// fill was the obvious way to say "not yet" and it was a legibility bug:
/// `gold @ 60%` over the light sheet lands on RGB(221,192,134), and the ink
/// label on it measures 2.15:1 -- the same trap `dialogActionColors` and
/// `SecondaryButton` already document for flat gold, reached from the other
/// direction. It was the *opening* state of six screens (the seed backup in
/// both brightnesses, the phone-share form, the driver profile, the QR
/// capture, the rating step), i.e. the first thing a new user ever saw of
/// this app. The recessed field fill with the supporting-text colour on it
/// is asserted at 5.26:1 in `theme_tokens_test.dart`, and it also reads
/// more honestly: a disabled control should look like the *wells* around
/// it, not like a washed-out version of the live one. The spinner follows
/// the label for the same reason -- a loading button is a disabled one, and
/// an ink-coloured arc on the dark theme's field fill would be invisible.
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
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: TakhiColors.gold,
          foregroundColor: TakhiColors.ink,
          disabledBackgroundColor: surfaces.field,
          disabledForegroundColor: surfaces.muted,
          padding: const EdgeInsets.symmetric(vertical: _kVerticalPadding),
          // A minimum rather than a fixed height: a Mongolian label long
          // enough to wrap has to be allowed to make the button taller.
          minimumSize: const Size.fromHeight(_kMinHeight),
          shape: const RoundedRectangleBorder(
            borderRadius: TakhiRadius.pillAll,
          ),
        ),
        onPressed: (loading || onPressed == null) ? null : onPressed,
        child: loading
            ? SizedBox(
                height: _kSpinnerSize,
                width: _kSpinnerSize,
                child: CircularProgressIndicator(
                  strokeWidth: TakhiStroke.indicator,
                  color: surfaces.muted,
                ),
              )
            : Text(label, textAlign: TextAlign.center, style: TakhiType.title),
      ),
    );
  }
}
