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
      name: 'Бат',
      car: 'Prius 20',
      color: 'цагаан',
      plate: '1234УНА',
      kmTariffMnt: 1500,
    );
    expect(e.kind, kKindProfile);
    expect(e.pubkey, 'ab' * 32);
    expect(e.createdAt, 1000);
    final content = jsonDecode(e.content) as Map<String, dynamic>;
    expect(content['name'], 'Бат');
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
      name: 'Бат',
      car: 'Prius',
      color: 'хар',
      plate: '5678АБВ',
      kmTariffMnt: 1000,
    );
    expect(e.content.toLowerCase().contains('qr'), isFalse);
    expect(e.content.toLowerCase().contains('bank'), isFalse);
  });

  test('parseDriverProfile round-trips through buildDriverProfile', () {
    final e = buildDriverProfile(
      pubkey: 'cd' * 32,
      now: 2000,
      name: 'Сараа',
      car: 'Sonata',
      color: 'улаан',
      plate: '4321ЭЖӨ',
      kmTariffMnt: 2200,
    );
    final p = parseDriverProfile(e);
    expect(p.name, 'Сараа');
    expect(p.car, 'Sonata');
    expect(p.color, 'улаан');
    expect(p.plate, '4321ЭЖӨ');
    expect(p.kmTariffMnt, 2200);
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
        'name': 'Бат',
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

  test('parseDriverProfile rejects a missing name field', () {
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
    expect(() => parseDriverProfile(e), throwsFormatException);
  });

  test(
      'buildDriverProfile publishes the waiting tariff alongside the '
      'km-tariff, so a passenger can see both before choosing', () {
    final e = buildDriverProfile(
      pubkey: 'ab' * 32,
      now: 1000,
      name: 'Бат',
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
      name: 'Бат',
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
        'name': 'Бат',
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
}
