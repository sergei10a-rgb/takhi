// SPDX-License-Identifier: AGPL-3.0-or-later

/// Metres as the kilometre figure a screen shows: `8317` -> `8.3`.
///
/// Parsed back out of the fixed-point string rather than left as a raw
/// division, so the value handed to `meterRunningDistanceLabel` is already
/// the number the reader will see. A bare `meters / 1000` would arrive at
/// the localisation layer as 8.317 and be rounded there, which means the
/// rounding rule would live wherever the string happened to be formatted --
/// and the same trip could read 8.3 км on the running meter and 8.32 км in
/// the journal.
///
/// One decimal is the honest precision: a phone GPS track is not accurate to
/// ten metres, and a driver comparing two runs reads the tenth, not the
/// metre.
double displayKm(int meters) =>
    double.parse((meters / 1000).toStringAsFixed(1));

/// Seconds as a clock a passenger can check the money against: `34` -> `0:34`.
///
/// Written because of a receipt line that read «Хүлээлгийн хөлс 85 ₮» above
/// «Хүлээсэн хугацаа 0 мин». Both figures were correct — 34 seconds at
/// 150₮/мин is 85₮, and 34 seconds floors to zero whole minutes — and read
/// together they said the meter had charged for nothing. At the moment
/// money changes hands that is the worst thing a screen can say.
///
/// The fix is not to round the money up to a started minute: a total that
/// leaps by a whole minute's charge while the passenger watches reads as
/// the meter cheating, whatever the arithmetic. It is to show the time at
/// the precision the money is actually using.
String displayClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final rest = (safe % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
