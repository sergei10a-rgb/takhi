// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'theme/takhi_theme.dart';

void main() => runApp(const ProviderScope(child: TakhiApp()));

class TakhiApp extends StatelessWidget {
  const TakhiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
    theme: takhiTheme(Brightness.light),
    darkTheme: takhiTheme(Brightness.dark),
    locale: const Locale('mn'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: appRouter,
  );
}
