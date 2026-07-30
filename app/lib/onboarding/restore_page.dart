// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/primary_button.dart';

/// Lets a returning rider paste their 12-word recovery phrase back in.
/// `privateKeyFromMnemonic` throws [ArgumentError] for anything that fails
/// BIP-39 validation (wrong words, bad checksum) — that's ordinary,
/// expected user-input feedback here, not a programming bug, so it is
/// caught narrowly and surfaced as an inline error instead of crashing.
class RestorePage extends ConsumerStatefulWidget {
  const RestorePage({super.key});

  @override
  ConsumerState<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends ConsumerState<RestorePage> {
  final _controller = TextEditingController();
  bool _restoring = false;
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final mnemonic = _controller.text.trim();
    if (mnemonic.isEmpty || _restoring) return;
    setState(() {
      _restoring = true;
      _showError = false;
    });
    try {
      await ref.read(identityServiceProvider).restore(mnemonic);
      if (!mounted) return;
      context.go('/home');
    } on ArgumentError {
      if (!mounted) return;
      setState(() => _showError = true);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

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
        title: Text(l.restoreIdentity),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TakhiSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                maxLines: 3,
                autofocus: true,
                style: const TextStyle(color: TakhiColors.ink),
                decoration: InputDecoration(
                  hintText: l.restoreHint,
                  filled: true,
                  fillColor: TakhiColors.sand,
                  border: OutlineInputBorder(
                    borderRadius: TakhiRadius.tileAll,
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(TakhiSpace.md),
                ),
              ),
              if (_showError) ...[
                const SizedBox(height: TakhiSpace.sm),
                Text(l.restoreError, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: TakhiSpace.lg),
              PrimaryButton(
                label: l.restoreIdentity,
                loading: _restoring,
                onPressed: _restore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
