// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ebarimt/ebarimt_receipt.dart';
import 'package:takhi/ebarimt/ebarimt_issuer.dart';

/// The gate in front of the driver's PosAPI (roadmap #9).
///
/// A receipt is issued only when two things are true at once: the driver has
/// connected their own eBarimt registration, and the passenger asked for a
/// receipt. Neither alone is enough — a connected driver carrying a cash
/// rider who wants nothing should mint no receipt, and a passenger asking a
/// driver who never registered cannot be given one. The rule lives in a pure
/// function so it can be proven without standing up a payment screen.
class _FakeIssuer implements EbarimtIssuer {
  int calls = 0;
  int? lastGross;

  @override
  Future<EbarimtReceipt> issue({required int grossMnt, required int now}) async {
    calls++;
    lastGross = grossMnt;
    return EbarimtReceipt(
      qrData: 'https://ebarimt.mn/receipt?id=test',
      lottery: 'ZZ 00000001',
      totalAmountMnt: grossMnt,
      vatMnt: (grossMnt * 10) ~/ 110,
      issuedAt: now,
    );
  }
}

void main() {
  test('issues a receipt when connected and the passenger asked', () async {
    final issuer = _FakeIssuer();
    final receipt = await maybeIssueFareReceipt(
      driverConnected: true,
      passengerWantsReceipt: true,
      issuer: issuer,
      grossMnt: 6500,
      now: 1000,
    );
    expect(receipt, isNotNull);
    expect(receipt!.totalAmountMnt, 6500);
    expect(issuer.calls, 1);
    expect(issuer.lastGross, 6500);
  });

  test('issues nothing when the driver has not connected eBarimt', () async {
    final issuer = _FakeIssuer();
    final receipt = await maybeIssueFareReceipt(
      driverConnected: false,
      passengerWantsReceipt: true,
      issuer: issuer,
      grossMnt: 6500,
      now: 1000,
    );
    expect(receipt, isNull);
    expect(issuer.calls, 0, reason: 'the PosAPI must not be called');
  });

  test('issues nothing when the passenger does not want a receipt', () async {
    final issuer = _FakeIssuer();
    final receipt = await maybeIssueFareReceipt(
      driverConnected: true,
      passengerWantsReceipt: false,
      issuer: issuer,
      grossMnt: 6500,
      now: 1000,
    );
    expect(receipt, isNull);
    expect(issuer.calls, 0);
  });

  test('issues nothing when no issuer is configured', () async {
    final receipt = await maybeIssueFareReceipt(
      driverConnected: true,
      passengerWantsReceipt: true,
      issuer: null,
      grossMnt: 6500,
      now: 1000,
    );
    expect(receipt, isNull);
  });
}
