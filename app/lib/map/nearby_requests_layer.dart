// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../ride/driver_inbox_service.dart';
import '../theme/takhi_theme.dart';

/// Draws each nearby ride request a driver is subscribed to at its
/// geohash-6 cell CENTER, never at a passenger's exact coordinates --
/// `DriverInboxService` never receives exact coordinates in the first
/// place (spec §6/§9 privacy tiering: public = geohash-6 only, the exact
/// point is DM-only after selection), so there is nothing more precise
/// this layer could plot even by mistake.
class NearbyRequestsLayer extends StatelessWidget {
  final List<RideRequestListing> listings;
  final ValueChanged<RideRequestListing> onTap;

  const NearbyRequestsLayer({
    super.key,
    required this.listings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => MarkerLayer(
    markers: listings.map((listing) {
      final center = geohashDecodeCenter(listing.request.pickupGeohash);
      return Marker(
        point: ll.LatLng(center.lat, center.lon),
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => onTap(listing),
          child: const Icon(
            Icons.person_pin_circle,
            color: TakhiColors.steppe,
            size: 36,
          ),
        ),
      );
    }).toList(),
  );
}
