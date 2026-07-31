// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

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
      locationSettings: _settings(interval),
    ).map(
      (position) => GpsFix(
        lat: position.latitude,
        lon: position.longitude,
        timestampSeconds: position.timestamp.millisecondsSinceEpoch ~/ 1000,
        accuracyMeters: _reportedAccuracy(position.accuracy),
      ),
    );
  }
}

/// Platform-specific settings, so the cadence is something this app asked
/// for rather than whatever the OS felt like.
///
/// The old code passed a bare `LocationSettings`, which has no interval
/// knob at all -- the comment on [LocationSource.watch] even said the
/// interval was "only a hint". On Android that leaves the fused provider
/// free to batch fixes to save power, and the result on a real drive was a
/// map pin trailing well behind the car: the driver had already turned the
/// corner while the screen still showed them mid-block.
///
/// `AndroidSettings.intervalDuration` is the fastest rate the app is asking
/// for; the platform may still deliver more slowly when the signal is poor.
/// `distanceFilter: 0` is kept deliberately -- filtering by distance here
/// would silently suppress the fixes that prove a car is *stationary*, and
/// `classifyMovement` (`geo/gps_jitter.dart`) needs to see those to run the
/// waiting meter. Jitter is dealt with there, on the billing side, where it
/// can be reasoned about and tested; it must not be dealt with by throwing
/// readings away at the source.
LocationSettings _settings(Duration interval) {
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: interval,
      // The OS must not coalesce several seconds of movement into one
      // delayed delivery: a position that arrives late is a position that
      // was wrong for as long as it took to arrive.
      forceLocationManager: false,
    );
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      // Apple pauses updates on its own guess that the user has stopped
      // moving. For a taximeter that guess is a billing decision made by
      // the operating system, which is not somewhere it belongs.
      pauseLocationUpdatesAutomatically: false,
      activityType: ActivityType.automotiveNavigation,
    );
  }
  return LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0);
}

/// `Position.accuracy` as an accuracy the UI is allowed to draw, or `null`
/// when the platform did not actually measure one.
///
/// Geolocator reports `0.0` (and, on some Android builds, a negative value)
/// when accuracy is unknown -- both mean "no answer", and painting a
/// zero-radius ring around the dot would turn that into the strongest
/// possible precision claim, which is the exact inversion of the truth.
double? _reportedAccuracy(double accuracy) =>
    accuracy > 0 && accuracy.isFinite ? accuracy : null;

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
