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
        name: 'Бат',
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
      expect(saved!.name, 'Бат');
      expect(saved.kmTariffMnt, 1500);
    },
  );

  test('loadLocalProfile reads whatever the store holds', () async {
    final pool = RelayPool([], connect: (u) => FakeRelaySocket());
    final store = InMemoryDriverProfileStore();
    final service = DriverProfileService(pool, store);
    expect(await service.loadLocalProfile(), isNull);
    await store.save(
      const DriverProfile(
        name: 'Сараа',
        car: 'Sonata',
        color: 'улаан',
        plate: '4321ЭЖӨ',
        kmTariffMnt: 2200,
      ),
    );
    final loaded = await service.loadLocalProfile();
    expect(loaded!.name, 'Сараа');
  });
}
