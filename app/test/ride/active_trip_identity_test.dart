// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/identity/short_pubkey.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

Uint8List _portrait() =>
    img.encodeJpg(img.Image(width: 16, height: 16), quality: 60);

/// Mounts the passenger's side of a live trip, optionally knowing who the
/// driver is -- which is exactly what the selected offer carries and what
/// `PassengerRidePage` now threads in.
Future<KeyPair> _pumpTrip(
  WidgetTester tester, {
  String? counterpartyName,
  Uint8List? counterpartyPhotoJpeg,
}) async {
  final store = InMemoryKeyStore();
  await IdentityService(store).createNew();
  final driver = generateKeyPair(List<int>.filled(32, 71));

  final sockets = <String, FakeRelaySocket>{};
  final pool = RelayPool([
    'wss://a',
  ], connect: (u) => sockets[u] = FakeRelaySocket());
  await pool.connectAll();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(store),
        relayPoolProvider.overrideWithValue(pool),
        locationSourceProvider.overrideWithValue(FakeLocationSource()),
        locationPermissionCheckProvider.overrideWithValue(() async => true),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: Scaffold(
          body: ActiveTripView(
            role: TripRole.passenger,
            tripId: 'trip-1',
            counterpartyPubHex: driver.publicHex,
            agreedPriceMnt: 5000,
            counterpartyName: counterpartyName,
            counterpartyPhotoJpeg: counterpartyPhotoJpeg,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return driver;
}

void main() {
  testWidgets('the trip names the driver the rider chose, and shows their '
      'face', (tester) async {
    await _pumpTrip(
      tester,
      counterpartyName: 'Б. Батбаяр',
      counterpartyPhotoJpeg: _portrait(),
    );

    expect(find.text('Б. Батбаяр'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    // The word "Жолооч" was the whole of what this row could say before the
    // name arrived; with a real one it must not be shown instead.
    expect(find.text('Жолооч'), findsNothing);
  });

  testWidgets('the key stays under the name -- it is what a careful rider '
      'checks the offer against', (tester) async {
    final driver = await _pumpTrip(
      tester,
      counterpartyName: 'Б. Батбаяр',
      counterpartyPhotoJpeg: _portrait(),
    );

    expect(find.text(shortPubkeyLabel(driver.publicHex)!), findsOneWidget);
  });

  testWidgets('a trip with no name falls back to which side the other person '
      'is, exactly as before', (tester) async {
    await _pumpTrip(tester);

    expect(find.text('Жолооч'), findsOneWidget);
  });

  testWidgets('tapping the driver opens their face full screen', (
    tester,
  ) async {
    await _pumpTrip(
      tester,
      counterpartyName: 'Б. Батбаяр',
      counterpartyPhotoJpeg: _portrait(),
    );

    await tester.tap(find.text('Б. Батбаяр'));
    await tester.pumpAndSettle();

    expect(find.text('Баталгаажаагүй зураг'), findsOneWidget);
    expect(find.text('Хаах'), findsOneWidget);
  });

  testWidgets('a driver with no photo offers no enlargement', (tester) async {
    await _pumpTrip(tester, counterpartyName: 'Б. Батбаяр');

    await tester.tap(find.text('Б. Батбаяр'));
    await tester.pumpAndSettle();

    expect(find.text('Баталгаажаагүй зураг'), findsNothing);
  });
}
