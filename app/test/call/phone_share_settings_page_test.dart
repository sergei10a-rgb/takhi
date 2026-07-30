// SPDX-License-Identifier: AGPL-3.0-or-later

/// Regression coverage for Plan 5's review CRITICAL-2: before this screen
/// existed, `PhoneShareSettingsStore.saveOwnPhone`/`.setEnabled` were
/// never called anywhere in production, so `RideHandoffPayload.phone`
/// (read correctly by `PassengerRidePage._select`) was always `null` and
/// `CallStateFallbackPhone` could never fire. These tests exercise the
/// screen itself; `passenger_ride_page_test.dart`'s existing "selecting an
/// offer with a saved own phone number..." test covers the read side.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_providers.dart';
import 'package:takhi/call/phone_share_settings.dart';
import 'package:takhi/call/phone_share_settings_page.dart';
import 'package:takhi/l10n/app_localizations.dart';

/// `phoneShareEnabledToggleLabel` -- the toggle row's heavy line, and what
/// these tests tap. The row is the target rather than the switch itself:
/// the thumb is a scrap of paint inside a card that fills the screen's
/// width, and the screen deliberately routes the gesture to the card so a
/// tap anywhere on it flips the value exactly once.
const _toggleLabel = 'Дугаараа тохирсон хүнд илгээх';

Widget _harness(PhoneShareSettingsStore store) => ProviderScope(
  overrides: [phoneShareSettingsStoreProvider.overrideWithValue(store)],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('mn'),
    home: const PhoneShareSettingsPage(),
  ),
);

void main() {
  testWidgets(
    'loads an already-saved phone number and enabled state into the form',
    (tester) async {
      final store = InMemoryPhoneShareSettingsStore();
      await store.saveOwnPhone('99112233');
      await store.setEnabled(false);

      await tester.pumpWidget(_harness(store));
      await tester.pumpAndSettle();

      expect(find.text('99112233'), findsOneWidget);
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isFalse);
    },
  );

  testWidgets(
    'defaults the toggle to enabled (spec §7.3-②: "default: асаалттай") '
    'when nothing has been saved yet',
    (tester) async {
      await tester.pumpWidget(_harness(InMemoryPhoneShareSettingsStore()));
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isTrue);
    },
  );

  testWidgets(
    'entering a number, flipping the toggle off, and saving persists both '
    'through the store and pops the screen',
    (tester) async {
      final store = InMemoryPhoneShareSettingsStore();
      var popped = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [phoneShareSettingsStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                builder: (_) => const PhoneShareSettingsPage(),
              ),
              observers: [_PopWatcher(() => popped = true)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '88001122');
      // `enterText` does not itself pump a frame, so the `PrimaryButton`'s
      // `onPressed` (computed from `_controller.text` on every build)
      // would still be the stale, disabled `null` from before typing
      // without this -- the next tap would silently no-op.
      await tester.pump();
      await tester.tap(find.text(_toggleLabel)); // flip off
      await tester.pump();
      // Exactly once: the row owns the gesture and the switch inside it is
      // wrapped in an `IgnorePointer`, so a tap cannot toggle both.
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      expect(await store.loadOwnPhone(), '88001122');
      expect(await store.isEnabled(), isFalse);
      expect(popped, isTrue);
    },
  );

  testWidgets('the save button is disabled while the phone field is empty', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(InMemoryPhoneShareSettingsStore()));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'Хадгалах');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '99887766');
    await tester.pump();

    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });
}

class _PopWatcher extends NavigatorObserver {
  final VoidCallback onPop;
  _PopWatcher(this.onPop);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPop();
  }
}
