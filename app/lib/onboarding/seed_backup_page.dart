// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/primary_button.dart';

/// Shown once, immediately after a fresh identity is created. Displays the
/// 12-word BIP-39 recovery phrase and a hard warning that it is the only way
/// back in — Тахь has no server-side account recovery. The phrase never
/// touches disk or network from this screen; it only lives in navigation
/// state for the duration of this route.
class SeedBackupPage extends StatelessWidget {
  final String mnemonic;

  const SeedBackupPage({super.key, required this.mnemonic});

  static const _warnColor = Color(0xFF9E3327);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final words = mnemonic.trim().split(RegExp(r'\s+'));

    return Scaffold(
      backgroundColor: TakhiColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.seedBackupTitle,
                style: const TextStyle(
                  color: TakhiColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _WarningBanner(text: l.seedBackupWarning, color: _warnColor),
              const SizedBox(height: 20),
              Expanded(child: _WordGrid(words: words)),
              const SizedBox(height: 16),
              PrimaryButton(
                label: l.iSavedIt,
                onPressed: () => context.go('/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;
  final Color color;

  const _WarningBanner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 14, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _WordGrid extends StatelessWidget {
  final List<String> words;

  const _WordGrid({required this.words});

  @override
  Widget build(BuildContext context) => GridView.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3.0,
    ),
    itemCount: words.length,
    itemBuilder: (context, i) => Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: TakhiColors.sand,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${i + 1}. ',
              style: const TextStyle(
                color: TakhiColors.goldDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: words[i],
              style: const TextStyle(
                color: TakhiColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
