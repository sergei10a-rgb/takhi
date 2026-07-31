// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/profile/driver_offer_eligibility.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_channel.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

/// A stand-in for a compressed portrait.
final String _photoBase64 = base64Encode(
  Uint8List.fromList(List<int>.filled(900, 0x42)),
);

/// An offer complete enough to actually be sent: a driver without a name
/// and a photo is refused by `OfferService.sendOffer` before it reaches a
/// relay, so every send test needs both.
RideOfferPayload _offer({
  String rideRequestId = 'req1',
  int priceMnt = 7000,
  int etaMinutes = 6,
  String vehicleDescription = 'ногоон Sonata',
  String? familyName = 'Б.',
  String? givenName = 'Батбаяр',
  String? photo,
}) => RideOfferPayload(
  rideRequestId: rideRequestId,
  priceMnt: priceMnt,
  etaMinutes: etaMinutes,
  vehicleDescription: vehicleDescription,
  driverFamilyName: familyName,
  driverGivenName: givenName,
  driverPhotoJpegBase64: photo ?? _photoBase64,
);

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
        offer: _offer(),
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

  // A passenger deciding whether to get into a stranger's car has almost
  // nothing to go on; a name and a face are what turn «npub1qz8…» into a
  // person they can greet at the window and compare to whoever pulls up.
  // The rule therefore lives at the door every offer goes through, not in a
  // greyed-out button -- a disabled button is bypassed by a modified
  // client, by the next code path somebody adds, and by any caller that
  // reaches the service directly.
  group('an incomplete driver cannot send an offer', () {
    late Map<String, FakeRelaySocket> sockets;
    late OfferService service;
    late int framesBefore;

    setUp(() async {
      sockets = <String, FakeRelaySocket>{};
      final pool = RelayPool([
        'wss://a',
      ], connect: (u) => sockets[u] = FakeRelaySocket());
      await pool.connectAll();
      service = OfferService(RideDmChannel(pool));
      framesBefore = sockets['wss://a']!.sent.length;
    });

    /// Sends [offer] and returns the block it was refused with -- failing
    /// if it was accepted. Also asserts the refusal happened *before* the
    /// network, which is the part that matters: a rejected offer that has
    /// already been published is not rejected.
    Future<DriverOfferBlock> refused(RideOfferPayload offer) async {
      await expectLater(
        service.sendOffer(
          driverPrivHex: driver.privateHex,
          passengerPubHex: passenger.publicHex,
          offer: offer,
          now: 1000,
        ),
        throwsA(isA<DriverOfferBlockedException>()),
      );
      expect(
        sockets['wss://a']!.sent.length,
        framesBefore,
        reason: 'the offer was published despite being refused',
      );
      try {
        await service.sendOffer(
          driverPrivHex: driver.privateHex,
          passengerPubHex: passenger.publicHex,
          offer: offer,
          now: 1000,
        );
      } on DriverOfferBlockedException catch (e) {
        return e.block;
      }
      fail('sendOffer accepted an incomplete offer');
    }

    test('with no name at all', () async {
      expect(
        await refused(_offer(familyName: null, givenName: null)),
        DriverOfferBlock.missingName,
      );
    });

    test('with only a given name -- half a name is not a name', () async {
      expect(
        await refused(_offer(familyName: null)),
        DriverOfferBlock.missingName,
      );
    });

    test('with only a family name', () async {
      expect(
        await refused(_offer(givenName: null)),
        DriverOfferBlock.missingName,
      );
    });

    test('with a blank name typed as spaces', () async {
      expect(
        await refused(_offer(givenName: '   ')),
        DriverOfferBlock.missingName,
      );
    });

    test('with no photo', () async {
      expect(await refused(_offer(photo: '')), DriverOfferBlock.missingPhoto);
    });

    test('with a photo that will not decode', () async {
      expect(
        await refused(_offer(photo: 'not!!base64')),
        DriverOfferBlock.missingPhoto,
      );
    });

    // The name is reported first when both are missing: it is the cheaper
    // of the two to fix, and a driver told "add a photo" who then discovers
    // they also need a name has been sent back twice.
    test('reports the name first when both are missing', () async {
      expect(
        await refused(_offer(familyName: null, givenName: null, photo: '')),
        DriverOfferBlock.missingName,
      );
    });

    test('a complete driver is let through', () async {
      await service.sendOffer(
        driverPrivHex: driver.privateHex,
        passengerPubHex: passenger.publicHex,
        offer: _offer(),
        now: 1000,
      );
      expect(sockets['wss://a']!.sent.length, greaterThan(framesBefore));
    });
  });
}
