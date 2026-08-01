// SPDX-License-Identifier: AGPL-3.0-or-later
import '../l10n/app_localizations.dart';
import '../meter/money_format.dart';

/// States the distance half of a metered price and, beside it, what a minute
/// of standing still costs (spec §7.2 + §7.4).
///
/// Shared by the driver's offer dialog and the passenger's offer list on
/// purpose. Both sides have to read the same price the same way -- a rate
/// worded one way where it is offered and another where it is chosen is a
/// price neither side can check against the other. A missing or zero
/// stopped-time rate is stated outright ("stops free") rather than left as an
/// absence the reader is expected to notice: on a screen full of numbers, a
/// number that simply is not there reads as an oversight, not as a promise.
///
/// The trip-duration rate is deliberately **not** in this string. See
/// [meteredDurationTariffLabel].
String meteredTariffLabel(
  AppLocalizations l, {
  required int kmTariffMnt,
  required int? waitTariffMntPerMinute,
}) => waitTariffMntPerMinute == null || waitTariffMntPerMinute == 0
    ? l.meteredOfferNoWaitTariffLabel(groupedMnt(kmTariffMnt))
    : l.meteredOfferTariffPairLabel(
        groupedMnt(kmTariffMnt),
        groupedMnt(waitTariffMntPerMinute),
      );

/// What a minute of the trip itself costs, or `null` when the trip's duration
/// is free -- which is what an absent rate and a zero one both mean, and what
/// nearly every offer will say.
///
/// Its own string, rendered as its own chip beside [meteredTariffLabel]'s,
/// rather than as a third clause inside it. The single-string version was
/// written first, and its screenshot is why this exists: «1 500 ₮/км + 300
/// ₮/мин зогсолт + 80 ₮/мин хугацаа» does not fit an offer-card chip on a
/// 360dp phone, and that chip does not wrap -- it ellipsed to «... + 80 ₮/мин
/// хуг…», clipping the word that says what the third rate is. Every test
/// passed and the analyzer was clean; only the picture showed it. The
/// taximeter's own tariff pills had already settled the same question the
/// same way ("a truncated price is worse than a second row"), and the offer
/// card lays its qualifiers out in a `Wrap`, so a second short chip simply
/// flows onto the next line.
///
/// Silent at zero, unlike its neighbour's treatment of a free stop. The
/// asymmetry is deliberate: every metered offer has an answer about stopped
/// time, so an absent one there is genuinely ambiguous -- whereas most
/// drivers will never set a duration rate at all, and printing "duration
/// free" on every offer in the country would put a line about a charge that
/// does not exist in front of every passenger.
String? meteredDurationTariffLabel(
  AppLocalizations l,
  int? durationTariffMntPerMinute,
) => durationTariffMntPerMinute == null || durationTariffMntPerMinute == 0
    ? null
    : l.meteredOfferDurationTariffLabel(groupedMnt(durationTariffMntPerMinute));
