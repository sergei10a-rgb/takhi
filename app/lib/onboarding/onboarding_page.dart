// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../identity/identity_service.dart';
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/primary_button.dart';

/// The two riding modes Тахь supports. Selected on the onboarding screen and
/// reused on the placeholder home screen; the real ride flow (Plan 3) reads
/// this to decide which surface to show.
enum TakhiMode { passenger, driver }

/// First screen a new install shows: brand mark, mode pick, and the two
/// entry points into identity — create a fresh keypair or restore one from
/// an existing 12-word phrase. No network call happens here, so first paint
/// is never blocked on connectivity.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  TakhiMode _mode = TakhiMode.passenger;
  bool _creating = false;
  bool _showError = false;

  /// Creates a fresh identity and hands the generated mnemonic to the seed
  /// backup screen. `createNewWithMnemonic` persists the new private key via
  /// [KeyStore.write], which throws [SecureStoreException] when the native
  /// secure-storage backend fails (locked keystore, denied access,
  /// unsupported platform, etc.) — that's an expected failure mode here, not
  /// a programming bug, so it's caught narrowly and surfaced as an inline
  /// error with the button re-enabled for a retry, instead of leaving the
  /// only entry point into the app permanently stuck mid-spinner.
  Future<void> _createIdentity() async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _showError = false;
    });
    try {
      final service = ref.read(identityServiceProvider);
      final (mnemonic, _) = await service.createNewWithMnemonic();
      if (!mounted) return;
      context.go('/seed', extra: mnemonic);
    } on SecureStoreException {
      if (!mounted) return;
      setState(() => _showError = true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: TakhiColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const _Brandmark(),
              const SizedBox(height: 18),
              Text(
                l.appName,
                style: const TextStyle(
                  color: TakhiColors.gold,
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  height: 1.0,
                ),
              ),
              const Spacer(flex: 2),
              _ModeToggle(
                mode: _mode,
                onChanged: (m) => setState(() => _mode = m),
                labels: (l.passengerMode, l.driverMode),
              ),
              const Spacer(flex: 3),
              if (_showError) ...[
                Text(
                  l.createIdentityError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFE18579)),
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                label: l.createIdentity,
                loading: _creating,
                onPressed: _createIdentity,
              ),
              const SizedBox(height: 12),
              _SecondaryButton(
                label: l.restoreIdentity,
                onPressed: () => context.push('/restore'),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brandmark extends StatelessWidget {
  const _Brandmark();

  @override
  Widget build(BuildContext context) => Container(
    width: 132,
    height: 132,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: TakhiColors.gold, width: 2),
      boxShadow: [
        BoxShadow(
          color: TakhiColors.gold.withValues(alpha: 0.28),
          blurRadius: 36,
          spreadRadius: 2,
        ),
      ],
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/icon.png',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) =>
            const ColoredBox(color: TakhiColors.goldDeep),
      ),
    ),
  );
}

class _ModeToggle extends StatelessWidget {
  final TakhiMode mode;
  final ValueChanged<TakhiMode> onChanged;
  final (String, String) labels;

  const _ModeToggle({
    required this.mode,
    required this.onChanged,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final (passengerLabel, driverLabel) = labels;
    return SegmentedButton<TakhiMode>(
      segments: [
        ButtonSegment(value: TakhiMode.passenger, label: Text(passengerLabel)),
        ButtonSegment(value: TakhiMode.driver, label: Text(driverLabel)),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onChanged(selection.first),
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: TakhiColors.sand,
        selectedBackgroundColor: TakhiColors.gold,
        selectedForegroundColor: TakhiColors.ink,
        side: const BorderSide(color: TakhiColors.goldDeep),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SecondaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: TakhiColors.sand,
        side: const BorderSide(color: TakhiColors.sand),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 15)),
    ),
  );
}
