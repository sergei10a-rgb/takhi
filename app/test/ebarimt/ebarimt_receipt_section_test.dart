// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ebarimt/ebarimt_receipt_card.dart';
import 'package:takhi/ebarimt/ebarimt_receipt_section.dart';
import 'package:takhi/l10n/app_localizations.dart';

/// The eBarimt block on the driver's finished screen (roadmap #9). It starts
/// as a single action so the payment screen is not two QR codes deep before a
/// driver who is taking cash even looks at it; the receipt appears only once
/// the driver asks for it.
Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('mn'),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  late AppLocalizations l;
  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('mn'));
  });

  testWidgets('starts as an action with no receipt on screen', (tester) async {
    await tester.pumpWidget(_host(const EbarimtReceiptSection(fareMnt: 6500)));

    expect(find.text(l.ebarimtIssueAction), findsOneWidget);
    expect(find.byType(EbarimtReceiptCard), findsNothing);
  });

  testWidgets('reveals the receipt once the driver asks for it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const EbarimtReceiptSection(fareMnt: 6500)));

    await tester.tap(find.text(l.ebarimtIssueAction));
    await tester.pumpAndSettle();

    expect(find.byType(EbarimtReceiptCard), findsOneWidget);
    // The default issuer is the demo one, so the card must carry its warning —
    // this is the wiring that would let a real-looking demo reach a passenger
    // if it were ever dropped.
    expect(find.text(l.ebarimtDemoNotice), findsOneWidget);
  });
}
