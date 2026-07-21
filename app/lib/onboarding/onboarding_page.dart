// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';

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

  Future<void> _createIdentity() async {
    if (_creating) return;
    setState(() => _creating = true);
    final service = ref.read(identityServiceProvider);
    final (mnemonic, _) = await service.createNewWithMnemonic();
    if (!mounted) return;
    setState(() => _creating = false);
    context.go('/seed', extra: mnemonic);
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
              _PrimaryButton(
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
        ButtonSegment(
          value: TakhiMode.passenger,
          label: Text(passengerLabel),
        ),
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

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: TakhiColors.gold,
        foregroundColor: TakhiColors.ink,
        disabledBackgroundColor: TakhiColors.gold.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: TakhiColors.ink,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
    ),
  );
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 15)),
    ),
  );
}
