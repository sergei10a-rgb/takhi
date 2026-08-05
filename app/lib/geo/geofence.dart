// SPDX-License-Identifier: AGPL-3.0-or-later
import 'gps_fix.dart';
import 'gps_track.dart';

/// How close, in metres, the driver's position must be to the agreed pickup
/// point before the taximeter is allowed to start.
///
/// A meter that can be started anywhere lets a distance be run up before the
/// passenger is ever in the car — the one overcharge a local, server-less
/// meter cannot otherwise catch, because there is nobody re-deriving the
/// trip from an independent source. Gating the start on the driver actually
/// being at the pickup closes that: the fare can only begin once the two
/// people are in the same place.
///
/// 60m rather than something tighter because a phone's fix under a windscreen
/// on a built-up street is routinely 20-40m out (see `kGpsNoiseFloorMeters`
/// and the accuracy-scaled floor in `gps_jitter.dart`), and a gate narrower
/// than the fix error would refuse a driver who is genuinely there. The cost
/// of the looser radius lands on the passenger's side by at most that
/// distance's worth of fare, which is the direction this app resolves doubt.
const double kPickupArrivalRadiusMeters = 60.0;

/// Whether [fix] lies within [radiusMeters] of the point ([lat], [lon]).
///
/// Pure great-circle geometry, no device or clock, so a pickup gate built on
/// it is testable without hardware — which matters because getting it wrong
/// either strands a driver who is present or lets a meter start on a driver
/// who is not.
bool isWithinRadius(GpsFix fix, double lat, double lon, double radiusMeters) =>
    haversineMeters(fix.lat, fix.lon, lat, lon) <= radiusMeters;

/// Whether the driver at [fix] has reached the pickup at
/// ([pickupLat], [pickupLon]) closely enough to start the meter.
///
/// A mocked fix never satisfies the gate: a driver feeding a fake position in
/// could otherwise "arrive" without moving, which is exactly the fraud the
/// gate exists to stop. The passenger's own device applies the same check
/// independently, so neither side has to trust the other's word for it.
bool hasReachedPickup(
  GpsFix fix,
  double pickupLat,
  double pickupLon, {
  double radiusMeters = kPickupArrivalRadiusMeters,
}) => !fix.isMocked && isWithinRadius(fix, pickupLat, pickupLon, radiusMeters);
