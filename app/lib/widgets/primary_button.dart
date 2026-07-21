// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// The single primary call-to-action button style used across onboarding
/// and identity flows: solid gold fill, 14px rounded corners, a dimmed
/// disabled state, and a spinner that replaces the label while [loading]
/// is true. The button is disabled -- dimmed via `disabledBackgroundColor`
/// and untappable -- whenever [onPressed] is null *or* [loading] is true,
/// so callers can express "nothing to do yet" (e.g. no input picked) by
/// passing `null` instead of a no-op closure that would leave the button
/// looking active while doing nothing on tap.
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
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: (loading || onPressed == null) ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: TakhiColors.ink,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
    ),
  );
}
