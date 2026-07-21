// SPDX-License-Identifier: AGPL-3.0-or-later

/// A single GPS reading: coordinates plus the device clock time it was
/// captured, in unix seconds (matching `NostrEvent.createdAt`'s unit, so a
/// fix's timestamp compares directly against event timestamps elsewhere).
class GpsFix {
  final double lat;
  final double lon;
  final int timestampSeconds;
  const GpsFix({
    required this.lat,
    required this.lon,
    required this.timestampSeconds,
  });
}
