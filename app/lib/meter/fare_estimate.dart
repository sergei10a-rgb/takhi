// SPDX-License-Identifier: AGPL-3.0-or-later
import '../geo/gps_track.dart';
import 'fare_calc.dart';
import 'routing_client.dart';

/// A pre-trip fare estimate (spec §7.4 step 2): the number, plus whether it
/// came from real routed distance ([isApproximate] false) or the offline
/// straight-line fallback ([isApproximate] true — UI must label it
/// "ойролцоогоор").
class FareEstimate {
  final int mnt;
  final bool isApproximate;
  const FareEstimate({required this.mnt, required this.isApproximate});
}

/// Tries [routingClient] first (bounded by [timeout]); falls back to the
/// offline straight-line × [urbanFactor] estimate on any failure — network
/// error, timeout, or the routing service returning no route. This IS the
/// online/offline branch spec §7.4 step 2 describes; there is no separate
/// "are we online" check first, because attempting the call and catching
/// its failure is the only reliable signal on a mobile network (a passed
/// connectivity check does not guarantee the follow-up request succeeds).
Future<FareEstimate> estimateTripFare({
  required RoutingClient routingClient,
  required int mntPerKm,
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
  double urbanFactor = 1.35,
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final routed = await routingClient
        .routeDistanceMeters(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
        )
        .timeout(timeout);
    if (routed != null) {
      return FareEstimate(
        mnt: computeFareMnt(mntPerKm: mntPerKm, distanceMeters: routed.round()),
        isApproximate: false,
      );
    }
  } on Exception {
    // Network error, timeout, or malformed response — fall through to the
    // offline estimate below.
  }
  final straightLine = haversineMeters(fromLat, fromLon, toLat, toLon);
  return FareEstimate(
    mnt: estimateFareMntOffline(
      mntPerKm: mntPerKm,
      straightLineDistanceMeters: straightLine,
    ),
    isApproximate: true,
  );
}
