// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/main.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/onboarding/onboarding_page.dart';
import 'package:takhi/onboarding/startup_gate.dart';
import 'package:takhi/theme/takhi_theme.dart';

import 'support/fake_relay_socket.dart';

/// A [KeyStore] whose `read()` hangs until the test releases it.
///
/// [InMemoryKeyStore] answers in the very next microtask, and that is
/// exactly what hid this bug: the onboarding flash only exists in the
/// frames between "the key-store read started" and "the read came back".
/// On a real device that gap is an Android Keystore / iOS Keychain round
/// trip — long enough to see.
class _HangingKeyStore implements KeyStore {
  _HangingKeyStore(this._privHex);

  final String? _privHex;
  final _gate = Completer<void>();

  /// Lets the pending [read] complete. Deliberately never called by the
  /// "the key store never answers" scenario.
  void release() => _gate.complete();

  @override
  Future<String?> read() async {
    await _gate.future;
    return _privHex;
  }

  @override
  Future<void> write(String privHex) async {}

  @override
  Future<void> clear() async {}
}

/// The private key of a rider who has used the app before, in the exact
/// form [SecureKeyStore] hands back on the next cold start.
Future<String> _storedPrivHex() async {
  final seed = InMemoryKeyStore();
  await IdentityService(seed).createNew();
  return (await seed.read())!;
}

Future<void> _pumpApp(WidgetTester t, KeyStore store) => t.pumpWidget(
  ProviderScope(
    overrides: [
      keyStoreProvider.overrideWithValue(store),
      // `/home` dials the relay network on arrival; no test may touch a
      // real socket.
      relayPoolProvider.overrideWithValue(
        RelayPool(defaultRelayUrls, connect: (u) => FakeRelaySocket()),
      ),
    ],
    child: const TakhiApp(),
  ),
);

void main() {
  testWidgets(
    'a returning rider is never shown onboarding, not even for a single '
    'frame, while the stored identity is still being read',
    (t) async {
      final store = _HangingKeyStore(await _storedPrivHex());

      await _pumpApp(t, store);

      // Cold start: the read is in flight, so the app knows nothing yet.
      // Guessing "no identity" here is what used to put S1 on screen.
      expect(find.byType(OnboardingPage), findsNothing);
      await t.pump(const Duration(milliseconds: 16));
      expect(find.byType(OnboardingPage), findsNothing);
      await t.pump(const Duration(milliseconds: 16));
      expect(find.byType(OnboardingPage), findsNothing);

      store.release();
      await t.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.text('Унаа дуудах'), findsOneWidget); // home's service row
    },
  );

  testWidgets('the wait screen is the native splash continued: brand '
      'background, nothing drawn on it', (t) async {
    final store = _HangingKeyStore(await _storedPrivHex());

    await _pumpApp(t, store);

    expect(
      t.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      takhiTheme(Brightness.light).colorScheme.surface,
    );
    // Not one glyph: a label appearing for two frames and vanishing reads
    // as a glitch, which is the failure mode this screen exists to avoid.
    expect(find.byType(Text), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    store.release();
    await t.pumpAndSettle();
  });

  testWidgets('a fast read shows no loading affordance at all; only a read '
      'still outstanding at 600ms earns the gold bar', (t) async {
    final store = _HangingKeyStore(await _storedPrivHex());

    await _pumpApp(t, store);

    await t.pump(StartupGate.indicatorDelay - const Duration(milliseconds: 1));
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await t.pump(const Duration(milliseconds: 1));
    final bar = t.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.minHeight, 3);
    expect(bar.color, TakhiColors.gold);
    // Indeterminate: nothing here knows how long a key-store read takes,
    // and a fake percentage would be a lie.
    expect(bar.value, isNull);

    store.release();
    await t.pumpAndSettle();
  });

  testWidgets('a key store that never answers hands the rider onboarding '
      'after 3s rather than stranding them on a blank screen', (t) async {
    // Released nowhere in this test -- a wedged Keystore, verbatim.
    final store = _HangingKeyStore(await _storedPrivHex());

    await _pumpApp(t, store);

    await t.pump(StartupGate.readTimeout - const Duration(milliseconds: 1));
    expect(find.byType(OnboardingPage), findsNothing);

    await t.pump(const Duration(milliseconds: 1));
    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  testWidgets('a first-run rider with no stored identity lands on '
      'onboarding once the read comes back empty', (t) async {
    final store = _HangingKeyStore(null);

    await _pumpApp(t, store);
    expect(find.byType(OnboardingPage), findsNothing); // still looking

    store.release();
    await t.pumpAndSettle();

    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('Шинээр эхлэх'), findsOneWidget);
    // This test also pins the timer teardown: a 600ms/3s timer left
    // running past the answer fails `testWidgets` outright with "a Timer
    // is still pending", so the gate has to stop waiting the moment it
    // knows.
  });
}
