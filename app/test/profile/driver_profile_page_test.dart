// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/profile/driver_profile_page.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi/profile/profile_providers.dart';
import 'package:takhi/widgets/primary_button.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

Widget _harness({
  required KeyStore keyStore,
  required RelayPool pool,
  required DriverProfileStore store,
}) => ProviderScope(
  overrides: [
    keyStoreProvider.overrideWithValue(keyStore),
    relayPoolProvider.overrideWithValue(pool),
    driverProfileStoreProvider.overrideWithValue(store),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('mn'),
    home: const DriverProfilePage(),
  ),
);

/// Mirrors `SettingsPage`'s real navigation shape (a button/tile pushes
/// `DriverProfilePage` via `Navigator.push`), so `Navigator.pop()` inside
/// `_save()` has a route to pop back to -- the same reasoning as
/// `driver_qr_capture_page_test.dart`'s `pumpPushed`.
Future<void> _pumpPushed(
  WidgetTester tester, {
  required KeyStore keyStore,
  required RelayPool pool,
  required DriverProfileStore store,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyStoreProvider.overrideWithValue(keyStore),
        relayPoolProvider.overrideWithValue(pool),
        driverProfileStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DriverProfilePage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The one line under the save button, or null while the form is complete
/// and there is nothing holding the button grey.
String? _saveBlockedHint(WidgetTester tester) {
  final finder = find.byKey(const Key('driverProfileSaveBlockedHint'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

/// Whether «Хадгалах» would do anything if it were tapped.
///
/// Read off [PrimaryButton.onPressed] rather than by tapping: a tap on a
/// disabled button silently does nothing, which is indistinguishable from a
/// tap on a live button whose save failed.
bool _canSave(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed != null;

void main() {
  testWidgets('fills in the form, saves, publishes a kind-0 event and pops', (
    tester,
  ) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final store = InMemoryDriverProfileStore();

    await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

    await tester.enterText(
      find.byKey(const Key('driverProfileFamilyNameField')),
      'Б.',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileNameField')),
      'Бат',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileCarField')),
      'Prius 20',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileColorField')),
      'цагаан',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfilePlateField')),
      '1234УНА',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileKmTariffField')),
      '1500',
    );
    // The last field's `onChanged`-triggered rebuild (which is what
    // flips the save button from disabled to enabled) is only flushed
    // by the *next* pump -- without this, `tap()` below would hit a
    // still-disabled button from the previous frame and silently no-op.
    await tester.pump();
    await tester.tap(find.text('Хадгалах'));
    await tester.pumpAndSettle();

    expect(
      sockets['wss://a']!.sent.any(
        (s) => s.contains('"EVENT"') && s.contains('"kind":0'),
      ),
      isTrue,
    );
    final saved = await store.load();
    expect(saved!.fullName, 'Б. Бат');
    expect(saved.kmTariffMnt, 1500);
  });

  testWidgets(
    'back is deliberately unguarded: the arrow is there, and unsaved edits '
    'are dropped without a confirmation, publishing nothing',
    (tester) async {
      final keyStore = InMemoryKeyStore();
      await IdentityService(keyStore).createNew();
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final store = InMemoryDriverProfileStore();

      await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

      expect(find.byType(BackButton), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Бат',
      );
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Re-typing a form is the whole cost of leaving here -- no trip, no
      // meter, no published event -- so this page is left poppable.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DriverProfilePage), findsNothing);
      expect(await store.load(), isNull);
      expect(sockets['wss://a']!.sent, isEmpty);
    },
  );

  testWidgets(
    'a waiting tariff typed beside the km-tariff is cached and published with '
    'the rest of the profile (spec §7.4)',
    (tester) async {
      final keyStore = InMemoryKeyStore();
      await IdentityService(keyStore).createNew();
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final store = InMemoryDriverProfileStore();

      await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

      await tester.enterText(
        find.byKey(const Key('driverProfileFamilyNameField')),
        'Б.',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Бат',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileCarField')),
        'Prius 20',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileColorField')),
        'цагаан',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfilePlateField')),
        '1234УНА',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileKmTariffField')),
        '1500',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileWaitTariffField')),
        '300',
      );
      await tester.pump();
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved!.kmTariffMnt, 1500);
      expect(saved.waitTariffMntPerMinute, 300);
      // The published kind-0 carries it too, otherwise a passenger reading
      // the profile off a relay would see only half this driver's price.
      final profileEvent = NostrEvent.fromJson(
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kind":0'),
                  ),
                )
                as List<dynamic>)[1]
            as Map<String, dynamic>,
      );
      expect(parseDriverProfile(profileEvent).waitTariffMntPerMinute, 300);
    },
  );

  testWidgets(
    'the waiting tariff may be left blank -- the profile still saves, and '
    'waiting simply costs nothing',
    (tester) async {
      final keyStore = InMemoryKeyStore();
      await IdentityService(keyStore).createNew();
      final pool = RelayPool([], connect: (u) => FakeRelaySocket());
      final store = InMemoryDriverProfileStore();

      await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

      await tester.enterText(
        find.byKey(const Key('driverProfileFamilyNameField')),
        'Ц.',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Сараа',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileCarField')),
        'Sonata',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileColorField')),
        'улаан',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfilePlateField')),
        '4321ЭЖӨ',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileKmTariffField')),
        '2200',
      );
      await tester.pump();

      // Untouched waiting field: the save button must not be gated on it.
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved!.kmTariffMnt, 2200);
      expect(saved.waitTariffMntPerMinute, 0);
    },
  );

  testWidgets('pre-fills the form from an existing saved profile', (
    tester,
  ) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();
    await store.save(
      const DriverProfile(
        familyName: 'Ц.',
        givenName: 'Сараа',
        car: 'Sonata',
        color: 'улаан',
        plate: '4321ЭЖӨ',
        kmTariffMnt: 2200,
      ),
    );

    await tester.pumpWidget(
      _harness(keyStore: keyStore, pool: pool, store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('Сараа'), findsOneWidget);
    expect(find.text('Sonata'), findsOneWidget);
    expect(find.text('2200'), findsOneWidget);
  });

  testWidgets('pre-fills the saved waiting tariff too, so editing one rate '
      'never silently clears the other', (tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();
    await store.save(
      const DriverProfile(
        familyName: 'Д.',
        givenName: 'Дорж',
        car: 'Prius 30',
        color: 'хар',
        plate: '9999БАН',
        kmTariffMnt: 1800,
        waitTariffMntPerMinute: 250,
      ),
    );

    await tester.pumpWidget(
      _harness(keyStore: keyStore, pool: pool, store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('1800'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
  });

  testWidgets(
    'all three rates typed together are cached and published together -- the '
    'stopped-time and trip-duration rates overlap by design and nothing on '
    'this form argues with the driver about it',
    (tester) async {
      final keyStore = InMemoryKeyStore();
      await IdentityService(keyStore).createNew();
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final store = InMemoryDriverProfileStore();

      await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

      await tester.enterText(
        find.byKey(const Key('driverProfileFamilyNameField')),
        'Б.',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Бат',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileCarField')),
        'Prius 20',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileColorField')),
        'цагаан',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfilePlateField')),
        '1234УНА',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileKmTariffField')),
        '1500',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileWaitTariffField')),
        '300',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileDurationTariffField')),
        '200',
      );
      await tester.pump();

      // Both per-minute rates are filled at once on purpose. Every stopped
      // second is also a second of the trip's duration, so a driver who sets
      // both is charging stopped time twice -- and that is their call to
      // make, not this form's. If a validator, a warning or a "did you mean
      // moving time?" ever appears, this save stops being possible and this
      // test is what says so.
      expect(_canSave(tester), isTrue);
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved!.kmTariffMnt, 1500);
      expect(saved.waitTariffMntPerMinute, 300);
      expect(saved.durationTariffMntPerMinute, 200);

      // And the relay copy carries all three, otherwise a passenger reading
      // this profile would price the trip on two thirds of it.
      final profileEvent = NostrEvent.fromJson(
        (jsonDecode(
                  sockets['wss://a']!.sent.firstWhere(
                    (s) => s.contains('"kind":0'),
                  ),
                )
                as List<dynamic>)[1]
            as Map<String, dynamic>,
      );
      final published = parseDriverProfile(profileEvent);
      expect(published.waitTariffMntPerMinute, 300);
      expect(published.durationTariffMntPerMinute, 200);
    },
  );

  testWidgets(
    'the trip-duration tariff may be left blank -- the profile still saves, '
    'and the trip\'s duration simply costs nothing',
    (tester) async {
      final keyStore = InMemoryKeyStore();
      await IdentityService(keyStore).createNew();
      final pool = RelayPool([], connect: (u) => FakeRelaySocket());
      final store = InMemoryDriverProfileStore();

      await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

      await tester.enterText(
        find.byKey(const Key('driverProfileFamilyNameField')),
        'Ц.',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Сараа',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileCarField')),
        'Sonata',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileColorField')),
        'улаан',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfilePlateField')),
        '4321ЭЖӨ',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileKmTariffField')),
        '2200',
      );
      await tester.pump();

      // Untouched duration field, and no line under the button naming it:
      // the save must not be gated on a rate whose blank means "free".
      expect(_saveBlockedHint(tester), isNull);
      expect(_canSave(tester), isTrue);
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved!.kmTariffMnt, 2200);
      expect(saved.durationTariffMntPerMinute, 0);
    },
  );

  testWidgets('pre-fills the saved trip-duration tariff too, so opening the '
      'form and saving it again never silently drops a rate', (tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();
    await store.save(
      const DriverProfile(
        familyName: 'Д.',
        givenName: 'Дорж',
        car: 'Prius 30',
        color: 'хар',
        plate: '9999БАН',
        kmTariffMnt: 1800,
        waitTariffMntPerMinute: 250,
        durationTariffMntPerMinute: 120,
      ),
    );

    await tester.pumpWidget(
      _harness(keyStore: keyStore, pool: pool, store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('1800'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
  });

  // The grey «Хадгалах» button used to be the app's most expensive silence:
  // a driver filled in their name, added a photo, tapped a button that did
  // not answer, and left -- and nothing had been saved, because the car,
  // the colour, the plate and the km-tariff were still empty and the button
  // never said so. These four cases pin the line that now says it.

  testWidgets('an untouched form names every box that is keeping «Хадгалах» '
      'grey, rather than leaving a dead button unexplained', (tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();

    await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

    expect(_canSave(tester), isFalse);
    final hint = _saveBlockedHint(tester);
    // Every required box, by the same words standing above it on the page.
    expect(hint, contains('Овог'));
    expect(hint, contains('Нэр'));
    expect(hint, contains('Машины загвар'));
    expect(hint, contains('Өнгө'));
    expect(hint, contains('Улсын дугаар'));
    expect(hint, contains('Км-тариф'));
    // The two optional rates are not on the list. Naming a box the button
    // is not waiting for would send a driver to fill in a price they had
    // deliberately left free.
    expect(hint, isNot(contains('Түгжрэл')));
    expect(hint, isNot(contains('Аяллын хугацаа')));
  });

  testWidgets('the line names only what is still missing, and disappears '
      'together with the last empty box', (tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();

    await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

    await tester.enterText(
      find.byKey(const Key('driverProfileFamilyNameField')),
      'Б.',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileNameField')),
      'Бат',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileCarField')),
      'Prius 20',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileColorField')),
      'цагаан',
    );
    await tester.pump();

    final partial = _saveBlockedHint(tester);
    expect(partial, contains('Улсын дугаар'));
    expect(partial, contains('Км-тариф'));
    // Answered boxes drop off. A list that keeps naming what is already
    // filled in is a list nobody reads twice.
    expect(partial, isNot(contains('Овог')));
    expect(partial, isNot(contains('Машины загвар')));
    expect(partial, isNot(contains('Өнгө')));
    expect(_canSave(tester), isFalse);

    await tester.enterText(
      find.byKey(const Key('driverProfilePlateField')),
      '1234УНА',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileKmTariffField')),
      '1500',
    );
    await tester.pump();

    // The line and the button answer the same question, so they turn over
    // in the same frame.
    expect(_saveBlockedHint(tester), isNull);
    expect(_canSave(tester), isTrue);
  });

  testWidgets('a name the offer rule refuses keeps the button grey and is '
      'named in the line -- a form that looks full and will not save is the '
      'worst version of this bug', (tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();

    await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

    await tester.enterText(
      find.byKey(const Key('driverProfileFamilyNameField')),
      'Б.',
    );
    // Digits are not a usable name part, so `driverOfferBlock` -- and with
    // it the save button -- refuses it even though the box is not empty.
    await tester.enterText(
      find.byKey(const Key('driverProfileNameField')),
      'Бат1',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileCarField')),
      'Prius 20',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileColorField')),
      'цагаан',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfilePlateField')),
      '1234УНА',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileKmTariffField')),
      '1500',
    );
    await tester.pump();

    expect(_canSave(tester), isFalse);
    final hint = _saveBlockedHint(tester);
    expect(hint, isNotNull);
    expect(hint, contains('Нэр'));
    expect(hint, isNot(contains('Улсын дугаар')));
  });

  testWidgets('a km-tariff that is not a number counts as missing -- the '
      'button is grey and the line says which box to look at', (tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();

    await _pumpPushed(tester, keyStore: keyStore, pool: pool, store: store);

    await tester.enterText(
      find.byKey(const Key('driverProfileFamilyNameField')),
      'Б.',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileNameField')),
      'Бат',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileCarField')),
      'Prius 20',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfileColorField')),
      'цагаан',
    );
    await tester.enterText(
      find.byKey(const Key('driverProfilePlateField')),
      '1234УНА',
    );
    // A number-keyboard field can still receive this from a paste or a
    // hardware keyboard, and `int.tryParse` is what `_save` would refuse.
    await tester.enterText(
      find.byKey(const Key('driverProfileKmTariffField')),
      '1 500 ₮',
    );
    await tester.pump();

    expect(_canSave(tester), isFalse);
    expect(_saveBlockedHint(tester), contains('Км-тариф'));
  });
}
