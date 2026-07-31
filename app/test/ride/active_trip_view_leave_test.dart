// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/geo_providers.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/ride/active_trip_view.dart';
import 'package:takhi/ride/trip_role.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_location_source.dart';
import '../support/fake_relay_socket.dart';

/// Mounts [ActiveTripView] on its own, the way its host pages do, with the
/// relay pool already connected -- `initState` starts subscribing as soon
/// as identity resolves, which can happen during `pumpWidget` itself.
Future<Map<String, FakeRelaySocket>> _pumpTrip(
  WidgetTester t, {
  required InMemoryKeyStore keyStore,
  required String counterpartyPubHex,
  required TripRole role,
  Future<bool> Function()? permissionCheck,
  VoidCallback? onTripSettled,
  VoidCallback? onFinished,
}) async {
  final sockets = <String, FakeRelaySocket>{};
  final pool = RelayPool([
    'wss://a',
  ], connect: (u) => sockets[u] = FakeRelaySocket());
  await pool.connectAll();

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(keyStore),
        relayPoolProvider.overrideWithValue(pool),
        locationSourceProvider.overrideWithValue(FakeLocationSource()),
        locationPermissionCheckProvider.overrideWithValue(
          permissionCheck ?? () async => true,
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: Scaffold(
          body: ActiveTripView(
            role: role,
            tripId: 'trip-leave',
            counterpartyPubHex: counterpartyPubHex,
            agreedPriceMnt: 5000,
            onTripSettled: onTripSettled,
            onFinished: onFinished,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return sockets;
}

/// Both driver phase buttons, then a rating -- the only path that actually
/// publishes this side's trip receipt and reaches the final screen.
Future<void> _driveToDoneStep(WidgetTester t) async {
  await t.tap(find.text('Зорчигч сууллаа'));
  await t.pumpAndSettle();
  await t.tap(find.text('Аялал дууслаа'));
  await t.pumpAndSettle();
  await t.tap(find.byIcon(Icons.star_border).at(4));
  await t.pumpAndSettle();
  await t.tap(find.text('Илгээх'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('onTripSettled fires only once the receipt is published, and '
      'onFinished is what the final screen\'s button calls', (t) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final passenger = generateKeyPair(List<int>.filled(32, 81));
    var settled = false, finished = false;

    await _pumpTrip(
      t,
      keyStore: keyStore,
      counterpartyPubHex: passenger.publicHex,
      role: TripRole.driver,
      onTripSettled: () => settled = true,
      onFinished: () => finished = true,
    );

    // Still tracking: nothing has been published, so the host must keep
    // its leave-confirmation guard up.
    expect(settled, isFalse);

    await _driveToDoneStep(t);

    expect(find.text('Баримт нийтлэгдлээ'), findsOneWidget);
    expect(settled, isTrue);
    expect(finished, isFalse);

    await t.tap(find.text('Аяллыг дуусгах'));
    await t.pumpAndSettle();

    expect(finished, isTrue);
  });

  testWidgets('a host that wires no onFinished simply gets no button -- the '
      'final screen never calls a null callback', (t) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final passenger = generateKeyPair(List<int>.filled(32, 82));

    await _pumpTrip(
      t,
      keyStore: keyStore,
      counterpartyPubHex: passenger.publicHex,
      role: TripRole.driver,
    );
    await _driveToDoneStep(t);

    expect(find.text('Баримт нийтлэгдлээ'), findsOneWidget);
    expect(find.text('Аяллыг дуусгах'), findsNothing);
  });

  testWidgets('retrying after a location-permission denial closes the '
      'subscriptions the first attempt opened instead of leaking them', (
    t,
  ) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final driver = generateKeyPair(List<int>.filled(32, 83));
    var granted = false;

    final sockets = await _pumpTrip(
      t,
      keyStore: keyStore,
      counterpartyPubHex: driver.publicHex,
      // Passenger: the side that opens *two* gift-wrap subscriptions
      // (trip status + voice notes) before the permission check.
      role: TripRole.passenger,
      permissionCheck: () async => granted,
    );
    final socket = sockets['wss://a']!;

    // `_startTracking`'s own two gift-wrap subscriptions are always the
    // first kind-1059 `REQ`s on the wire -- it wires them synchronously,
    // before any `await`, precisely so they beat `IncomingCallListener`'s
    // (see that method's ordering comment); the third id here is that
    // sibling widget's, which owns its own lifecycle.
    final firstAttemptSubIds = socket.sent
        .where((s) => s.contains('"kinds":[1059]'))
        .map((s) => (jsonDecode(s) as List<dynamic>)[1] as String)
        .take(2)
        .toList();
    for (final subId in firstAttemptSubIds) {
      expect(
        socket.sent.contains(jsonEncode(['CLOSE', subId])),
        isFalse,
        reason: 'the denied attempt still holds subscription $subId',
      );
    }

    granted = true;
    await t.tap(find.text('Зөвшөөрөл өгөх'));
    await t.pumpAndSettle();

    for (final subId in firstAttemptSubIds) {
      expect(
        socket.sent.contains(jsonEncode(['CLOSE', subId])),
        isTrue,
        reason: 'subscription $subId from the denied attempt was never closed',
      );
    }
  });
}
