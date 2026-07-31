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
