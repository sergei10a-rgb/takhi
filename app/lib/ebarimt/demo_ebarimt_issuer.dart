// SPDX-License-Identifier: AGPL-3.0-or-later
import 'ebarimt_issuer.dart';
import 'ebarimt_receipt.dart';

/// The lottery slot on a demo receipt. Not a code — a word, in place of the
/// eight-character lottery a real eBarimt carries, so nothing that reads a
/// receipt can mistake a demo for one the state has on file.
const kEbarimtDemoLottery = 'ЖИШЭЭ';

/// A stand-in [EbarimtIssuer] for before a driver's real PosAPI is connected
/// (roadmap #9).
///
/// It exists so the trip-end receipt flow and its screen can be built and
/// looked at now, and for nothing else. Every field it returns is chosen to
/// make the result unmistakably NOT a filed fiscal record: the lottery slot
/// holds [kEbarimtDemoLottery] rather than a real code, the VAT is left at
/// zero because computing tax is the real system's job and a fabricated figure
/// is the exact harm this is careful to avoid, and the QR points at a
/// `takhi-demo:` scheme that resolves to nothing at ebarimt.mn. The screen
/// that shows it must still say, in words, that it is a demo — this only makes
/// the data honest, not the presentation.
///
/// Swapped for a real `EbarimtIssuer` (a PosAPI client) once that exists; the
/// call site is [maybeIssueFareReceipt] and the screen above it, neither of
/// which knows or cares which issuer it holds.
class DemoEbarimtIssuer implements EbarimtIssuer {
  const DemoEbarimtIssuer();

  @override
  Future<EbarimtReceipt> issue({
    required int grossMnt,
    required int now,
  }) async =>
      EbarimtReceipt(
        qrData: 'takhi-demo:ebarimt?amount=$grossMnt&at=$now',
        lottery: kEbarimtDemoLottery,
        totalAmountMnt: grossMnt,
        vatMnt: 0,
        issuedAt: now,
      );
}
