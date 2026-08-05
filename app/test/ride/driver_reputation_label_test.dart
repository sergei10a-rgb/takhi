// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/ride/driver_offer_view.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

/// Roadmap #12 — the one fact the offer list did not yet say out loud: that a
/// driver about to pull up is one this passenger has ridden with and chose to
/// trust before. It rides on the same reputation subtitle as everything else,
/// so a returning rider reads "someone you trust" in the same glance they
/// already give the row, rather than re-deriving it from a key.
void main() {
  late AppLocalizations l;
  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('mn'));
  });

  Reputation rep({int paired = 3, int distinct = 2}) =>
      Reputation(paired, 4.7, 2.0, distinctCounterpartyCount: distinct);

  test('names a driver the viewer has vouched for as one they trust', () {
    expect(
      driverReputationLabel(l, rep(), viewerTrusts: true),
      l.driverTrustedByYouLabel,
    );
  });

  test('a vouch outranks the trip summary, even on a thin history', () {
    expect(
      driverReputationLabel(l, rep(paired: 1, distinct: 1), viewerTrusts: true),
      l.driverTrustedByYouLabel,
    );
  });

  test('without a vouch, still reads as the trips both sides confirmed', () {
    expect(
      driverReputationLabel(l, rep()),
      l.driverReputationSummaryLabel(3, 2),
    );
  });

  test('a driver with no history and no vouch is named new', () {
    expect(driverReputationLabel(l, rep(paired: 0, distinct: 0)),
        l.driverNewLabel);
  });
}
