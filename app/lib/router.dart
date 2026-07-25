// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'call/phone_share_settings_page.dart';
import 'identity/identity_state.dart';
import 'l10n/app_localizations.dart';
import 'legal/legal_notice_page.dart';
import 'meter/taximeter_page.dart';
import 'nostr/relay_pool_provider.dart';
import 'onboarding/onboarding_page.dart';
import 'onboarding/restore_page.dart';
import 'onboarding/seed_backup_page.dart';
import 'profile/driver_profile_page.dart';
import 'ride/driver_inbox_page.dart';
import 'ride/passenger_ride_page.dart';
import 'safety/emergency_contact_settings_page.dart';
import 'settings/settings_page.dart';
import 'theme/takhi_theme.dart';
import 'widgets/primary_button.dart';

/// Re-runs [GoRouter]'s `redirect` whenever [currentIdentityProvider]
/// settles or changes — e.g. once the initial async key-store read
/// resolves, or after a create/restore/sign-out — so a stored identity is
/// honored without the user having to navigate manually.
class _IdentityRouteRefresh extends ChangeNotifier {
  _IdentityRouteRefresh(Ref ref) {
    ref.listen(currentIdentityProvider, (previous, next) => notifyListeners());
  }
}

/// App-wide navigation. `/` is the always-safe entry point: no route here
/// depends on network state, so first paint is never blocked on
/// connectivity (onboarding budget, spec §10).
///
/// A [Provider] rather than a bare top-level [GoRouter] so `redirect` can
/// read [currentIdentityProvider]: a returning rider who already has a
/// stored identity is sent straight to `/home` instead of being shown
/// onboarding — and its "start fresh" identity-creation flow — again.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _IdentityRouteRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final hasIdentity = ref.read(currentIdentityProvider).valueOrNull != null;
      final atOnboarding = state.matchedLocation == '/';
      if (hasIdentity && atOnboarding) return '/home';
      return null;
    },
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
      GoRoute(
        path: '/restore',
        builder: (context, state) => const RestorePage(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/ride/passenger',
        builder: (context, state) => const PassengerRidePage(),
      ),
      GoRoute(
        path: '/ride/driver',
        builder: (context, state) => const DriverInboxPage(),
      ),
      GoRoute(
        path: '/meter',
        builder: (context, state) => const TaximeterPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/settings/emergency-contact',
        builder: (context, state) => const EmergencyContactSettingsPage(),
      ),
      GoRoute(
        path: '/settings/phone-share',
        builder: (context, state) => const PhoneShareSettingsPage(),
      ),
      GoRoute(
        path: '/settings/driver-profile',
        builder: (context, state) => const DriverProfilePage(),
      ),
      GoRoute(
        path: '/settings/legal',
        builder: (context, state) => const LegalNoticePage(),
      ),
    ],
  );
});

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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: Text(l.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l.settingsAction,
            onPressed: () => context.push('/settings'),
          ),
        ],
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
              const SizedBox(height: 16),
              const _RelayStatusLabel(),
              const SizedBox(height: 16),
              identity.when(
                data: (id) => id == null
                    ? const SizedBox.shrink()
                    : Text(
                        id.npub,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                loading: () => const SizedBox.shrink(),
                error: (error, stack) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: _mode == TakhiMode.passenger
                    ? l.startAsPassengerAction
                    : l.startAsDriverAction,
                // `push`, not `go`: `/ride/*` are top-level routes, so a
                // `go` would *replace* the stack and leave the ride page
                // as its only entry -- no AppBar back arrow, and a
                // hardware back would close the app outright. Pushing
                // keeps `/home` underneath, exactly like the settings
                // entry point above.
                onPressed: () => context.push(
                  _mode == TakhiMode.passenger
                      ? '/ride/passenger'
                      : '/ride/driver',
                ),
              ),
              if (_mode == TakhiMode.driver) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  // `push` for the same reason as the CTA above -- the
                  // meter is a long-lived screen with no exit of its own.
                  onPressed: () => context.push('/meter'),
                  child: Text(l.startAsMeterAction),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the app's live connection state to the public relay network
/// (Plan 2 §5): the `connecting…` label while [relayConnectionProvider] is
/// still awaiting [RelayPool.connectAll], then `connected` with a live
/// count of relays actually holding an open socket once it resolves.
class _RelayStatusLabel extends ConsumerWidget {
  const _RelayStatusLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      color: scheme.onSurface.withValues(alpha: 0.6),
      fontSize: 12,
    );
    final connection = ref.watch(relayConnectionProvider);
    return connection.when(
      data: (pool) =>
          Text('${l.connected} (${pool.connectedUrls.length})', style: style),
      loading: () => Text(l.connecting, style: style),
      error: (error, stack) => Text(l.connecting, style: style),
    );
  }
}
