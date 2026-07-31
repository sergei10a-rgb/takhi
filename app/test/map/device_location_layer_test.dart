// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/map/device_location_layer.dart';
import 'package:takhi/map/ride_map.dart';

const _here = ll.LatLng(47.9186, 106.9176);

/// Hosts [layer] inside a real map, which is the only place a flutter_map
/// layer can build: every one of them reads `MapCamera.of(context)`.
Future<void> _pumpOnMap(WidgetTester tester, Widget layer) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RideMap(initialCenter: _here, layers: [layer]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<CircleMarker> _circles(WidgetTester tester) => tester
    .widgetList<CircleLayer>(find.byType(CircleLayer))
    .expand((layer) => layer.circles)
    .toList();

List<Marker> _markers(WidgetTester tester) => tester
    .widgetList<MarkerLayer>(find.byType(MarkerLayer))
    .expand((layer) => layer.markers)
    .toList();

void main() {
  testWidgets('draws one mark standing exactly on the reported position', (
    tester,
  ) async {
    await _pumpOnMap(
      tester,
      const DeviceLocationLayer(position: _here, accuracyMeters: 20),
    );

    final markers = _markers(tester);
    expect(markers, hasLength(1));
    expect(markers.single.point, _here);
  });

  testWidgets('draws the accuracy radius as a circle measured in METRES, so '
      'it grows and shrinks with the zoom the way the ground does', (
    tester,
  ) async {
    await _pumpOnMap(
      tester,
      const DeviceLocationLayer(position: _here, accuracyMeters: 35),
    );

    final circles = _circles(tester);
    expect(circles, hasLength(1));
    expect(circles.single.point, _here);
    expect(circles.single.radius, 35);
    expect(
      circles.single.useRadiusInMeter,
      isTrue,
      reason:
          'A pixel radius would claim a different accuracy at every zoom '
          'level -- the whole point of drawing it is that it is a distance '
          'on the ground.',
    );
  });

  testWidgets('draws NO accuracy circle when the device did not report an '
      'accuracy', (tester) async {
    await _pumpOnMap(tester, const DeviceLocationLayer(position: _here));

    // Silence is honest; a default ring would be a precision claim the app
    // cannot back.
    expect(_circles(tester), isEmpty);
    // The dot itself still stands: knowing roughly where the phone is is
    // never worse than showing nothing.
    expect(_markers(tester), hasLength(1));
  });

  testWidgets('draws no accuracy circle for a non-positive accuracy either -- '
      'that is how the platform says "unknown"', (tester) async {
    await _pumpOnMap(
      tester,
      const DeviceLocationLayer(position: _here, accuracyMeters: 0),
    );

    expect(_circles(tester), isEmpty);
  });

  testWidgets('a rough fix draws a correspondingly large circle rather than '
      'the same ring a precise one draws', (tester) async {
    await _pumpOnMap(
      tester,
      const DeviceLocationLayer(position: _here, accuracyMeters: 400),
    );

    expect(_circles(tester).single.radius, 400);
  });
}
