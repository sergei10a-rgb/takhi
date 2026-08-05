// SPDX-License-Identifier: AGPL-3.0-or-later

/// A legal eBarimt (И-Баримт) VAT receipt for a single fare (roadmap #9).
///
/// **Takhi does not compute the tax and never touches the money.** Mongolia
/// requires an eBarimt for a paid ride, but the authority that issues one is
/// the driver's OWN eBarimt registration, reached through their PosAPI on
/// their own device. That service works out the VAT, mints the lottery code,
/// and returns the QR payload the passenger scans; this class is the shape of
/// that answer, held just long enough to show the passenger a code and, if
/// they ask, to keep a copy. The Takhi network sees none of it.
///
/// The fields cross a trust boundary — they arrive from the PosAPI, not from
/// a value this app produced — so [fromJson] type-checks every one and throws
/// a [FormatException], never an uncaught `TypeError`, on any mismatch. A
/// caller can filter a malformed receipt with `on FormatException` instead of
/// a crafted response crashing the isolate at the moment a passenger is
/// waiting to pay.
class EbarimtReceipt {
  /// The QR payload the passenger scans to verify the receipt on ebarimt.mn
  /// and enter it in the VAT lottery. Produced by the PosAPI; never empty.
  final String qrData;

  /// The VAT-lottery code the state assigns to this receipt.
  final String lottery;

  /// The gross fare the receipt was issued for, in tögrög.
  final int totalAmountMnt;

  /// The VAT portion of [totalAmountMnt], as the eBarimt system worked it
  /// out. Displayed, never recomputed here — the authority on the number is
  /// the system that issued the receipt, not this app.
  final int vatMnt;

  /// Unix seconds when the receipt was issued.
  final int issuedAt;

  const EbarimtReceipt({
    required this.qrData,
    required this.lottery,
    required this.totalAmountMnt,
    required this.vatMnt,
    required this.issuedAt,
  });

  factory EbarimtReceipt.fromJson(Map<String, dynamic> json) {
    final qrData = _requiredString(json, 'qrData');
    if (qrData.isEmpty) {
      throw const FormatException(
          'EbarimtReceipt.fromJson: qrData must not be empty');
    }
    return EbarimtReceipt(
      qrData: qrData,
      lottery: _requiredString(json, 'lottery'),
      totalAmountMnt: _requiredInt(json, 'totalAmountMnt'),
      vatMnt: _requiredInt(json, 'vatMnt'),
      issuedAt: _requiredInt(json, 'issuedAt'),
    );
  }

  Map<String, dynamic> toJson() => {
        'qrData': qrData,
        'lottery': lottery,
        'totalAmountMnt': totalAmountMnt,
        'vatMnt': vatMnt,
        'issuedAt': issuedAt,
      };

  @override
  bool operator ==(Object other) =>
      other is EbarimtReceipt &&
      other.qrData == qrData &&
      other.lottery == lottery &&
      other.totalAmountMnt == totalAmountMnt &&
      other.vatMnt == vatMnt &&
      other.issuedAt == issuedAt;

  @override
  int get hashCode =>
      Object.hash(qrData, lottery, totalAmountMnt, vatMnt, issuedAt);

  @override
  String toString() =>
      'EbarimtReceipt(lottery: $lottery, total: $totalAmountMnt, '
      'vat: $vatMnt)';
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String) return value;
  throw FormatException(
      "EbarimtReceipt.fromJson: '$field' must be a String, got "
      '${value.runtimeType}');
}

int _requiredInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is int) return value;
  throw FormatException(
      "EbarimtReceipt.fromJson: '$field' must be an int, got "
      '${value.runtimeType}');
}
