// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/l10n/app_localizations.dart';

void main() {
  testWidgets('mn is default and appName is Тахь', (t) async {
    late AppLocalizations l;
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('mn'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            l = AppLocalizations.of(c)!;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(l.appName, 'Тахь');
    expect(l.localeName, 'mn');
  });
}
