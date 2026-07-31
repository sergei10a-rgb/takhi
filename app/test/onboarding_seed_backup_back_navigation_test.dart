// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/onboarding/seed_backup_page.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

const _title = 'Нөөц үгсээ хадгал';
const _leaveTitle = 'Нөөц үгсээ хадгалсан уу?';
const _stay = 'Үлдэх';
const _leave = 'Нүүр хуудас руу';
const _home = 'HOME_REACHED';

/// The tick that unlocks the forward exit -- `seedBackupConfirmLabel`.
const _acknowledge = '12 үгээ бичиж авлаа';

/// Boots straight onto `/seed`, exactly as `OnboardingPage._createIdentity`
/// leaves the app: it gets there with `context.go`, which *replaces* the
/// stack, so this route is the only entry on it -- there is no back arrow,
/// and a hardware back would otherwise take the rider out of the one screen
/// that will ever show these 12 words.
Widget _harness() => MaterialApp.router(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('mn'),
  routerConfig: GoRouter(
    initialLocation: '/seed',
    routes: [
      GoRoute(
        path: '/seed',
        builder: (context, state) => const SeedBackupPage(mnemonic: _mnemonic),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text(_home))),
      ),
    ],
  ),
);

/// Delivers the platform's `popRoute` message -- what Android's hardware
/// back button and iOS' back gesture actually send. The only back this
/// screen can receive: with no route underneath, there is no `AppBar`
/// arrow to tap.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
}

void main() {
  testWidgets('a stray hardware back on the recovery phrase asks first -- it '
      'no longer walks out of the only screen that shows it', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();
    expect(find.text(_title), findsOneWidget);

    await _systemBack(t);
    await t.pumpAndSettle();

    expect(find.text(_leaveTitle), findsOneWidget);
    // Intercepted, not popped: the words are still there behind the dialog.
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_home), findsNothing);
  });

  testWidgets('"Үлдэх" puts the rider back on the phrase with nothing lost', (
    t,
  ) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    await _systemBack(t);
    await t.pumpAndSettle();
    await t.tap(find.text(_stay));
    await t.pumpAndSettle();

    expect(find.text(_leaveTitle), findsNothing);
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_home), findsNothing);
  });

  testWidgets('confirming leaves for /home -- this route is the root of the '
      'stack, so a plain pop would have done nothing at all', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    await _systemBack(t);
    await t.pumpAndSettle();
    await t.tap(find.text(_leave));
    await t.pumpAndSettle();

    expect(find.text(_home), findsOneWidget);
    expect(find.text(_title), findsNothing);
    expect(find.text(_leaveTitle), findsNothing);
  });

  testWidgets('the forward exit waits on an explicit acknowledgement -- the '
      'most irreversible screen in the app no longer has the least friction '
      'on it', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    // Live from the first frame, this button let a rider tap straight past
    // twelve words they had not read, and nothing afterwards can undo that.
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.tap(find.text('Хадгаллаа'));
    await t.pumpAndSettle();
    expect(find.text(_home), findsNothing);
  });

  testWidgets('once acknowledged, "Хадгаллаа" still goes straight through, '
      'unguarded -- confirming a deliberate exit would be pure noise', (
    t,
  ) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    await t.tap(find.text(_acknowledge));
    await t.pump();
    await t.tap(find.text('Хадгаллаа'));
    await t.pumpAndSettle();

    expect(find.text(_leaveTitle), findsNothing);
    expect(find.text(_home), findsOneWidget);
  });
}
