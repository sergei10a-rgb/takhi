// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ebarimt/ebarimt_receipt.dart';

/// Roadmap #9 — the legal eBarimt (И-Баримт) VAT receipt.
///
/// Takhi does not compute the tax. The driver's OWN eBarimt registration —
/// through their PosAPI — is the authority that issues the receipt and hands
/// back the QR payload, the lottery code, and the VAT it worked out. This
/// model is the shape of that answer, and it is parsed at a trust boundary:
/// the fields come from outside the app, so a malformed one is a
/// `FormatException` a caller can filter, never an uncaught `TypeError`.
void main() {
  Map<String, dynamic> validJson() => {
        'qrData': 'https://ebarimt.mn/receipt?id=abc123',
        'lottery': 'AB 12345678',
        'totalAmountMnt': 6500,
        'vatMnt': 591,
        'issuedAt': 1000,
      };

  group('EbarimtReceipt.fromJson', () {
    test('round-trips every field through toJson', () {
      final receipt = EbarimtReceipt.fromJson(validJson());
      expect(receipt.qrData, 'https://ebarimt.mn/receipt?id=abc123');
      expect(receipt.lottery, 'AB 12345678');
      expect(receipt.totalAmountMnt, 6500);
      expect(receipt.vatMnt, 591);
      expect(receipt.issuedAt, 1000);
      expect(EbarimtReceipt.fromJson(receipt.toJson()), receipt);
    });

    test('rejects an empty QR payload — a receipt nobody can scan is none', () {
      final json = validJson()..['qrData'] = '';
      expect(() => EbarimtReceipt.fromJson(json), throwsFormatException);
    });

    test('rejects a missing required field', () {
      final json = validJson()..remove('lottery');
      expect(() => EbarimtReceipt.fromJson(json), throwsFormatException);
    });

    test('rejects a field of the wrong type rather than crashing', () {
      final json = validJson()..['totalAmountMnt'] = '6500'; // String, not int
      expect(() => EbarimtReceipt.fromJson(json), throwsFormatException);
    });
  });

  test('two receipts with the same fields are equal', () {
    expect(
      EbarimtReceipt.fromJson(validJson()),
      EbarimtReceipt.fromJson(validJson()),
    );
  });
}
