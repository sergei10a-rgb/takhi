// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/legal/legal_notice_page.dart';

Widget _harness() => const MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale('mn'),
  home: LegalNoticePage(),
);

void main() {
  testWidgets('shows the legal-notice title and body (spec §4)', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Хууль зүйн мэдэгдэл'), findsWidgets);
    expect(
      find.textContaining('Тахь бол эзэнгүй P2P платформ'),
      findsOneWidget,
    );
    expect(find.textContaining('Жолоочийн шалгалт байхгүй'), findsOneWidget);
  });
}
