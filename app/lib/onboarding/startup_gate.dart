// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../identity/identity_state.dart';
import '../theme/takhi_theme.dart';
import 'onboarding_page.dart';

/// What `/` builds while the stored-identity read is still in flight.
///
/// [currentIdentityProvider] is a `FutureProvider`, so `valueOrNull` reads
/// `null` for two entirely different situations: "this phone has no
/// identity" and "we have not finished looking yet". Treating both as the
/// first one meant every returning rider watched S1 Onboarding flash past
/// on launch before the redirect threw them at S4 — a branded native
/// splash handing over to the wrong screen.
///
/// So this widget waits on [AsyncValue.isLoading] instead, showing a
/// neutral continuation of the native splash. The waiting is bounded at
/// both ends:
///
///  * **No floor.** An identity that is already loaded costs zero extra
///    frames — nothing is held back to show off the brand.
///  * **[indicatorDelay] before any loading affordance.** A key-store read
///    that answers promptly should look instantaneous, not busy.
///  * **[readTimeout] ceiling.** A wedged Keystore must not lock the rider
///    out of their own app forever; past this the app falls through to
///    onboarding, and the redirect still takes over if the read eventually
///    lands on an identity.
class StartupGate extends ConsumerStatefulWidget {
  const StartupGate({super.key});

  /// How long the screen stays completely empty before admitting it is
  /// waiting on something.
  static const indicatorDelay = Duration(milliseconds: 600);

  /// Upper bound on the whole wait.
  static const readTimeout = Duration(seconds: 3);

  /// Thickness of the loading bar — a hairline, deliberately: it is a sign
  /// of life on a splash screen, not a component of the UI.
  static const indicatorHeight = 3.0;

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate> {
  Timer? _indicatorTimer;
  Timer? _timeoutTimer;
  bool _showIndicator = false;
  bool _gaveUp = false;

  @override
  void initState() {
    super.initState();
    // The zero floor, mechanically: with the read already settled there is
    // nothing to wait for, so no timer is armed and this build resolves
    // straight to its answer.
    if (!ref.read(currentIdentityProvider).isLoading) return;
    _indicatorTimer = Timer(
      StartupGate.indicatorDelay,
      () => setState(() => _showIndicator = true),
    );
    _timeoutTimer = Timer(
      StartupGate.readTimeout,
      () => setState(() => _gaveUp = true),
    );
  }

  void _stopWaiting() {
    _indicatorTimer?.cancel();
    _indicatorTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  @override
  void dispose() {
    _stopWaiting();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Disarms both timers the moment the answer arrives. Letting them run
    // on would repaint a screen that has already moved on -- and under
    // `flutter_test` a timer outliving its widget fails the test outright.
    ref.listen(currentIdentityProvider, (previous, next) {
      if (!next.isLoading) _stopWaiting();
    });

    final identity = ref.watch(currentIdentityProvider);
    // `isLoading`, not `valueOrNull == null`: telling those two apart is
    // the entire reason this widget exists. An *error* counts as an
    // answer -- a key store that cannot be read has no identity to offer,
    // and onboarding is where that rider has to start.
    if (identity.isLoading && !_gaveUp) {
      return _StartupSplash(showIndicator: _showIndicator);
    }
    // A stored identity never gets this far: `routerProvider`'s redirect
    // fires off the same provider and replaces `/` with `/home`.
    return const OnboardingPage();
  }
}

/// The native splash, continued in Flutter: same brand background, nothing
/// on it. Text is deliberately absent — a label that appears for a few
/// frames and vanishes reads as a glitch, not as progress.
class _StartupSplash extends StatelessWidget {
  const _StartupSplash({required this.showIndicator});

  final bool showIndicator;

  @override
  Widget build(BuildContext context) => Scaffold(
    // `colorScheme.surface` is what `flutter_native_splash`'s `color` /
    // `color_dark` in `pubspec.yaml` are set to; `splash_parity_test.dart`
    // fails if the two ever drift apart again.
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: showIndicator
            ? const LinearProgressIndicator(
                minHeight: StartupGate.indicatorHeight,
                color: TakhiColors.gold,
                backgroundColor: Colors.transparent,
              )
            : const SizedBox.shrink(),
      ),
    ),
  );
}
