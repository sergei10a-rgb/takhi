// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';

/// The single settings hub reached from `HomePage`'s gear icon. A thin
/// menu, not a feature in itself -- everything it lists (driver profile,
/// phone-share, and the legal notice, spec §4) already has its own
/// dedicated page and route; this just gives them all one common,
/// always-reachable entry point instead of scattering separate icons
/// across `HomePage`'s AppBar.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
        title: Text(l.settingsTitle),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(l.settingsDriverProfileMenuLabel),
              onTap: () => context.push('/settings/driver-profile'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(l.settingsPhoneShareMenuLabel),
              onTap: () => context.push('/settings/phone-share'),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: Text(l.settingsLegalNoticeMenuLabel),
              onTap: () => context.push('/settings/legal'),
            ),
          ],
        ),
      ),
    );
  }
}
