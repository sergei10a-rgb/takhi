// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'call/phone_share_settings_page.dart';
import 'home/home_page.dart';
import 'identity/identity_state.dart';
import 'legal/legal_notice_page.dart';
import 'meter/taximeter_page.dart';
import 'onboarding/onboarding_page.dart';
import 'onboarding/restore_page.dart';
import 'onboarding/startup_gate.dart';
import 'onboarding/seed_backup_page.dart';
import 'profile/driver_profile_page.dart';
import 'ride/driver_inbox_page.dart';
import 'ride/passenger_ride_page.dart';
import 'safety/emergency_contact_settings_page.dart';
import 'settings/settings_page.dart';

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
///
/// That redirect can only fire once the key-store read has *answered*,
/// which on a cold start is several frames after the first paint. What `/`
/// shows in the meantime is [StartupGate]'s business, not this one's — see
/// its doc comment for why it must not be [OnboardingPage].
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _IdentityRouteRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      if (state.matchedLocation != '/') return null;
      final identity = ref.read(currentIdentityProvider);
      // Three states, not two: `loading` is *not* "no identity", it is "we
      // do not know yet", and it must leave the location alone so
      // [StartupGate] can hold the splash. `refreshListenable` re-runs this
      // the moment the read lands, so the wait costs the rider nothing.
      if (identity.hasValue && identity.value != null) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const StartupGate()),
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
