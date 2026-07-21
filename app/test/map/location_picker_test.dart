// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/location_picker.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
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
