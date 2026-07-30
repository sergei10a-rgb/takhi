// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import 'notice_card.dart';
import 'primary_button.dart';
import 'section_heading.dart';
import 'takhi_sheet.dart';

/// Shared "location permission denied" feedback: any screen that needs a
/// GPS fix (`ActiveTripView`'s tracking step, `TaximeterPage`'s idle step)
/// shows this instead of silently doing nothing when
/// `locationPermissionCheckProvider` comes back false, so the user always
/// gets a real UI state plus a way to retry (never swallow the denial per
/// common/coding-style.md's "never silently swallow errors").
///
/// It is built like every other step in this app rather than as a centred
/// message, and the difference is not decoration. Before this it was one
/// grey sentence and a gold capsule floating in the middle of an otherwise
/// blank page: no title, no surface, nothing tying it to the screen the
/// user had been on. A rendered screenshot of it is indistinguishable from
/// a screen that failed to build. Now it says what state the app is in
/// (heading), why (a tinted [NoticeCard] rather than loose coloured text)
/// and offers the one answer on the anchored sheet every other step puts
/// its action on.
class LocationPermissionDeniedView extends StatelessWidget {
  final VoidCallback onRetry;
  const LocationPermissionDeniedView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              TakhiSpace.md,
              TakhiSpace.lg,
              TakhiSpace.md,
              TakhiSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(title: l.locationPermissionNeededTitle),
                const SizedBox(height: TakhiSpace.lg),
                // Clay, the caveat family: nothing is broken and nothing has
                // been lost -- a permission is simply switched off, and the
                // next tap can switch it back on.
                NoticeCard(
                  icon: Icons.location_off_outlined,
                  text: l.locationPermissionNeededHint,
                  accent: TakhiAccent.clay,
                ),
              ],
            ),
          ),
        ),
        TakhiSheet(
          showHandle: false,
          child: PrimaryButton(
            label: l.grantLocationPermissionAction,
            onPressed: onRetry,
          ),
        ),
      ],
    );
  }
}
