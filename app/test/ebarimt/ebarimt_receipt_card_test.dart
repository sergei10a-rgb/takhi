// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ebarimt/ebarimt_receipt.dart';
import 'package:takhi/ebarimt/ebarimt_receipt_card.dart';
import 'package:takhi/l10n/app_localizations.dart';

/// The card a driver shows a passenger at trip end (roadmap #9). The one rule
/// it exists to enforce visually: a demo receipt must never be able to pass
/// for a filed one, so the demo warning is part of the card, not a caption a
/// caller might forget.
const _demoReceipt = EbarimtReceipt(
  qrData: 'takhi-demo:ebarimt?amount=6500',
  lottery: 'ЖИШЭЭ',
  totalAmountMnt: 6500,
  vatMnt: 0,
  issuedAt: 1000,
);

const _realReceipt = EbarimtReceipt(
  qrData: 'https://ebarimt.mn/receipt?id=abc123',
  lottery: 'AB 12345678',
  totalAmountMnt: 6500,
  vatMnt: 591,
  issuedAt: 1000,
);

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

  testWidgets('a demo receipt says outright it is not an official one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const EbarimtReceiptCard(receipt: _demoReceipt, isDemo: true)),
    );

    expect(find.text(l.ebarimtDemoNotice), findsOneWidget);
    expect(find.text(l.ebarimtLotteryLabel('ЖИШЭЭ')), findsOneWidget);
  });

  testWidgets('a real receipt carries no demo warning', (tester) async {
    await tester.pumpWidget(
      _host(const EbarimtReceiptCard(receipt: _realReceipt)),
    );

    expect(find.text(l.ebarimtDemoNotice), findsNothing);
    expect(find.text(l.ebarimtLotteryLabel('AB 12345678')), findsOneWidget);
  });
}
