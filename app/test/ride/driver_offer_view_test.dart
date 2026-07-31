// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/money_format.dart';
import 'package:takhi/ride/driver_offer_view.dart';
import 'package:takhi/ride/offer_ranking.dart';
import 'package:takhi/ride/offer_service.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/widgets/driver_portrait.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

/// A real, decodable JPEG standing in for a compressed portrait.
Uint8List _jpegBytes() =>
    img.encodeJpg(img.Image(width: 16, height: 16), quality: 60);

String _jpegBase64() => base64Encode(_jpegBytes());

/// A well-formed 64-hex pubkey, so `hexToNpub` produces a real npub the
/// abbreviation and the avatar mark can both be cut from.
const _driverPubHex =
    'b0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecf';

/// 2026-03-14, as the unix second a receipt would carry.
const _kMarch2026 = 1773446400;

RankedRideOffer _ranked({
  String? familyName = 'Б.',
  String? givenName = 'Батбаяр',
  String? photoBase64,
  int pairedTrips = 0,
  int distinctPeople = 0,
  double averageRating = 0,
  int? firstPairedAt,
  int? kmTariffMnt,
}) => RankedRideOffer(
  RideOffer(
    _driverPubHex,
    RideOfferPayload(
      rideRequestId: 'req-1',
      priceMnt: 9000,
      etaMinutes: 4,
      vehicleDescription: 'цагаан Prius',
      kmTariffMnt: kmTariffMnt,
      driverFamilyName: familyName,
      driverGivenName: givenName,
      driverPhotoJpegBase64: photoBase64,
    ),
    1000,
  ),
  Reputation(
    pairedTrips,
    averageRating,
    pairedTrips.toDouble(),
    distinctCounterpartyCount: distinctPeople,
    firstPairedAt: firstPairedAt,
  ),
);

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('mn'),
  home: Scaffold(body: child),
);

void main() {
  group('the identity row on an offer card', () {
    testWidgets('leads with the driver\'s family and given name, not their '
        'key', (tester) async {
      await tester.pumpWidget(
        _host(DriverIdentityRow(ranked: _ranked(photoBase64: _jpegBase64()))),
      );

      expect(find.text('Б. Батбаяр'), findsOneWidget);
      // The key is not what a rider recognises a person by, and while it
      // occupied the name slot nobody could.
      expect(find.textContaining('npub1'), findsNothing);
    });

    testWidgets('draws the portrait the offer carried', (tester) async {
      await tester.pumpWidget(
        _host(DriverIdentityRow(ranked: _ranked(photoBase64: _jpegBase64()))),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('falls back to an initials mark when no portrait arrived', (
      tester,
    ) async {
      await tester.pumpWidget(_host(DriverIdentityRow(ranked: _ranked())));

      expect(find.byType(Image), findsNothing);
      // Both halves of the name, so two drivers called Батбаяр with
      // different family names do not share one mark.
      expect(find.text('ББ'), findsOneWidget);
    });

    testWidgets('says outright when an offer carried no name at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DriverIdentityRow(ranked: _ranked(familyName: null, givenName: null)),
        ),
      );

      expect(find.text('Нэрээ илгээгээгүй жолооч'), findsOneWidget);
    });

    testWidgets('half a name is no name', (tester) async {
      await tester.pumpWidget(
        _host(DriverIdentityRow(ranked: _ranked(givenName: null))),
      );

      expect(find.text('Нэрээ илгээгээгүй жолооч'), findsOneWidget);
      expect(find.text('Б.'), findsNothing);
    });
  });

  group('the driver page a rider opens before choosing', () {
    testWidgets('states who is coming, what they drive, and what it costs', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DriverOfferPage(
            ranked: _ranked(
              photoBase64: _jpegBase64(),
              pairedTrips: 11,
              distinctPeople: 7,
              averageRating: 4.8,
              kmTariffMnt: 1500,
            ),
          ),
        ),
      );

      expect(find.text('Б. Батбаяр'), findsOneWidget);
      expect(find.textContaining('Prius'), findsOneWidget);
      expect(find.textContaining(groupedMnt(9000)), findsOneWidget);
      // Both halves: eleven trips from one enthusiastic pubkey and eleven
      // trips from seven riders are the same first number and very
      // different evidence.
      expect(find.text('11 аялал · 7 хүн баталсан'), findsOneWidget);
      // The key stays reachable -- it is the only thing a careful rider can
      // check an offer against later -- just no longer in the name's place.
      expect(find.textContaining('npub1'), findsOneWidget);
    });

    testWidgets('says in words that the portrait proves nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(DriverOfferPage(ranked: _ranked(photoBase64: _jpegBase64()))),
      );

      expect(find.text('Баталгаажаагүй зураг'), findsOneWidget);
      expect(
        find.textContaining('Тэр царай яг энэ жолоочийнх мөн эсэхийг'),
        findsOneWidget,
      );
    });

    testWidgets('a driver who sent no portrait is marked as such rather than '
        'left looking checked', (tester) async {
      await tester.pumpWidget(_host(DriverOfferPage(ranked: _ranked())));

      expect(find.text('Зураг илгээгээгүй'), findsOneWidget);
      expect(find.text('Баталгаажаагүй зураг'), findsNothing);
    });

    testWidgets('takes the reputation apart: how many trips, how many '
        'people, since when', (tester) async {
      await tester.pumpWidget(
        _host(
          DriverOfferPage(
            ranked: _ranked(
              pairedTrips: 11,
              distinctPeople: 7,
              averageRating: 4.8,
              firstPairedAt: _kMarch2026,
            ),
          ),
        ),
      );

      expect(find.text('Баталгаажсан аялал'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('Өөр өөр хүн'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(
        find.text('2026 оны 3-р сараас хойш хуримтлагдсан'),
        findsOneWidget,
      );
    });

    testWidgets('says in one sentence why the count cannot be faked', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DriverOfferPage(ranked: _ranked(pairedTrips: 11, distinctPeople: 7)),
        ),
      );

      expect(
        find.textContaining('Зөвхөн хосоороо таарсан баримт'),
        findsOneWidget,
      );
    });

    // The fairness half. A network whose newcomers read as suspects never
    // gets a second driver, so "new" has to be said as a stage rather than
    // as a deficiency -- and the sentence explaining the system has to be
    // visible to exactly the riders being asked to take a chance.
    testWidgets('a driver with no history is called new, not untrusted', (
      tester,
    ) async {
      await tester.pumpWidget(_host(DriverOfferPage(ranked: _ranked())));

      expect(find.text('Шинэ жолооч'), findsOneWidget);
      expect(find.textContaining('Энэ нь муу үнэлгээ биш'), findsOneWidget);
      // No breakdown rows to state, and no invented ones either: zero trips
      // "since 1970" would be worse than nothing.
      expect(find.text('Баталгаажсан аялал'), findsNothing);
      expect(find.textContaining('хуримтлагдсан'), findsNothing);
    });

    testWidgets('the portrait opens full screen', (tester) async {
      await tester.pumpWidget(
        _host(DriverOfferPage(ranked: _ranked(photoBase64: _jpegBase64()))),
      );

      await tester.tap(find.byType(DriverPortrait));
      await tester.pumpAndSettle();

      expect(find.text('Хаах'), findsOneWidget);
    });
  });

  group('what the driver page answers with', () {
    /// Pushes the page onto a route stack and records what it popped with,
    /// which is the whole of its contract with `PassengerRidePage`.
    Future<bool?> pushAndAnswer(
      WidgetTester tester,
      Future<void> Function(WidgetTester) act,
    ) async {
      bool? answer;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        DriverOfferPage(ranked: _ranked(pairedTrips: 3)),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act(tester);
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('choosing this driver answers yes -- and nothing else does', (
      tester,
    ) async {
      final answer = await pushAndAnswer(tester, (t) async {
        await t.tap(find.text('Энэ жолоочийг сонгох'));
      });

      expect(answer, isTrue);
    });

    testWidgets('backing out answers nothing, so no exact address moves', (
      tester,
    ) async {
      final answer = await pushAndAnswer(tester, (t) async {
        await t.tap(find.text('Буцах'));
      });

      expect(answer, isNot(isTrue));
    });
  });
}
