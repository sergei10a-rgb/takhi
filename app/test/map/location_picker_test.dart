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
}
