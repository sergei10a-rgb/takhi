// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';

/// The full-text legal/liability disclaimer (spec §4: "Хууль зүйн ил
/// сануулга" -- Тахь has no operator, no driver vetting, and each side
/// bears their own risk). Reached from `SettingsPage` at any time
/// ("...дэлгэцээс байнга хандах"); the same [legalNoticeBody] copy also
/// appears inline on `OnboardingPage` the first time a rider sees the app,
/// before any identity exists.
class LegalNoticePage extends StatelessWidget {
  const LegalNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: Text(l.legalNoticeTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TakhiSpace.xl),
          child: Text(l.legalNoticeBody, style: const TextStyle(height: 1.5)),
        ),
      ),
    );
  }
}
