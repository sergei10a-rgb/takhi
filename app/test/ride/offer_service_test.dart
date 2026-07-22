// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

void main() {
  final driver = generateKeyPair(List<int>.filled(32, 101));
  final passenger = generateKeyPair(List<int>.filled(32, 102));

  test(
    'sendOffer delivers a decoded RideOffer to the passenger inbox',
    () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final service = OfferService(RideDmChannel(pool));

      final got = <RideOffer>[];
      final sub = service
          .receiveOffers(passenger.publicHex, passenger.privateHex)
          .listen(got.add);
      final subId =
          (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
              as String;

      await service.sendOffer(
        driverPrivHex: driver.privateHex,
        passengerPubHex: passenger.publicHex,
        offer: const RideOfferPayload(
          rideRequestId: 'req1',
          priceMnt: 7000,
          etaMinutes: 6,
          vehicleDescription: 'ногоон Sonata',
        ),
        now: 1000,
      );
      final publishedFrame =
          jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
      sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(got.length, 1);
      expect(got.first.driverPubkey, driver.publicHex);
      expect(got.first.payload.priceMnt, 7000);
      expect(got.first.payload.vehicleDescription, 'ногоон Sonata');
      await sub.cancel();
    },
  );

  test(
    'receiveOffers ignores non-offer ride DMs on the same channel',
    () async {
      final sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      final dm = RideDmChannel(pool);
      final service = OfferService(dm);

      final got = <RideOffer>[];
      final sub = service
          .receiveOffers(passenger.publicHex, passenger.privateHex)
          .listen(got.add);
      final subId =
          (jsonDecode(sockets['wss://a']!.sent.first) as List<dynamic>)[1]
              as String;

      await dm.send(
        senderPrivHex: driver.privateHex,
        recipientPubHex: passenger.publicHex,
        payload: const RideCancelPayload(rideRequestId: 'req1'),
        now: 1000,
      );
      final publishedFrame =
          jsonDecode(sockets['wss://a']!.sent.last) as List<dynamic>;
      sockets['wss://a']!.emit(jsonEncode(['EVENT', subId, publishedFrame[1]]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(got, isEmpty);
      await sub.cancel();
    },
  );
}
