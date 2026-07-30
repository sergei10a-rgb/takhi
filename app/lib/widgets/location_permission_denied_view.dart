// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'primary_button.dart';
import '../theme/takhi_theme.dart';

/// Shared "location permission denied" feedback: any screen that needs a
/// GPS fix (`ActiveTripView`'s tracking step, `TaximeterPage`'s idle step)
/// shows this instead of silently doing nothing when
/// `locationPermissionCheckProvider` comes back false, so the user always
/// gets a real UI state plus a way to retry (never swallow the denial per
/// common/coding-style.md's "never silently swallow errors").
class LocationPermissionDeniedView extends StatelessWidget {
  final VoidCallback onRetry;
  const LocationPermissionDeniedView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.locationPermissionNeededHint, textAlign: TextAlign.center),
            const SizedBox(height: TakhiSpace.md),
            PrimaryButton(
              label: l.grantLocationPermissionAction,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
