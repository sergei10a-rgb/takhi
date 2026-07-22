// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/settings/settings_page.dart';

Widget _harness() => const ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale('mn'),
    home: SettingsPage(),
  ),
);

void main() {
  testWidgets('lists the driver-profile and phone-share menu entries', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Жолоочийн профайл'), findsOneWidget);
    expect(find.text('Утасны дугаар'), findsOneWidget);
    expect(find.text('Хууль зүйн сануулга'), findsOneWidget);
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
