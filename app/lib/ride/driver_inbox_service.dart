// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';

/// A public ride request as seen by a nearby driver: the parsed protocol
/// fields plus the raw event (its `id` is the ride request id offers and
/// handoffs reference) and a freshness check against the driver's clock.
class RideRequestListing {
  final NostrEvent event;
  final RideRequest request;
  const RideRequestListing(this.event, this.request);

  /// Always non-null: [RelayPool.subscribe] never dispatches an event
  /// with a null `id`.
  String get rideRequestId => event.id!;

  bool isExpired(int nowSeconds) => nowSeconds >= request.expiration;
}

/// Subscribes a driver to public ride requests near their own location
/// (spec §5 "geohash шошгоор", §7.1 step 2). A driver listens on their
/// own geohash-6 cell plus its 8 neighbors (via [geohashNeighbors]) so a
/// passenger just across a cell boundary is still visible.
class DriverInboxService {
  final RelayPool _pool;
  DriverInboxService(this._pool);

  /// [nowSeconds] is injected (rather than read from a wall clock inside
  /// this class) so expiry filtering is deterministic in tests; app call
  /// sites pass `() => DateTime.now().millisecondsSinceEpoch ~/ 1000`.
  Stream<RideRequestListing> nearbyRequests({
    required double driverLat,
    required double driverLon,
    required int Function() nowSeconds,
  }) {
    final myCell = geohashEncode(driverLat, driverLon, precision: 6);
    final cells = [myCell, ...geohashNeighbors(myCell)];
    final filter = RelayFilter(
      kinds: [kKindRideRequest],
      tagFilters: {'#g': cells},
    );
    return _pool
        .subscribe(filter)
        .map(_tryParse)
        .where((listing) =>
            listing != null && !listing.isExpired(nowSeconds()))
        .cast<RideRequestListing>();
  }

  static RideRequestListing? _tryParse(NostrEvent event) {
    try {
      return RideRequestListing(event, parseRideRequest(event));
    } on FormatException {
      return null;
    }
  }
}
