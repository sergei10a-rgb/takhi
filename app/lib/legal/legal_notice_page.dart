// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/accent_dot.dart';
import '../widgets/section_heading.dart';

/// Diameter of the disc that marks the notice.
const _kNoticeDotSize = 36.0;

/// The full-text legal/liability disclaimer (spec §4: "Хууль зүйн ил
/// сануулга" -- Тахь has no operator, no driver vetting, and each side
/// bears their own risk). Reached from `SettingsPage` at any time
/// ("...дэлгэцээс байнга хандах"); the same [legalNoticeBody] copy also
/// appears on `OnboardingPage` the first time a rider sees the app, before
/// any identity exists.
///
/// It used to be three lines of default-styled body text against the top of
/// an otherwise empty screen -- which read as an oversight rather than as
/// the one thing this app says about who carries the risk. The wording is
/// unchanged and still comes wholly from `l10n`; what changed is that it now
/// sits on a surface, under a heading that says why it is here, so it looks
/// like the disclosure it is.
class LegalNoticePage extends StatelessWidget {
  const LegalNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return Scaffold(
      backgroundColor: surfaces.canvas,
      appBar: AppBar(
        backgroundColor: surfaces.canvas,
        foregroundColor: surfaces.onSheet,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            TakhiSpace.md,
            TakhiSpace.lg,
            TakhiSpace.md,
            TakhiSpace.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(
                title: l.legalNoticeTitle,
                subtitle: l.legalNoticeSubtitle,
              ),
              const SizedBox(height: TakhiSpace.lg),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: surfaces.sheet,
                  borderRadius: TakhiRadius.cardAll,
                  border: Border.all(color: surfaces.hairline),
                  boxShadow: surfaces.sheetShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(TakhiSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AccentDot(
                        icon: Icons.gavel,
                        accent: TakhiAccent.clay,
                        size: _kNoticeDotSize,
                      ),
                      const SizedBox(width: TakhiSpace.sm),
                      Expanded(
                        child: Text(
                          l.legalNoticeBody,
                          style: TakhiType.body.copyWith(
                            color: surfaces.onSheet,
                            // Looser than the role's own leading: legal
                            // wording is read sentence by sentence rather
                            // than scanned.
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
