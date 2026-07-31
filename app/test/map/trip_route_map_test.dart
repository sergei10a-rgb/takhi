// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/trip_route_map.dart';
import 'package:takhi/map/trip_route_preview.dart';
import 'package:takhi/theme/takhi_theme.dart';

/// Far enough apart that a camera which never moved cannot possibly hold
/// both: the opening zoom shows a couple of streets, and these are opposite
/// ends of the city.
const _pickup = ll.LatLng(47.9186, 106.9176);
const _destination = ll.LatLng(47.8600, 106.7600);

const _routed = TripRoutePreview(
  points: [_pickup, ll.LatLng(47.8900, 106.8400), _destination],
  distanceMeters: 14000,
  durationSeconds: 1500,
  isApproximate: false,
);

const _approximate = TripRoutePreview(
  points: [_pickup, _destination],
  distanceMeters: 12000,
  isApproximate: true,
);

Future<MapController> _pumpMap(
  WidgetTester tester, {
  TripRoutePreview? preview,
  ll.LatLng? devicePosition,
  double? deviceAccuracyMeters,
}) async {
  final controller = MapController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: takhiTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('mn'),
      home: Scaffold(
        body: TripRouteMap(
          pickup: _pickup,
          destination: _destination,
          preview: preview,
          devicePosition: devicePosition,
          deviceAccuracyMeters: deviceAccuracyMeters,
          controller: controller,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

List<Marker> _markers(WidgetTester tester) => tester
    .widgetList<MarkerLayer>(find.byType(MarkerLayer))
    .expand((layer) => layer.markers)
    .toList();

List<Polyline> _polylines(WidgetTester tester) => tester
    .widgetList<PolylineLayer>(find.byType(PolylineLayer))
    .expand((layer) => layer.polylines)
    .toList();

void main() {
  testWidgets('marks BOTH ends of the trip, each at its own point', (
    tester,
  ) async {
    await _pumpMap(tester, preview: _routed);

    final points = _markers(tester).map((m) => m.point).toList();
    expect(points, contains(_pickup));
    expect(points, contains(_destination));
  });

  testWidgets('draws the two ends differently -- a rider must be able to tell '
      'where they get in from where they get out', (tester) async {
    await _pumpMap(tester, preview: _routed);

    final markers = _markers(tester);
    final pickup = markers.firstWhere((m) => m.point == _pickup);
    final destination = markers.firstWhere((m) => m.point == _destination);
    // Two marks that differ only in position are one mark drawn twice.
    expect(
      destination.child.runtimeType,
      isNot(pickup.child.runtimeType),
      reason: 'pickup and destination markers must be distinguishable',
    );
  });

  testWidgets('draws the route through every point the preview gave it', (
    tester,
  ) async {
    await _pumpMap(tester, preview: _routed);

    final lines = _polylines(tester);
    expect(lines, hasLength(1));
    expect(lines.single.points, _routed.points);
  });

  testWidgets('draws a BROKEN line when the route is only the straight-line '
      'guess, and a solid one when it is a real road', (tester) async {
    await _pumpMap(tester, preview: _approximate);
    final guessed = _polylines(tester).single.pattern;

    await _pumpMap(tester, preview: _routed);
    final real = _polylines(tester).single.pattern;

    expect(real, const StrokePattern.solid());
    expect(
      guessed,
      isNot(const StrokePattern.solid()),
      reason:
          'A solid line across the map is a claim about which streets the '
          'car will take. Offline, the app does not know that.',
    );
  });

  testWidgets('frames both ends of the trip, however far apart they are', (
    tester,
  ) async {
    final controller = await _pumpMap(tester, preview: _routed);

    final bounds = controller.camera.visibleBounds;
    expect(
      bounds.contains(_pickup),
      isTrue,
      reason: 'the pickup fell outside the camera after the fit',
    );
    expect(
      bounds.contains(_destination),
      isTrue,
      reason: 'the destination fell outside the camera after the fit',
    );
  });

  testWidgets('frames both ends even before any route has been fetched', (
    tester,
  ) async {
    // The routing call takes a second or two on a phone. Until it lands the
    // map still has to answer "where are these two places" -- otherwise the
    // screen opens on a random street and jumps a moment later.
    final controller = await _pumpMap(tester);

    final bounds = controller.camera.visibleBounds;
    expect(bounds.contains(_pickup), isTrue);
    expect(bounds.contains(_destination), isTrue);
  });

  testWidgets('shows where the rider is standing, with its accuracy, on top '
      'of the trip', (tester) async {
    const device = ll.LatLng(47.9190, 106.9180);
    await _pumpMap(
      tester,
      preview: _routed,
      devicePosition: device,
      deviceAccuracyMeters: 25,
    );

    expect(_markers(tester).map((m) => m.point), contains(device));
    final circles = tester
        .widgetList<CircleLayer>(find.byType(CircleLayer))
        .expand((layer) => layer.circles);
    expect(circles.single.radius, 25);
  });

  testWidgets('draws no own-position mark before a fix exists', (tester) async {
    await _pumpMap(tester, preview: _routed);

    // Exactly the two trip ends, and nothing standing in for a rider the
    // app cannot locate.
    expect(_markers(tester), hasLength(2));
  });
}
