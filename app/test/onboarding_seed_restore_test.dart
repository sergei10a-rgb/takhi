// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/onboarding/restore_page.dart';
import 'package:takhi/onboarding/seed_backup_page.dart';

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

/// Minimal harness router mirroring the shape of the real [appRouter]'s
/// `/seed` -> `/restore` -> `/home` legs, without pulling in [HomePage]
/// (which reads `currentIdentityProvider` and adds unrelated setup). The
/// distinguishing text on `/home` is enough to prove `context.go('/home')`
/// actually fired.
GoRouter _harnessRouter({required String initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/seed',
      builder: (context, state) =>
          const SeedBackupPage(mnemonic: _validMnemonic),
    ),
    GoRoute(path: '/restore', builder: (context, state) => const RestorePage()),
    GoRoute(
      path: '/home',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('HOME_REACHED'))),
    ),
  ],
);

Widget _harness(GoRouter router, {KeyStore? keyStore}) => ProviderScope(
  overrides: [
    if (keyStore != null) keyStoreProvider.overrideWithValue(keyStore),
  ],
  child: MaterialApp.router(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('mn'),
    routerConfig: router,
  ),
);

void main() {
  group('SeedBackupPage', () {
    testWidgets('renders title, warning and all 12 numbered words', (t) async {
      // The grid sits inside a scroll view, so the default 800x600 test
      // surface only paints the rows that fit. Every tile is *built*
      // regardless (the grid is a plain Column, not a lazy GridView), but
      // the surface is grown anyway so a failure here reads as "a word is
      // missing" rather than "a word is below the fold".
      final originalSize = t.view.physicalSize;
      final originalRatio = t.view.devicePixelRatio;
      addTearDown(() {
        t.view.physicalSize = originalSize;
        t.view.devicePixelRatio = originalRatio;
      });
      t.view.physicalSize = const Size(1200, 4000);
      t.view.devicePixelRatio = 1.0;

      await t.pumpWidget(_harness(_harnessRouter(initialLocation: '/seed')));

      expect(find.text('Нөөц үгсээ хадгал'), findsOneWidget);
      expect(find.textContaining('Энэ 12 үгийг бичиж хадгал'), findsOneWidget);

      // Each grid cell renders as one Text.rich with an ordinal span
      // ("7. ") followed by the word span ("abandon"). Matching on the
      // full concatenated plain text (rather than a substring) avoids
      // false positives like "1. " matching inside "11. ".
      final words = _validMnemonic.split(' ');
      expect(words, hasLength(12));
      for (var i = 0; i < words.length; i++) {
        final expectedText = '${i + 1}. ${words[i]}';
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && w.textSpan?.toPlainText() == expectedText,
          ),
          findsOneWidget,
          reason: 'expected exactly one grid cell reading "$expectedText"',
        );
      }
    });

    testWidgets('acknowledging the phrase, then tapping "I saved it", '
        'navigates to /home', (t) async {
      await t.pumpWidget(_harness(_harnessRouter(initialLocation: '/seed')));

      // The tick is the gate: see the back-navigation test for the half of
      // this that proves the button is dead until it is ticked.
      await t.tap(find.text('12 үгээ бичиж авлаа'));
      await t.pump();
      await t.tap(find.text('Хадгаллаа'));
      await t.pumpAndSettle();

      expect(find.text('HOME_REACHED'), findsOneWidget);
    });
  });

  group('RestorePage', () {
    testWidgets('tapping restore with an empty field does nothing', (t) async {
      await t.pumpWidget(
        _harness(
          _harnessRouter(initialLocation: '/restore'),
          keyStore: InMemoryKeyStore(),
        ),
      );

      await t.tap(find.byType(FilledButton));
      await t.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('HOME_REACHED'), findsNothing);
    });

    testWidgets('valid mnemonic restores identity and navigates to /home', (
      t,
    ) async {
      await t.pumpWidget(
        _harness(
          _harnessRouter(initialLocation: '/restore'),
          keyStore: InMemoryKeyStore(),
        ),
      );

      await t.enterText(find.byType(TextField), _validMnemonic);
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();

      expect(find.text('HOME_REACHED'), findsOneWidget);
    });

    testWidgets(
      'invalid mnemonic shows inline error and re-enables the button',
      (t) async {
        await t.pumpWidget(
          _harness(
            _harnessRouter(initialLocation: '/restore'),
            keyStore: InMemoryKeyStore(),
          ),
        );

        await t.enterText(find.byType(TextField), 'not a real seed phrase');
        await t.tap(find.byType(FilledButton));
        await t.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('HOME_REACHED'), findsNothing);
        expect(
          find.text('Нөөц үг буруу байна. Дахин шалгаад оруулна уу.'),
          findsOneWidget,
        );

        final button = t.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('the whole phrase goes into one field, and a live count says '
        'how far along it is', (t) async {
      await t.pumpWidget(
        _harness(
          _harnessRouter(initialLocation: '/restore'),
          keyStore: InMemoryKeyStore(),
        ),
      );

      // One field, not twelve: nobody fills in twelve inputs on a phone,
      // and the paste has to land in a single box.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('0 / 12 үг'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'abandon abandon  about ');
      await t.pump();
      // Whitespace-separated and empties dropped, so a double space or a
      // trailing one does not read as another word.
      expect(find.text('3 / 12 үг'), findsOneWidget);

      await t.enterText(find.byType(TextField), _validMnemonic);
      await t.pump();
      expect(find.text('12 / 12 үг'), findsOneWidget);
    });

    testWidgets('the count informs but never gates: an eleven-word phrase is '
        'still submitted, and BIP-39 gives the verdict', (t) async {
      await t.pumpWidget(
        _harness(
          _harnessRouter(initialLocation: '/restore'),
          keyStore: InMemoryKeyStore(),
        ),
      );

      await t.enterText(
        find.byType(TextField),
        _validMnemonic.split(' ').take(11).join(' '),
      );
      await t.pump();

      expect(find.text('11 / 12 үг'), findsOneWidget);
      // Not disabled -- attempting is more useful than a silent refusal.
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(
        find.text('Нөөц үг буруу байна. Дахин шалгаад оруулна уу.'),
        findsOneWidget,
      );
    });

    testWidgets('retrying after an error clears the inline message', (t) async {
      await t.pumpWidget(
        _harness(
          _harnessRouter(initialLocation: '/restore'),
          keyStore: InMemoryKeyStore(),
        ),
      );

      await t.enterText(find.byType(TextField), 'bad seed words');
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(
        find.text('Нөөц үг буруу байна. Дахин шалгаад оруулна уу.'),
        findsOneWidget,
      );

      await t.enterText(find.byType(TextField), _validMnemonic);
      await t.tap(find.byType(FilledButton));
      await t.pump();

      expect(
        find.text('Нөөц үг буруу байна. Дахин шалгаад оруулна уу.'),
        findsNothing,
      );

      await t.pumpAndSettle();
      expect(find.text('HOME_REACHED'), findsOneWidget);
    });
  });
}
