// SPDX-License-Identifier: AGPL-3.0-or-later

/// What other drivers on this network are actually charging.
///
/// This is the answer to a problem the author raised and was right about:
/// the app prefills a driver's rates, and the moment it calls those figures
/// "the market price" two things follow. A passenger can point at the app to
/// argue a driver down once the market has moved past it, and somebody
/// becomes responsible for keeping the number current — which an app with
/// nobody at the middle of it cannot have.
///
/// A survey of the network has neither problem. Nobody maintains it: when
/// the market moves to 3,000₮ the drivers move first and the figure follows
/// them the same day. And it is not a claim by the app at all — it is a
/// count of what is already published.
///
/// **Shown only to drivers.** The same number is help to one side and a
/// bargaining anchor against the other, so it appears on the tariff form
/// and nowhere a passenger can see it.
library;

/// How many published tariffs it takes before a survey means anything.
///
/// Below this the "median" is one or two people, and printing it would
/// dress a coincidence up as a market. Five is small, deliberately: this
/// app starts with a handful of drivers and a survey that waits for
/// hundreds would never appear at all.
const int kMinTariffSampleSize = 5;

/// Tariffs this far apart from the median are left out.
///
/// A driver who typed 15 instead of 15,000 — or 150,000 instead of 1,500 —
/// publishes a figure that drags an average badly. The median is already
/// resistant to that, and trimming the tail as well keeps the *range* the
/// survey reports from being nonsense.
const double kTariffOutlierFactor = 4.0;

/// What other drivers charge per kilometre, as far as this phone has seen.
class TariffSurvey {
  /// The middle figure, in ₮/km.
  final int medianMntPerKm;

  /// How many published tariffs it was taken from, after trimming.
  final int sampleSize;

  /// The trimmed range, for a driver who wants to know how much spread
  /// there is behind one number.
  final int lowMntPerKm;
  final int highMntPerKm;

  const TariffSurvey({
    required this.medianMntPerKm,
    required this.sampleSize,
    required this.lowMntPerKm,
    required this.highMntPerKm,
  });
}

/// Summarises [tariffs], or `null` when there is not enough to say.
///
/// Null rather than a figure with a caveat: a survey of two drivers is not
/// a small survey, it is not a survey, and a screen that prints it with an
/// asterisk is still a screen that printed it.
TariffSurvey? summariseTariffs(Iterable<int> tariffs) {
  // A zero or negative rate is not a price. Nothing here is validated at
  // the source -- these come off the open network, published by any client
  // anyone cares to write -- so the filtering happens where the reading is.
  final usable = tariffs.where((t) => t > 0).toList()..sort();
  if (usable.length < kMinTariffSampleSize) return null;

  final rough = _median(usable);
  final trimmed =
      usable
          .where(
            (t) =>
                t <= rough * kTariffOutlierFactor &&
                t >= rough / kTariffOutlierFactor,
          )
          .toList()
        ..sort();
  if (trimmed.length < kMinTariffSampleSize) return null;

  return TariffSurvey(
    medianMntPerKm: _median(trimmed),
    sampleSize: trimmed.length,
    lowMntPerKm: trimmed.first,
    highMntPerKm: trimmed.last,
  );
}

/// Middle value of a sorted, non-empty list. An even count averages the two
/// middles, which is the ordinary definition and keeps a two-priced network
/// from reporting whichever of the two happened to sort first.
int _median(List<int> sorted) {
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}
