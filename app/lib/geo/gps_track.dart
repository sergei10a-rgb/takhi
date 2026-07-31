// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'gps_fix.dart';

const double _earthRadiusMeters = 6371000;

/// Metres per second to kilometres per hour.
const double _metersPerSecondToKmh = 3.6;

/// Great-circle distance between two points, in meters (haversine). Pure
/// math, no Flutter/location dependency — the shared building block behind
/// both the active-trip tracker (Task 7) and the taximeter (Task 6).
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * c;
}

double _radians(double degrees) => degrees * math.pi / 180.0;

/// Average speed over the leg between two consecutive fixes, in km/h.
///
/// Derived from the two fixes rather than read off the device, even though
/// `package:geolocator`'s `Position` does report an instantaneous speed:
/// the taximeter decides *money* from this number, so it must be
/// reproducible from the recorded track alone. A fare computed from a
/// value the device reported once and never stored could never be
/// re-checked afterwards by either side of the trip.
///
/// Returns 0 when [to] does not strictly follow [from] in time — no elapsed
/// time means no measurable speed, and callers must treat that as a fix to
/// discard rather than as a stopped vehicle.
double segmentSpeedKmh(GpsFix from, GpsFix to) {
  final seconds = to.timestampSeconds - from.timestampSeconds;
  if (seconds <= 0) return 0;
  final meters = haversineMeters(from.lat, from.lon, to.lat, to.lon);
  return meters / seconds * _metersPerSecondToKmh;
}

/// Total path length across consecutive [fixes], rounded to whole meters.
/// Fewer than 2 fixes has no distance yet.
int trackDistanceMeters(List<GpsFix> fixes) {
  if (fixes.length < 2) return 0;
  var total = 0.0;
  for (var i = 1; i < fixes.length; i++) {
    total += haversineMeters(
      fixes[i - 1].lat,
      fixes[i - 1].lon,
      fixes[i].lat,
      fixes[i].lon,
    );
  }
  return total.round();
}

/// Elapsed time between the first and last [fixes], in seconds. Fewer than
/// 2 fixes has no duration yet.
int trackDurationSeconds(List<GpsFix> fixes) {
  if (fixes.length < 2) return 0;
  return fixes.last.timestampSeconds - fixes.first.timestampSeconds;
}

/// Mutable accumulator over a live sequence of [GpsFix]es — the shared
/// engine behind the active-trip distance tracker (`ride/`, Task 7) and
/// the taximeter (`meter/`, Task 6, via `MeterSession`), so the haversine-
/// sum logic lives in exactly one place (DRY). Intentionally mutable — see
/// Global Constraints' immutability note.
class GpsTrackAccumulator {
  final List<GpsFix> _fixes = [];

  void addFix(GpsFix fix) => _fixes.add(fix);

  List<GpsFix> get fixes => List.unmodifiable(_fixes);
  int get distanceMeters => trackDistanceMeters(_fixes);
  int get durationSeconds => trackDurationSeconds(_fixes);
}
