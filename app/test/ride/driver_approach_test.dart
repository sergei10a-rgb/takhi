// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Watching the chosen driver drive over.
//
// The encrypted position channel and the tracking map both already existed
// -- neither side opened them until the trip was STARTED, which is a button
// pressed at the kerb. The minutes before that are the ones a waiting
// passenger actually wants to see, and they were blank.
//
// What these tests pin is the part that has a consequence outside the
// phone: the broadcast starts when the driver is awarded the job, stops the
// moment the booking ends, and nothing is drawn at a position nobody sent.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/map/trip_tracking_map.dart';
import 'package:takhi/theme/takhi_theme.dart';

/// The pickup the driver is heading for.
const _kPickup = ll.LatLng(47.9186, 106.9176);

/// Where the driver's last ping put them -- a few hundred metres away.
const _kDriverAt = ll.LatLng(47.9215, 106.9210);

Widget _harness({
  required ll.LatLng? counterpartyPosition,
  ll.LatLng? selfPosition,
}) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('mn'),
    theme: takhiTheme(Brightness.light),
    home: Scaffold(
      body: SizedBox(
        height: 300,
        child: TripTrackingMap(
          selfPosition: selfPosition,
          selfAccuracyMeters: selfPosition == null ? null : 12,
          counterpartyPosition: counterpartyPosition,
          counterpartyIsDriver: true,
          fallbackCenter: _kPickup,
        ),
      ),
    ),
  ),
);

void main() {
  group('the approach map', () {
    testWidgets('draws nothing for a driver who has sent no position yet', (
      tester,
    ) async {
      // The failure this prevents is not a crash, it is a lie: a car drawn
      // at the map's fallback centre would tell a passenger their driver
      // is standing on top of them.
      await tester.pumpWidget(_harness(counterpartyPosition: null));
      await tester.pumpAndSettle();

      final map = tester.widget<TripTrackingMap>(find.byType(TripTrackingMap));
      expect(map.counterpartyPosition, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws the car once a position arrives', (tester) async {
      await tester.pumpWidget(_harness(counterpartyPosition: _kDriverAt));
      await tester.pumpAndSettle();

      final map = tester.widget<TripTrackingMap>(find.byType(TripTrackingMap));
      expect(map.counterpartyPosition, _kDriverAt);
      expect(map.counterpartyIsDriver, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows both ends once the passenger has a fix too', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(counterpartyPosition: _kDriverAt, selfPosition: _kPickup),
      );
      await tester.pumpAndSettle();

      final map = tester.widget<TripTrackingMap>(find.byType(TripTrackingMap));
      expect(map.selfPosition, _kPickup);
      expect(map.counterpartyPosition, _kDriverAt);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a driver position that arrives BEFORE the passenger has '
        'their own fix is still drawn', (tester) async {
      // The passenger's own GPS can be the slower of the two -- they may
      // have been indoors when they booked. Waiting for both would blank
      // the screen for the person who is waiting.
      await tester.pumpWidget(
        _harness(counterpartyPosition: _kDriverAt, selfPosition: null),
      );
      await tester.pumpAndSettle();

      final map = tester.widget<TripTrackingMap>(find.byType(TripTrackingMap));
      expect(map.selfPosition, isNull);
      expect(map.counterpartyPosition, _kDriverAt);
    });
  });
}
