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

  /// Whether the platform reported this position as coming from a **mock
  /// location provider** rather than the real GPS hardware.
  ///
  /// Android exposes this as `Location.isFromMockProvider`; `geolocator`
  /// surfaces it on `Position.isMocked`. A driver running a "Fake GPS" app
  /// can otherwise feed the taximeter an invented route — a straight fast
  /// road where there was a slow curved one — and inflate the distance the
  /// passenger is billed for. The local meter has no server re-deriving the
  /// distance from an independent source, so this device-level flag is the
  /// one signal available to catch it, and it must not be dropped on the
  /// way in from the platform.
  ///
  /// `false`, not `null`, when unknown: the platforms that cannot answer
  /// (older Android, desktop) are the ones where mock injection is not the
  /// threat it is on a phone, so treating "did not say" as "not mocked" is
  /// the safe default rather than a claim.
  final bool isMocked;

  const GpsFix({
    required this.lat,
    required this.lon,
    required this.timestampSeconds,
    this.accuracyMeters,
    this.isMocked = false,
  });
}
