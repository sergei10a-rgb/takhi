// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/map/nearby_requests_layer.dart';
import 'package:takhi/ride/driver_inbox_service.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  testWidgets('renders one marker per listing and reports taps', (
    tester,
  ) async {
    final kp = generateKeyPair(List<int>.filled(32, 95));
    final unsigned = buildRideRequest(
      pubkey: kp.publicHex,
      now: 1000,
      pickupLat: 47.9186,
      pickupLon: 106.9176,
      destLat: 47.91,
      destLon: 106.90,
    );
    final event = signEvent(
      unsigned,
      kp.privateHex,
      auxRand: List<int>.filled(32, 0),
    );
    final listing = RideRequestListing(event, parseRideRequest(event));

    RideRequestListing? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          options: const MapOptions(
            initialCenter: ll.LatLng(47.9186, 106.9176),
          ),
          children: [
            NearbyRequestsLayer(listings: [listing], onTap: (l) => tapped = l),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_pin_circle));
    expect(tapped, listing);
  });
}
