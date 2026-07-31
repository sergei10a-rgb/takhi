// SPDX-License-Identifier: AGPL-3.0-or-later

/// A single GPS reading: coordinates plus the device clock time it was
/// captured, in unix seconds (matching `NostrEvent.createdAt`'s unit, so a
/// fix's timestamp compares directly against event timestamps elsewhere).
class GpsFix {
  final double lat;
  final double lon;
  final int timestampSeconds;

  /// The radius, in metres, the device claims the true position lies
  /// within. `null` when the platform did not say -- which is a real
  /// answer, not a missing one, and must never be silently replaced with a
  /// number.
  ///
  /// Carried because a coordinate on its own is a *claim of certainty*: a
  /// dot painted on a map at a fix taken indoors, off a cell tower, looks
  /// exactly as confident as one taken under open sky with eight
  /// satellites, and the two can be half a kilometre apart. The map layer
  /// draws this as a ring around the dot, so a rider deciding whether the
  /// app has actually found them can see how much room the answer has.
  final double? accuracyMeters;

  const GpsFix({
    required this.lat,
    required this.lon,
    required this.timestampSeconds,
    this.accuracyMeters,
  });
}
