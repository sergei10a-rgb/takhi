// SPDX-License-Identifier: AGPL-3.0-or-later
import '../l10n/app_localizations.dart';
import '../meter/money_format.dart';

/// States a metered price in full: the km-tariff and, beside it, what a
/// minute of standing still costs (spec §7.2 + §7.4).
///
/// Shared by the driver's offer dialog and the passenger's offer list on
/// purpose. Both sides have to read the same price the same way -- a rate
/// worded one way where it is offered and another where it is chosen is a
/// price neither side can check against the other. A missing or zero
/// waiting rate is stated outright ("waiting free") rather than left as an
/// absence the reader is expected to notice: on a screen full of numbers, a
/// number that simply is not there reads as an oversight, not as a promise.
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
