// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

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
///
/// Because of that, this is the single most destructive back gesture in the
/// app: `OnboardingPage` arrives here with `context.go('/seed')`, so a stray
/// hardware back or edge swipe would leave the only screen that will ever
/// show these words, with no way to bring them back. [_confirmLeave] gates
/// it, in the same spirit as `ConfirmLeaveScope` guards the running meter
/// and an active trip.
class SeedBackupPage extends StatefulWidget {
  final String mnemonic;

  const SeedBackupPage({super.key, required this.mnemonic});

  @override
  State<SeedBackupPage> createState() => _SeedBackupPageState();
}

class _SeedBackupPageState extends State<SeedBackupPage> {
  /// Mirrors `ConfirmLeaveScope`'s own guard: a second back press racing
  /// the dialog's entry animation would otherwise stack a second identical
  /// copy that then needs dismissing twice.
  bool _asking = false;

  /// Deliberately *not* [ConfirmLeaveScope], despite the identical shape:
  /// that widget finishes by calling `Navigator.pop()`, and `go('/seed')`
  /// replaced the stack, so this route is its only entry and `canPop()` is
  /// false -- confirming would do nothing at all and trap the user in the
  /// dialog. Leaving this screen means going on to `/home`, not popping.
  Future<void> _confirmLeave() async {
    final l = AppLocalizations.of(context)!;
    _asking = true;
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l.leaveSeedBackupTitle),
          content: Text(l.leaveSeedBackupMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.stayAction),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.backToHomeAction),
            ),
          ],
        ),
      );
    } finally {
      _asking = false;
    }
    // `null` is a barrier tap or a back press on the dialog itself --
    // treated as "stay", the safe answer on this screen above all others.
    if (confirmed != true || !mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final words = widget.mnemonic.trim().split(RegExp(r'\s+'));
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _asking) return;
        unawaited(_confirmLeave());
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.seedBackupTitle,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _WarningBanner(text: l.seedBackupWarning, color: scheme.error),
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
