// SPDX-License-Identifier: AGPL-3.0-or-later
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
}
