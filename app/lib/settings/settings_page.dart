// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../support/bug_report_page.dart';
import '../theme/takhi_theme.dart';
import '../widgets/menu_row.dart';
import '../widgets/section_heading.dart';

/// The single settings hub reached from `HomePage`'s gear icon. A thin
/// menu, not a feature in itself -- everything it lists already has its own
/// dedicated page and route; this just gives them all one common,
/// always-reachable entry point instead of scattering separate icons across
/// `HomePage`.
///
/// Two things it was getting wrong:
///
/// * it was four words in a column of grey outline glyphs. "Утасны дугаар"
///   does not say *whose* number, or what the app does with it, so the only
///   way to find the right row was to open them one by one. Every row now
///   carries a line saying what is behind it, in the user's terms and not
///   the code's;
/// * **`/settings/emergency-contact` was not on it at all.** The only way in
///   was the "add a number" link on the SOS sheet's empty state -- which
///   disappears the moment a number is saved, so a rider whose emergency
///   contact changed their phone had no way back to the field. It is listed
///   here now, which is the whole reason a settings hub exists.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return Scaffold(
      backgroundColor: surfaces.canvas,
      // Home pushes this route, so the bar has to be here to carry the back
      // arrow -- but not the title, which the SectionHeading below states at
      // a size worth reading.
      appBar: AppBar(
        backgroundColor: surfaces.canvas,
        foregroundColor: surfaces.onSheet,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            TakhiSpace.md,
            TakhiSpace.lg,
            TakhiSpace.md,
            TakhiSpace.xl,
          ),
          children: [
            SectionHeading(
              title: l.settingsTitle,
              subtitle: l.settingsSubtitle,
            ),
            const SizedBox(height: TakhiSpace.lg),
            MenuRow(
              icon: Icons.badge,
              label: l.settingsDriverProfileMenuLabel,
              subtitle: l.settingsDriverProfileMenuHint,
              // Steppe throughout the app means "working as a driver" --
              // the same accent the driver tile on the home sheet carries.
              accent: TakhiAccent.steppe,
              onTap: () => context.push('/settings/driver-profile'),
            ),
            const SizedBox(height: TakhiSpace.xs),
            MenuRow(
              icon: Icons.receipt_long,
              label: l.settingsJournalMenuLabel,
              subtitle: l.settingsJournalMenuHint,
              // Steppe again, and directly under the driver profile: both
              // rows are about working as a driver, and the journal is the
              // record of exactly the work that profile advertises.
              accent: TakhiAccent.steppe,
              onTap: () => context.push('/settings/journal'),
            ),
            const SizedBox(height: TakhiSpace.xs),
            MenuRow(
              icon: Icons.phone,
              label: l.settingsPhoneShareMenuLabel,
              subtitle: l.settingsPhoneShareMenuHint,
              accent: TakhiAccent.sky,
              onTap: () => context.push('/settings/phone-share'),
            ),
            const SizedBox(height: TakhiSpace.xs),
            MenuRow(
              icon: Icons.emergency_share,
              label: l.settingsEmergencyContactMenuLabel,
              subtitle: l.settingsEmergencyContactMenuHint,
              // Clay is the emergency family, matching the SOS tile on the
              // home sheet and the sheet it opens.
              accent: TakhiAccent.clay,
              onTap: () => context.push('/settings/emergency-contact'),
            ),
            const SizedBox(height: TakhiSpace.xs),
            MenuRow(
              icon: Icons.gavel,
              label: l.settingsLegalNoticeMenuLabel,
              subtitle: l.settingsLegalNoticeMenuHint,
              // Gold, not neutral: the neutral tint *is* the row's own fill,
              // so a neutral disc disappears and this row alone ends up
              // with a bare glyph while the three above it have marks.
              accent: TakhiAccent.gold,
              onTap: () => context.push('/settings/legal'),
            ),
            const SizedBox(height: TakhiSpace.xs),
            // Last, and deliberately reachable from a menu rather than
            // hidden behind a shake gesture or a build number tapped seven
            // times: an app with nobody at the middle of it has no support
            // desk, so the only way a problem gets reported at all is if a
            // driver can find the place to write it down.
            MenuRow(
              icon: Icons.bug_report_outlined,
              label: l.bugReportTitle,
              subtitle: l.bugReportMenuHint,
              accent: TakhiAccent.clay,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BugReportPage(screen: l.settingsTitle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
