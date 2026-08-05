// SPDX-License-Identifier: AGPL-3.0-or-later
import 'ebarimt_receipt.dart';

/// The seam between Takhi and the driver's OWN eBarimt registration
/// (roadmap #9).
///
/// This is the one boundary where the ownerless design meets the state's tax
/// system, and the shape of it is deliberate: the app holds an [EbarimtIssuer]
/// that talks to *the driver's* PosAPI on *the driver's* device, with *the
/// driver's* registration. There is no Takhi server in the path and no Takhi
/// legal entity — the same reason the app can stay ownerless is the reason a
/// concrete implementation cannot ship inside it: it needs credentials and a
/// PosAPI endpoint that belong to each driver, not to the app.
///
/// So production wires a concrete implementation against the real PosAPI once
/// its request/response format is confirmed from the official spec (it is not
/// guessed here); tests supply a fake. Everything above this interface — when
/// to issue, what to show — is proven against that fake.
abstract interface class EbarimtIssuer {
  /// Issues a legal eBarimt for a [grossMnt] fare through the driver's PosAPI
  /// and returns the receipt it minted. The implementation performs the
  /// network call; callers await the result.
  Future<EbarimtReceipt> issue({required int grossMnt, required int now});
}

/// Issues a fare receipt only when the driver has connected their eBarimt and
/// the passenger asked for one, and returns `null` otherwise.
///
/// A cash rider who wants no receipt is not an error, and a passenger asking a
/// driver who never registered simply cannot be given one — both are ordinary
/// outcomes, not failures, so this returns `null` rather than throwing. The
/// PosAPI is not touched in either case.
Future<EbarimtReceipt?> maybeIssueFareReceipt({
  required bool driverConnected,
  required bool passengerWantsReceipt,
  required EbarimtIssuer? issuer,
  required int grossMnt,
  required int now,
}) async {
  if (!driverConnected || !passengerWantsReceipt || issuer == null) {
    return null;
  }
  return issuer.issue(grossMnt: grossMnt, now: now);
}
