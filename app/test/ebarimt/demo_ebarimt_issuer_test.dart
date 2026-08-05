// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ebarimt/demo_ebarimt_issuer.dart';

/// The stand-in issuer used until a driver's real PosAPI is wired (roadmap
/// #9). Its whole job is to let the trip-end screen be built and looked at
/// now, while making it impossible to mistake what it mints for a real
/// government receipt — a receipt-shaped card that lied about being filed
/// would be worse than none.
void main() {
  test('mints a receipt for the fare it was asked about', () async {
    const issuer = DemoEbarimtIssuer();
    final receipt = await issuer.issue(grossMnt: 6500, now: 1000);
    expect(receipt.totalAmountMnt, 6500);
    expect(receipt.issuedAt, 1000);
    expect(receipt.qrData, isNotEmpty);
  });

  test('announces itself as a demo, not a filed fiscal record', () async {
    const issuer = DemoEbarimtIssuer();
    final receipt = await issuer.issue(grossMnt: 6500, now: 1000);
    // The lottery code a real eBarimt carries is replaced by a marker no real
    // receipt would ever use, so nothing downstream mistakes it for filed.
    expect(receipt.lottery, kEbarimtDemoLottery);
    // A demo must not invent a VAT figure — computing tax is the real
    // PosAPI's job, and a fabricated number is the exact lie this stands in
    // for until that exists.
    expect(receipt.vatMnt, 0);
    // Its QR points at nothing fiscal — never at the real ebarimt.mn.
    expect(receipt.qrData, isNot(contains('ebarimt.mn')));
  });
}
