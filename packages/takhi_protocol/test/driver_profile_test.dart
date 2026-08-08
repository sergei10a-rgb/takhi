// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test(
      'buildDriverProfile produces a kind-0 event with takhi extension '
      'JSON content', () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      car: 'Prius 20',
      color: 'цагаан',
      plate: '1234УНА',
      kmTariffMnt: 1500,
    );
    expect(e.kind, kKindProfile);
    expect(e.pubkey, 'ab' * 32);
    expect(e.createdAt, 1000);
    final content = jsonDecode(e.content) as Map<String, dynamic>;
    final takhi = content['takhi'] as Map<String, dynamic>;
    expect(takhi['car'], 'Prius 20');
    expect(takhi['color'], 'цагаан');
    expect(takhi['plate'], '1234УНА');
    expect(takhi['km_tariff'], 1500);
  });

  test('buildDriverProfile never includes a bank QR field (spec §8)', () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      car: 'Prius',
      color: 'хар',
      plate: '5678АБВ',
      kmTariffMnt: 1000,
    );
    expect(e.content.toLowerCase().contains('qr'), isFalse);
    expect(e.content.toLowerCase().contains('bank'), isFalse);
  });

  // The public half of the identity-privacy rule. A kind-0 is world-readable
  // and replicated forever; a name on it is a name anyone can harvest
  // against a pubkey that also publishes a plate and a live geohash. The
  // name reaches one passenger, inside the gift-wrapped offer, instead.
  test(
      'buildDriverProfile publishes no name field at all -- names travel '
      'only inside the encrypted offer', () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      car: 'Prius',
      color: 'хар',
      plate: '5678АБВ',
      kmTariffMnt: 1000,
    );
    final content = jsonDecode(e.content) as Map<String, dynamic>;
    expect(content.containsKey('name'), isFalse);
    expect(content.keys, ['takhi']);
    final takhi = content['takhi'] as Map<String, dynamic>;
    expect(takhi.containsKey('name'), isFalse);
    expect(takhi.containsKey('family_name'), isFalse);
    expect(takhi.containsKey('given_name'), isFalse);
    // Nor a photograph, by any of the names one might be smuggled under.
    for (final forbidden in ['picture', 'photo', 'avatar', 'image', 'face']) {
      expect(
        e.content.toLowerCase().contains(forbidden),
        isFalse,
        reason: "public profile leaks a '$forbidden' field",
      );
    }
  });

  test('parseDriverProfile round-trips through buildDriverProfile', () {
    final e = buildDriverProfile(
      pubkey: 'cd' * 32,
      now: 2000,
      car: 'Sonata',
      color: 'улаан',
      plate: '4321ЭЖӨ',
      kmTariffMnt: 2200,
    );
    final p = parseDriverProfile(e);
    expect(p.car, 'Sonata');
    expect(p.color, 'улаан');
    expect(p.plate, '4321ЭЖӨ');
    expect(p.kmTariffMnt, 2200);
    expect(p.familyName, isNull);
    expect(p.givenName, isNull);
    expect(p.fullName, isNull);
    // Both flat fees default to zero when the builder was not given them.
    expect(p.bookingBaseMnt, 0);
    expect(p.minFareMnt, 0);
  });

  test('the booking base and minimum fare survive the round trip', () {
    final e = buildDriverProfile(
      pubkey: 'cd' * 32,
      now: 2000,
      car: 'Sonata',
      color: 'улаан',
      plate: '4321ЭЖӨ',
      kmTariffMnt: 2200,
      bookingBaseMnt: 1500,
      minFareMnt: 3000,
    );
    final p = parseDriverProfile(e);
    expect(p.bookingBaseMnt, 1500);
    expect(p.minFareMnt, 3000);
  });

  test('a profile published before the two flat fees existed parses them as '
      'zero rather than throwing', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({
        'takhi': {
          'car': 'Prius',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': 1500,
          'wait_tariff': 300,
          'duration_tariff': 120,
        },
      }),
    );
    final p = parseDriverProfile(e);
    expect(p.bookingBaseMnt, 0);
    expect(p.minFareMnt, 0);
    // Everything the older profile did carry is still read.
    expect(p.kmTariffMnt, 1500);
    expect(p.waitTariffMntPerMinute, 300);
    expect(p.durationTariffMntPerMinute, 120);
  });

  // The receiving half of the same rule. Another client -- or an older
  // build of this one -- may well publish a `name`. Reading it would put a
  // world-readable, unverified, attacker-chosen string on a passenger's
  // screen next to a face, which is exactly what the encrypted route exists
  // to prevent.
  test('parseDriverProfile ignores a name a public profile carries anyway', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({
        'name': 'Бат',
        'family_name': 'Б.',
        'given_name': 'Батбаяр',
        'picture': 'https://example.invalid/face.jpg',
        'takhi': {
          'car': 'Prius',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': 1500,
        },
      }),
    );
    final p = parseDriverProfile(e);
    expect(p.familyName, isNull);
    expect(p.givenName, isNull);
    expect(p.fullName, isNull);
    // The vehicle half is still read normally -- ignoring the name must not
    // cost the passenger the car they are meant to look for.
    expect(p.car, 'Prius');
    expect(p.plate, '1234УНА');
  });

  // A profile with no name is the normal case now, not an error one.
  test('parseDriverProfile accepts a profile with no name field', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({
        'takhi': {
          'car': 'Prius',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': 1500,
        },
      }),
    );
    expect(parseDriverProfile(e).car, 'Prius');
  });

  test('parseDriverProfile rejects a non kind-0 event', () {
    final wrong = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: 1,
      tags: const [],
      content: '{}',
    );
    expect(() => parseDriverProfile(wrong), throwsFormatException);
  });

  test('parseDriverProfile rejects malformed (non-JSON) content', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: 'not json',
    );
    expect(() => parseDriverProfile(e), throwsFormatException);
  });

  test('parseDriverProfile rejects content missing the takhi extension', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({'name': 'Бат'}),
    );
    expect(() => parseDriverProfile(e), throwsFormatException);
  });

  test('parseDriverProfile rejects a wrong-typed km_tariff', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({
        'takhi': {
          'car': 'Prius',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': '1500',
        },
      }),
    );
    expect(() => parseDriverProfile(e), throwsFormatException);
  });

  test(
      'buildDriverProfile publishes the waiting tariff alongside the '
      'km-tariff, so a passenger can see both before choosing', () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      car: 'Prius 30',
      color: 'саарал',
      plate: '1234УНА',
      kmTariffMnt: 1500,
      waitTariffMntPerMinute: 300,
    );
    final takhi = (jsonDecode(e.content) as Map<String, dynamic>)['takhi']
        as Map<String, dynamic>;
    expect(takhi['km_tariff'], 1500);
    expect(takhi['wait_tariff'], 300);
    expect(parseDriverProfile(e).waitTariffMntPerMinute, 300);
  });

  test(
      'a driver who charges nothing for waiting publishes that explicitly, '
      'rather than leaving it unsaid', () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      car: 'Prius',
      color: 'хар',
      plate: '1234УНА',
      kmTariffMnt: 1500,
    );
    final takhi = (jsonDecode(e.content) as Map<String, dynamic>)['takhi']
        as Map<String, dynamic>;
    expect(takhi['wait_tariff'], 0);
  });

  test(
      'a profile published before waiting tariffs existed still parses, as '
      'a driver who charges nothing for waiting', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({
        'name': 'Бат',
        'takhi': {
          'car': 'Prius',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': 1500,
        },
      }),
    );
    expect(parseDriverProfile(e).waitTariffMntPerMinute, 0);
  });

  test('parseDriverProfile rejects a wrong-typed waiting tariff', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({
        'takhi': {
          'car': 'Prius',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': 1500,
          'wait_tariff': '300',
        },
      }),
    );
    expect(() => parseDriverProfile(e), throwsFormatException);
  });

  // The third rate (added 2026-08-01). Same publication rules as the other
  // two -- it is public pricing, so it goes in the kind-0 -- and the same
  // absent-means-zero migration, because a driver who has not opened the app
  // since it was added is charging nothing for trip duration, not an unknown
  // amount.
  test(
      'buildDriverProfile publishes the trip-duration tariff alongside the '
      'other two, so a passenger sees the whole price', () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      car: 'Prius 30',
      color: 'саарал',
      plate: '1234УНА',
      kmTariffMnt: 1500,
      waitTariffMntPerMinute: 300,
      durationTariffMntPerMinute: 200,
    );
    final takhi = (jsonDecode(e.content) as Map<String, dynamic>)['takhi']
        as Map<String, dynamic>;
    expect(takhi['km_tariff'], 1500);
    expect(takhi['wait_tariff'], 300);
    expect(takhi['duration_tariff'], 200);
    expect(parseDriverProfile(e).durationTariffMntPerMinute, 200);
  });

  test(
      'a driver who does not charge for trip duration publishes that '
      'explicitly, rather than leaving it unsaid', () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      car: 'Prius',
      color: 'хар',
      plate: '1234УНА',
      kmTariffMnt: 1500,
    );
    final takhi = (jsonDecode(e.content) as Map<String, dynamic>)['takhi']
        as Map<String, dynamic>;
    expect(takhi['duration_tariff'], 0);
  });

  test(
      'a profile published before trip-duration tariffs existed still '
      'parses, as a driver who charges nothing for duration', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({
        'takhi': {
          'car': 'Prius',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': 1500,
          'wait_tariff': 300,
        },
      }),
    );
    final p = parseDriverProfile(e);
    expect(p.durationTariffMntPerMinute, 0);
    // The rates that *were* published are untouched by the migration of the
    // one that was not.
    expect(p.waitTariffMntPerMinute, 300);
    expect(p.kmTariffMnt, 1500);
  });

  test('parseDriverProfile rejects a wrong-typed duration tariff', () {
    final e = NostrEvent(
      pubkey: 'ab' * 32,
      createdAt: 1,
      kind: kKindProfile,
      tags: const [],
      content: jsonEncode({
        'takhi': {
          'car': 'Prius',
          'color': 'цагаан',
          'plate': '1234УНА',
          'km_tariff': 1500,
          'duration_tariff': '200',
        },
      }),
    );
    expect(() => parseDriverProfile(e), throwsFormatException);
  });

  // Adding a rate must not have re-opened the hole the name rules close: the
  // kind-0 grew a field, and the field it grew is a price, not an identity.
  test('publishing all three tariffs still leaks neither name nor photograph',
      () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      car: 'Prius',
      color: 'хар',
      plate: '1234УНА',
      kmTariffMnt: 1500,
      waitTariffMntPerMinute: 300,
      durationTariffMntPerMinute: 200,
    );
    final content = jsonDecode(e.content) as Map<String, dynamic>;
    expect(content.keys, ['takhi']);
    final takhi = content['takhi'] as Map<String, dynamic>;
    expect(takhi.keys, [
      'car',
      'color',
      'plate',
      'km_tariff',
      'wait_tariff',
      'duration_tariff',
      // Two more rate fields, and rates only: the booking base and the
      // minimum fare are prices, published like every other price. The point
      // of pinning the exact key set is that a name or a photograph never
      // joins them, and neither of these is one.
      'booking_base',
      'min_fare',
    ]);
  });

  test('copyWith carries the duration tariff through untouched', () {
    const original = DriverProfile(
      car: 'Prius',
      color: 'хар',
      plate: '1234УНА',
      kmTariffMnt: 1500,
      waitTariffMntPerMinute: 300,
      durationTariffMntPerMinute: 200,
    );
    expect(original.copyWith(car: 'Sonata').durationTariffMntPerMinute, 200);
    expect(
        original
            .copyWith(durationTariffMntPerMinute: 0)
            .durationTariffMntPerMinute,
        0);
  });

  group('fullName', () {
    const vehicle = {'car': 'Prius', 'color': 'хар', 'plate': '1234УНА'};

    DriverProfile profile({String? family, String? given}) => DriverProfile(
          familyName: family,
          givenName: given,
          car: vehicle['car']!,
          color: vehicle['color']!,
          plate: vehicle['plate']!,
          kmTariffMnt: 1500,
        );

    test('joins family name and given name, family first', () {
      expect(profile(family: 'Б.', given: 'Батбаяр').fullName, 'Б. Батбаяр');
    });

    // Half a name shown as though it were the whole one is worse than a
    // pubkey: a passenger reading «Батбаяр» cannot tell it is incomplete.
    test('is null while either half is missing', () {
      expect(profile(family: 'Б.', given: null).fullName, isNull);
      expect(profile(family: null, given: 'Батбаяр').fullName, isNull);
      expect(profile().fullName, isNull);
    });

    test('is null when either half is present but empty', () {
      expect(profile(family: '', given: 'Батбаяр').fullName, isNull);
      expect(profile(family: 'Б.', given: '').fullName, isNull);
    });
  });
}
