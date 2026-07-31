// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/location_picker.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  testWidgets(
    'panning the map under the center pin reports a new PickedLocation',
    (tester) async {
      const initialCenter = ll.LatLng(47.9186, 106.9176);
      final updates = <PickedLocation>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Scaffold(
            body: LocationPickerField(
              initialCenter: initialCenter,
              onChanged: updates.add,
            ),
          ),
        ),
      );

      // A real drag gesture on the map -- the same path a rider's thumb
      // takes when panning the map under the fixed center pin -- must
      // flow through RideMap.onPositionChanged (hasGesture: true) into
      // LocationPickerField's _emit() and out via onChanged.
      await tester.drag(find.byType(FlutterMap), const Offset(-120, -80));
      await tester.pumpAndSettle();

      expect(updates, isNotEmpty);
      final last = updates.last;
      expect(last.lat, isNot(initialCenter.latitude));
      expect(last.lon, isNot(initialCenter.longitude));
      expect(last.landmarkText, '');
      expect(last.plusCode, plusCodeEncode(last.lat, last.lon));
    },
  );

  testWidgets('typing a landmark reports a PickedLocation with a matching Plus '
      'Code', (tester) async {
    PickedLocation? last;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: Scaffold(
          body: LocationPickerField(
            initialCenter: const ll.LatLng(47.9186, 106.9176),
            onChanged: (p) => last = p,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Улаан хаалганы урд');
    await tester.pump();

    expect(last, isNotNull);
    expect(last!.landmarkText, 'Улаан хаалганы урд');
    expect(last!.lat, 47.9186);
    expect(last!.lon, 106.9176);
    expect(last!.plusCode, plusCodeEncode(47.9186, 106.9176));
  });

  group('a GPS fix arriving after the picker is already on screen', () {
    /// Hosts the picker with a centre the test can change afterwards, which
    /// is what a fix landing a second after the map opened actually does to
    /// it.
    Future<void Function(ll.LatLng)> pumpMovableCentre(
      WidgetTester tester, {
      required ll.LatLng initialCentre,
      required ValueChanged<PickedLocation> onChanged,
    }) async {
      late void Function(ll.LatLng) moveCentre;
      var centre = initialCentre;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                moveCentre = (next) => setState(() => centre = next);
                return LocationPickerField(
                  initialCenter: centre,
                  devicePosition: centre == initialCentre ? null : centre,
                  onChanged: onChanged,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return moveCentre;
    }

    testWidgets('recentres a map the rider has not touched, and reports the '
        'point it moved to', (tester) async {
      const cityCentre = ll.LatLng(47.9186, 106.9176);
      const fix = ll.LatLng(47.8720, 106.7500);
      PickedLocation? last;
      final moveCentre = await pumpMovableCentre(
        tester,
        initialCentre: cityCentre,
        onChanged: (p) => last = p,
      );

      moveCentre(fix);
      await tester.pumpAndSettle();

      expect(last, isNotNull);
      expect(last!.lat, fix.latitude);
      expect(last!.lon, fix.longitude);
    });

    testWidgets('never yanks a map the rider has already panned out from '
        'under them', (tester) async {
      const cityCentre = ll.LatLng(47.9186, 106.9176);
      const fix = ll.LatLng(47.8720, 106.7500);
      PickedLocation? last;
      final moveCentre = await pumpMovableCentre(
        tester,
        initialCentre: cityCentre,
        onChanged: (p) => last = p,
      );

      await tester.drag(find.byType(FlutterMap), const Offset(-140, -90));
      await tester.pumpAndSettle();
      final pannedTo = last;

      moveCentre(fix);
      await tester.pumpAndSettle();

      // The rider's own point survives: a fix that arrives late is a
      // suggestion about where they started, not an override of where they
      // said they are standing.
      expect(last!.lat, pannedTo!.lat);
      expect(last!.lon, pannedTo.lon);
      expect(last!.lat, isNot(fix.latitude));
    });

    testWidgets('draws the device position as a marker of its own, so it is '
        'still findable after a pan', (tester) async {
      const cityCentre = ll.LatLng(47.9186, 106.9176);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Scaffold(
            body: LocationPickerField(
              initialCenter: cityCentre,
              // A couple of streets away rather than across the valley:
              // flutter_map culls markers outside the viewport, and the
              // fact under test is that the marker is drawn at all.
              devicePosition: const ll.LatLng(47.9200, 106.9200),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('draws no device marker before any fix has arrived', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Scaffold(
            body: LocationPickerField(
              initialCenter: const ll.LatLng(47.9186, 106.9176),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A marker for a position the app does not have would be a claim it
      // cannot back -- the pin at the centre is not the rider.
      expect(find.byIcon(Icons.my_location), findsNothing);
    });
  });
}
