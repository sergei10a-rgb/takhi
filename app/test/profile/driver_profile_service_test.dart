// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/profile/driver_profile_service.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  test(
    'publishAndSave publishes a signed kind-0 event and saves it locally',
    () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final store = InMemoryDriverProfileStore();
      final service = DriverProfileService(pool, store);
      final kp = generateKeyPair(List<int>.filled(32, 7));

      await service.publishAndSave(
        privHex: kp.privateHex,
        now: 1000,
        familyName: 'Б.',
        givenName: 'Бат',
        car: 'Prius 20',
        color: 'цагаан',
        plate: '1234УНА',
        kmTariffMnt: 1500,
      );

      expect(
        sockets['wss://a']!.sent.any(
          (s) => s.contains('"EVENT"') && s.contains('"kind":0'),
        ),
        isTrue,
      );
      final saved = await store.load();
      expect(saved!.fullName, 'Б. Бат');
      expect(saved.kmTariffMnt, 1500);
    },
  );

  // The asymmetry is the whole design: the vehicle half is published, the
  // name half is not. A kind-0 is world-readable and replicated forever, so
  // a name on it is a name anyone can harvest against a pubkey that also
  // carries this driver's plate and, while they work, a live geohash.
  test('publishAndSave sends the car to the relay and keeps the name on the '
      'phone', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool([
      'wss://a',
    ], connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final service = DriverProfileService(pool, InMemoryDriverProfileStore());

    await service.publishAndSave(
      privHex: generateKeyPair(List<int>.filled(32, 7)).privateHex,
      now: 1000,
      familyName: 'Дэлгэрмаа',
      givenName: 'Оюунчимэг',
      car: 'Prius 20',
      color: 'цагаан',
      plate: '1234УНА',
      kmTariffMnt: 1500,
    );

    final published = sockets['wss://a']!.sent
        .where((s) => s.contains('"EVENT"'))
        .join('\n');
    expect(published, contains('Prius 20'));
    expect(published, contains('1234'));
    expect(
      published,
      isNot(contains('Дэлгэрмаа')),
      reason: 'the family name reached a relay',
    );
    expect(
      published,
      isNot(contains('Оюунчимэг')),
      reason: 'the given name reached a relay',
    );
  });

  test('loadLocalProfile reads whatever the store holds', () async {
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();
    final service = DriverProfileService(pool, store);
    expect(await service.loadLocalProfile(), isNull);
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
    final loaded = await service.loadLocalProfile();
    expect(loaded!.fullName, 'Ц. Сараа');
  });

  // Field-test bug (2026-08, Эрдэнэхүү): a driver who restored from their
  // 12-word seed on a fresh install found their registration blank. The
  // profile lives in device-local storage keyed to the install, not to the
  // seed (`SharedPreferencesDriverProfileStore`), so a new phone has none.
  // But the vehicle-and-tariff half was published to the relays as a kind-0
  // event under this driver's own pubkey, so it can be fetched back and the
  // form prefilled. The name half stays gone -- it was never published
  // (privacy), and comes back only when the driver retypes it.
  group('fetchPublishedProfile (relay re-fetch on restore)', () {
    // subscribe() sends its REQ synchronously, so by the time
    // fetchPublishedProfile() has handed back its Future the REQ is already
    // in `sent`; this reads the id back so the test can answer the right
    // subscription rather than hard-coding `takhi-0`.
    String reqSubId(FakeRelaySocket socket) {
      for (final raw in socket.sent.reversed) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        if (decoded[0] == 'REQ') return decoded[1] as String;
      }
      throw StateError('no REQ frame sent');
    }

    NostrEvent signedProfile(
      List<int> seed, {
      required int now,
      required String car,
      required String color,
      required String plate,
      required int kmTariffMnt,
    }) {
      final keys = generateKeyPair(seed);
      return signEvent(
        buildDriverProfile(
          pubkey: keys.publicHex,
          now: now,
          car: car,
          color: color,
          plate: plate,
          kmTariffMnt: kmTariffMnt,
        ),
        keys.privateHex,
      );
    }

    test('returns the driver own published car and tariff, with names left '
        'null', () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = DriverProfileService(pool, InMemoryDriverProfileStore());
      final keys = generateKeyPair(List<int>.filled(32, 7));

      final future = service.fetchPublishedProfile(
        keys.publicHex,
        timeout: const Duration(milliseconds: 80),
      );
      sockets['wss://a']!.emit(
        jsonEncode([
          'EVENT',
          reqSubId(sockets['wss://a']!),
          signedProfile(
            List<int>.filled(32, 7),
            now: 1000,
            car: 'Prius 30',
            color: 'цагаан',
            plate: '1234УНА',
            kmTariffMnt: 2500,
          ).toJson(),
        ]),
      );

      final profile = await future;
      expect(profile, isNotNull);
      expect(profile!.car, 'Prius 30');
      expect(profile.color, 'цагаан');
      expect(profile.plate, '1234УНА');
      expect(profile.kmTariffMnt, 2500);
      // The name was never on the relay, so it cannot come back this way.
      expect(profile.familyName, isNull);
      expect(profile.givenName, isNull);
    });

    test('returns null when the window closes with nothing', () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = DriverProfileService(pool, InMemoryDriverProfileStore());

      final profile = await service.fetchPublishedProfile(
        generateKeyPair(List<int>.filled(32, 7)).publicHex,
        timeout: const Duration(milliseconds: 30),
      );
      expect(profile, isNull);
    });

    test('returns null with no relay connected, and starts no timer', () async {
      final pool = RelayPool([], connect: (u) => FakeRelaySocket());
      await pool.connectAll();
      final service = DriverProfileService(pool, InMemoryDriverProfileStore());

      // A four-second default window must not fire here: with no relay there
      // is nothing to wait for, and a timer outliving the blank form it was
      // opened for is a leak on the phone and a hung `flutter test`.
      final profile = await service.fetchPublishedProfile(
        generateKeyPair(List<int>.filled(32, 7)).publicHex,
      );
      expect(profile, isNull);
    });

    test('ignores a kind-0 from another pubkey a misbehaving relay '
        'forwards', () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = DriverProfileService(pool, InMemoryDriverProfileStore());
      // The driver we are asking about.
      final mine = generateKeyPair(List<int>.filled(32, 7));

      final future = service.fetchPublishedProfile(
        mine.publicHex,
        timeout: const Duration(milliseconds: 60),
      );
      // A different driver's profile, forwarded despite our authors filter.
      sockets['wss://a']!.emit(
        jsonEncode([
          'EVENT',
          reqSubId(sockets['wss://a']!),
          signedProfile(
            List<int>.filled(32, 9),
            now: 1000,
            car: 'Someone Else',
            color: 'хар',
            plate: '9999ХХХ',
            kmTariffMnt: 9999,
          ).toJson(),
        ]),
      );

      expect(await future, isNull);
    });

    test('keeps the newest published version when several arrive', () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = DriverProfileService(pool, InMemoryDriverProfileStore());
      final seed = List<int>.filled(32, 7);
      final keys = generateKeyPair(seed);

      final future = service.fetchPublishedProfile(
        keys.publicHex,
        timeout: const Duration(milliseconds: 80),
      );
      final subId = reqSubId(sockets['wss://a']!);
      // The newer version arrives FIRST, the older one second: the result
      // must be chosen by created_at, not by which frame landed last.
      sockets['wss://a']!.emit(
        jsonEncode([
          'EVENT',
          subId,
          signedProfile(
            seed,
            now: 2000,
            car: 'New Sonata',
            color: 'цагаан',
            plate: '1234УНА',
            kmTariffMnt: 3000,
          ).toJson(),
        ]),
      );
      sockets['wss://a']!.emit(
        jsonEncode([
          'EVENT',
          subId,
          signedProfile(
            seed,
            now: 1000,
            car: 'Old Prius',
            color: 'цагаан',
            plate: '1234УНА',
            kmTariffMnt: 2500,
          ).toJson(),
        ]),
      );

      final profile = await future;
      expect(profile!.car, 'New Sonata');
      expect(profile.kmTariffMnt, 3000);
    });
  });
}
