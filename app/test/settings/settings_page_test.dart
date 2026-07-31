// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/settings/settings_page.dart';
import 'package:takhi/widgets/menu_row.dart';

Widget _harness() => const ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale('mn'),
    home: SettingsPage(),
  ),
);

void main() {
  testWidgets('lists every settings destination, including the emergency '
      'contact -- whose only other entry point disappears as soon as a '
      'number is saved', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Жолоочийн профайл'), findsOneWidget);
    expect(find.text('Аяллын түүх'), findsOneWidget);
    expect(find.text('Утасны дугаар'), findsOneWidget);
    expect(find.text('Яаралтай үеийн хүн'), findsOneWidget);
    expect(find.text('Хууль зүйн сануулга'), findsOneWidget);
  });

  testWidgets('every row says what is behind it -- a menu of bare nouns can '
      'only be read by opening each one', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    for (final row in tester.widgetList<MenuRow>(find.byType(MenuRow))) {
      expect(
        row.subtitle,
        isNotNull,
        reason: '"${row.label}" has no line saying what it leads to',
      );
      expect(row.subtitle, isNotEmpty);
      expect(
        row.subtitle,
        isNot(row.label),
        reason: '"${row.label}" only restates itself',
      );
    }
  });

  testWidgets('tapping the emergency-contact row pushes its route', (
    tester,
  ) async {
    final pushed = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          routerConfig: GoRouter(
            initialLocation: '/settings',
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
              GoRoute(
                path: '/settings/emergency-contact',
                builder: (context, state) {
                  pushed.add('/settings/emergency-contact');
                  return const Scaffold(body: Text('emergency-stub'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Яаралтай үеийн хүн'));
    await tester.pumpAndSettle();

    expect(pushed, ['/settings/emergency-contact']);
  });

  // The journal is the only screen that can answer "what did I take this
  // week", and this row is its only entrance -- the meter itself shows one
  // run and then forgets it.
  testWidgets('tapping the trip-history row pushes /settings/journal', (
    tester,
  ) async {
    final pushed = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          routerConfig: GoRouter(
            initialLocation: '/settings',
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
              GoRoute(
                path: '/settings/journal',
                builder: (context, state) {
                  pushed.add('/settings/journal');
                  return const Scaffold(body: Text('journal-stub'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Аяллын түүх'));
    await tester.pumpAndSettle();

    expect(pushed, ['/settings/journal']);
    expect(find.text('journal-stub'), findsOneWidget);
  });

  testWidgets(
    'tapping the driver-profile tile pushes /settings/driver-profile',
    (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            routerConfig: GoRouter(
              initialLocation: '/settings',
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const SettingsPage(),
                ),
                GoRoute(
                  path: '/settings/driver-profile',
                  builder: (context, state) {
                    pushed.add('/settings/driver-profile');
                    return const Scaffold(body: Text('driver-profile-stub'));
                  },
                ),
                GoRoute(
                  path: '/settings/phone-share',
                  builder: (context, state) =>
                      const Scaffold(body: Text('phone-share-stub')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Жолоочийн профайл'));
      await tester.pumpAndSettle();

      expect(pushed, ['/settings/driver-profile']);
      expect(find.text('driver-profile-stub'), findsOneWidget);
    },
  );
}
