// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/device_location_layer.dart';
import 'package:takhi/map/trip_tracking_map.dart';
import 'package:takhi/theme/takhi_theme.dart';

/// Where the map opens before anything is known: the city centre.
const _cityCentre = ll.LatLng(47.9186, 106.9176);

/// Where the phone actually is. Far enough from the centre that a camera
/// which never moved cannot hold it -- roughly the distance the reported
/// bug was found at, two and a half kilometres out.
const _self = ll.LatLng(47.9411, 106.9444);

/// Where the other side of the trip is, further out again.
const _counterparty = ll.LatLng(47.9000, 106.8600);

/// Rebuilds the widget with new positions, exactly as a stream of GPS fixes
/// makes the real screen rebuild -- and returns the controller so the camera
/// can be read back.
Future<MapController> _pumpTracking(
  WidgetTester tester, {
  ll.LatLng? selfPosition,
  ll.LatLng? counterpartyPosition,
  double? selfAccuracyMeters,
  bool counterpartyIsDriver = true,
  MapController? reuse,
}) async {
  final controller = reuse ?? MapController();
  if (reuse == null) addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: takhiTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('mn'),
      home: Scaffold(
        body: TripTrackingMap(
          selfPosition: selfPosition,
          selfAccuracyMeters: selfAccuracyMeters,
          counterpartyPosition: counterpartyPosition,
          counterpartyIsDriver: counterpartyIsDriver,
          fallbackCenter: _cityCentre,
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

void main() {
  testWidgets('shows where THIS phone is, the moment the first fix lands', (
    tester,
  ) async {
    // The reported bug, in one assertion. The screen is built before any
    // fix exists (the map's `initialCenter` is therefore the city centre),
    // and the first fix arrives a second later -- which is the ordinary
    // case, not an edge one.
    final controller = await _pumpTracking(tester);
    expect(_markers(tester), isEmpty, reason: 'nothing is known yet');

    await _pumpTracking(tester, selfPosition: _self, reuse: controller);

    expect(_markers(tester).map((m) => m.point), contains(_self));
    expect(
      controller.camera.visibleBounds.contains(_self),
      isTrue,
      reason:
          'The rider is on the map but off the screen -- which is exactly '
          'what "I cannot tell where I am" looks like.',
    );
  });

  testWidgets('draws own position with the SAME mark every other map in this '
      'app uses', (tester) async {
    await _pumpTracking(tester, selfPosition: _self);

    // Not a bespoke glyph for this one screen. One fact, one shape,
    // everywhere -- otherwise the rider has to learn the map twice.
    expect(find.byType(DeviceLocationLayer), findsOneWidget);
  });

  testWidgets('draws the accuracy the fix reported, and nothing when it '
      'reported none', (tester) async {
    await _pumpTracking(tester, selfPosition: _self, selfAccuracyMeters: 40);
    final circles = tester
        .widgetList<CircleLayer>(find.byType(CircleLayer))
        .expand((layer) => layer.circles);
    expect(circles.single.radius, 40);

    await _pumpTracking(tester, selfPosition: _self);
    expect(
      find.byType(CircleLayer),
      findsNothing,
      reason:
          'A default radius would be a precision claim the phone never '
          'made.',
    );
  });

  testWidgets('keeps BOTH people in frame once the other side reports in', (
    tester,
  ) async {
    final controller = await _pumpTracking(tester, selfPosition: _self);
    await _pumpTracking(
      tester,
      selfPosition: _self,
      counterpartyPosition: _counterparty,
      reuse: controller,
    );

    final bounds = controller.camera.visibleBounds;
    expect(bounds.contains(_self), isTrue);
    expect(
      bounds.contains(_counterparty),
      isTrue,
      reason:
          '"Where is my driver" is the other question this screen exists '
          'to answer.',
    );
  });

  testWidgets('follows the phone as it moves', (tester) async {
    const later = ll.LatLng(47.8600, 106.7600);
    final controller = await _pumpTracking(tester, selfPosition: _self);
    await _pumpTracking(tester, selfPosition: later, reuse: controller);

    expect(
      controller.camera.visibleBounds.contains(later),
      isTrue,
      reason:
          'A camera fitted once and never again is the bug this widget was '
          'written to remove.',
    );
  });

  testWidgets('tells a driver from a passenger by SHAPE, not only by colour', (
    tester,
  ) async {
    // A car for the driver on their way, a person-pin for the passenger
    // standing at the kerb. Both in the same steppe green, so the colour
    // says "the other side of this ride" and the shape says which side --
    // two marks that differ only in hue are one mark at arm's length.
    final controller = await _pumpTracking(
      tester,
      selfPosition: _self,
      counterpartyPosition: _counterparty,
    );
    expect(find.byIcon(Icons.directions_car), findsOneWidget);
    expect(find.byIcon(Icons.person_pin_circle), findsNothing);

    // Same camera, same two points -- only which side of the trip the other
    // person is on changes, so any difference in what is drawn is the
    // glyph and nothing else.
    await _pumpTracking(
      tester,
      selfPosition: _self,
      counterpartyPosition: _counterparty,
      counterpartyIsDriver: false,
      reuse: controller,
    );
    expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsNothing);
  });

  testWidgets('draws nothing at all for a position that does not exist', (
    tester,
  ) async {
    await _pumpTracking(tester, counterpartyPosition: _counterparty);

    // Only the other side is marked. No stand-in dot at the city centre,
    // which a rider would read as "the app has found me".
    expect(_markers(tester), hasLength(1));
    expect(find.byType(DeviceLocationLayer), findsNothing);
  });
}
