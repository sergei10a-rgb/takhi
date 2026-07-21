// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'identity/identity_state.dart';
import 'l10n/app_localizations.dart';
import 'onboarding/onboarding_page.dart';
import 'onboarding/restore_page.dart';
import 'onboarding/seed_backup_page.dart';
import 'theme/takhi_theme.dart';

/// App-wide navigation. `/` is the always-safe entry point: no route here
/// depends on network state, so first paint is never blocked on
/// connectivity (onboarding budget, spec §10).
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const OnboardingPage()),
    GoRoute(
      path: '/seed',
      builder: (context, state) {
        // A 12-word mnemonic is only ever handed here as in-memory route
        // `extra` right after creation — never persisted, never a deep
        // link target. A missing/oddly-typed extra means this route was
        // reached some other way (e.g. a stale deep link); fall back to
        // onboarding instead of crashing.
        final mnemonic = state.extra;
        if (mnemonic is! String || mnemonic.isEmpty) {
          return const OnboardingPage();
        }
        return SeedBackupPage(mnemonic: mnemonic);
      },
    ),
    GoRoute(path: '/restore', builder: (context, state) => const RestorePage()),
    GoRoute(path: '/home', builder: (context, state) => const HomePage()),
  ],
);

/// Placeholder two-mode home. The real ride flow (map, taximeter, calling)
/// ships in Plan 3 — this only proves the onboarding → identity → home path
/// works end to end.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  TakhiMode _mode = TakhiMode.passenger;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final identity = ref.watch(currentIdentityProvider);

    return Scaffold(
      backgroundColor: TakhiColors.paper,
      appBar: AppBar(
        backgroundColor: TakhiColors.paper,
        foregroundColor: TakhiColors.ink,
        elevation: 0,
        title: Text(l.appName),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<TakhiMode>(
                segments: [
                  ButtonSegment(
                    value: TakhiMode.passenger,
                    label: Text(l.passengerMode),
                  ),
                  ButtonSegment(
                    value: TakhiMode.driver,
                    label: Text(l.driverMode),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: TakhiColors.sand,
                  foregroundColor: TakhiColors.ink,
                  selectedBackgroundColor: TakhiColors.gold,
                  selectedForegroundColor: TakhiColors.ink,
                  side: const BorderSide(color: TakhiColors.goldDeep),
                ),
              ),
              const SizedBox(height: 24),
              identity.when(
                data: (id) => id == null
                    ? const SizedBox.shrink()
                    : Text(
                        id.npub,
                        style: const TextStyle(
                          color: TakhiColors.ink,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                loading: () => const SizedBox.shrink(),
                error: (error, stack) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
