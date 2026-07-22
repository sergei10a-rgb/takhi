// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:geolocator/geolocator.dart';

import 'gps_fix.dart';

/// Abstracts the device GPS behind a plain [Stream] so every consumer
/// (Task 3's live-location channel, Task 7's active-trip tracker, Task 8's
/// taximeter) is testable with a fake stream instead of a real device —
/// per the plan's Global Constraints, nothing outside this file talks to
/// `package:geolocator` directly.
abstract interface class LocationSource {
  /// Emits a new [GpsFix] as the device moves. [interval] documents the
  /// intended cadence (spec §6: every 5-10s) but is only a *hint* here —
  /// `package:geolocator`'s base `LocationSettings` has no direct interval
  /// knob; the platform-specific subclasses (`AndroidSettings.intervalDuration`,
  /// `AppleSettings`) can honor it once the resolved `geolocator` version's
  /// exact constructor is confirmed (see Self-Review open questions).
  Stream<GpsFix> watch({Duration interval = const Duration(seconds: 5)});
}

/// Real device GPS via `package:geolocator`. Requires
/// `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (AndroidManifest.xml,
/// Step 6 below) and a granted runtime permission — [watch] does not
/// request permission itself; callers must call [ensureLocationPermission]
/// first (Task 7/8 UI) before constructing/using this class.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Stream<GpsFix> watch({Duration interval = const Duration(seconds: 5)}) {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).map(
      (position) => GpsFix(
        lat: position.latitude,
        lon: position.longitude,
        timestampSeconds: position.timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }
}

/// Requests location permission if not already granted, returning whether
/// GPS is now usable. Every UI that starts a [GeolocatorLocationSource]
/// subscription (Task 7/8) must check this first and show a clear "location
/// needed" state instead if it returns `false`, rather than letting
/// `Geolocator.getPositionStream` throw.
Future<bool> ensureLocationPermission() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}
