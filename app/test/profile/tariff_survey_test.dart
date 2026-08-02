// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The app must never say "this is the market price".
//
// The moment it does, a passenger can point at it to argue a driver down
// once the market has moved past the figure, and somebody becomes
// responsible for keeping that figure current — which an app with nobody at
// the middle of it cannot have. A count of what other drivers have already
// published has neither problem: nobody maintains it, and it is not a claim
// by the app at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/profile/tariff_survey.dart';

void main() {
  test('says nothing at all below the minimum sample', () {
    // Not "a small survey" — not a survey. A screen that printed two
    // drivers' rates with an asterisk is still a screen that printed them.
    expect(summariseTariffs([1500, 1600]), isNull);
    expect(summariseTariffs(List.filled(kMinTariffSampleSize - 1, 1500)),
        isNull);
  });

  test('reports the middle figure once there are enough', () {
    final survey = summariseTariffs([1200, 1400, 1500, 1600, 1800])!;

    expect(survey.medianMntPerKm, 1500);
    expect(survey.sampleSize, 5);
    expect(survey.lowMntPerKm, 1200);
    expect(survey.highMntPerKm, 1800);
  });

  test('an even count averages the two middles', () {
    final survey = summariseTariffs([1000, 1400, 1600, 2000, 2200, 2400])!;
    expect(survey.medianMntPerKm, 1800);
  });

  test('a fat-fingered rate does not drag the survey', () {
    // A driver who typed 150000 instead of 1500 publishes a real event
    // that any client can read. The median resists it; trimming keeps the
    // reported *range* from being nonsense too.
    final survey = summariseTariffs([
      1400,
      1500,
      1500,
      1600,
      1700,
      150000,
    ])!;

    expect(survey.medianMntPerKm, closeTo(1500, 100));
    expect(survey.highMntPerKm, lessThan(3000));
    expect(survey.sampleSize, 5);
  });

  test('a rate of zero or less is not a price', () {
    // Nothing validates these at the source: they come off the open
    // network, published by any client anyone cares to write.
    final survey = summariseTariffs([0, -100, 1400, 1500, 1600, 1700, 1800])!;
    expect(survey.sampleSize, 5);
    expect(survey.lowMntPerKm, 1400);
  });

  test('trimming that leaves too few reports nothing rather than a rump', () {
    // Five wildly scattered figures are not a market. Answering with the
    // two that happen to sit together would be the worst of both.
    expect(summariseTariffs([1, 10, 1500, 90000, 900000]), isNull);
  });
}
