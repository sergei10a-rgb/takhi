// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('ride request has geohash, expiration, price tags', () {
    final e = buildRideRequest(
        pubkey: 'ab' * 32,
        now: 1000,
        pickupLat: 47.9186,
        pickupLon: 106.9176,
        destLat: 47.9100,
        destLon: 106.9000);
    expect(e.kind, kKindRideRequest);
    expect(e.tags.firstWhere((t) => t.first == 'g')[1].length, 6);
    expect(e.tags.firstWhere((t) => t.first == 'expiration')[1], '1240');
    // No price tag can be produced at all. A passenger naming a figure
    // before anyone has quoted one is guessing, and a guess that lands low
    // draws no offers with nothing on screen saying why -- so pricing runs
    // the other way now and each driver quotes their own.
    expect(e.tags.any((t) => t.first == 'price'), isFalse);
  });

  test('trip receipt round-trips through parse', () {
    final e = buildTripReceipt(
        pubkey: 'cd' * 32,
        now: 2000,
        tripId: 'trip-xyz',
        counterpartyPubkey: 'ef' * 32,
        role: 'passenger',
        ratingStars: 5,
        distanceMeters: 6000,
        durationSeconds: 900,
        priceMnt: 9000,
        comment: 'сайн');
    final p = parseTripReceipt(e);
    expect(p.tripId, 'trip-xyz');
    expect(p.counterpartyPubkey, 'ef' * 32);
    expect(p.role, 'passenger');
    expect(p.ratingStars, 5);
    expect(p.distanceMeters, 6000);
    expect(p.durationSeconds, 900);
    expect(p.priceMnt, 9000);
    expect(p.comment, 'сайн');
    expect(p.authorPubkey, 'cd' * 32);
    expect(p.createdAt, 2000);
  });

  test('parseTripReceipt rejects wrong kind', () {
    final wrong = NostrEvent(
        pubkey: 'ab' * 32, createdAt: 1, kind: 1, tags: [], content: '');
    expect(() => parseTripReceipt(wrong), throwsFormatException);
  });

  test('parseRideRequest rejects an event missing a required tag', () {
    // Right kind, but the 'dest' tag required by parseRideRequest is
    // missing — must hit the tag() helper's orElse -> FormatException path.
    final missingDest = NostrEvent(
        pubkey: 'ab' * 32,
        createdAt: 1,
        kind: kKindRideRequest,
        tags: [
          ['g', 'u9huf'],
          ['expiration', '1240'],
        ],
        content: '');
    expect(() => parseRideRequest(missingDest), throwsFormatException);
  });

  test('parseTripReceipt rejects an event missing a required tag', () {
    // Right kind, but the 'd' (tripId) tag is missing.
    final missingTripId = NostrEvent(
        pubkey: 'cd' * 32,
        createdAt: 2000,
        kind: kKindTripReceipt,
        tags: [
          ['p', 'ef' * 32],
          ['role', 'passenger'],
          ['rating', '5'],
          ['dist', '6000'],
          ['dur', '900'],
          ['price', '9000'],
        ],
        content: '');
    expect(() => parseTripReceipt(missingTripId), throwsFormatException);
  });

  test('buildTripReceipt rejects rating below 1', () {
    expect(
        () => buildTripReceipt(
            pubkey: 'cd' * 32,
            now: 2000,
            tripId: 'trip-xyz',
            counterpartyPubkey: 'ef' * 32,
            role: 'passenger',
            ratingStars: 0,
            distanceMeters: 6000,
            durationSeconds: 900,
            priceMnt: 9000),
        throwsArgumentError);
  });

  test('buildTripReceipt rejects rating above 5', () {
    expect(
        () => buildTripReceipt(
            pubkey: 'cd' * 32,
            now: 2000,
            tripId: 'trip-xyz',
            counterpartyPubkey: 'ef' * 32,
            role: 'passenger',
            ratingStars: 6,
            distanceMeters: 6000,
            durationSeconds: 900,
            priceMnt: 9000),
        throwsArgumentError);
  });

  test('ride request without offered price omits price tag', () {
    final e = buildRideRequest(
        pubkey: 'ab' * 32,
        now: 1000,
        pickupLat: 47.9186,
        pickupLon: 106.9176,
        destLat: 47.9100,
        destLon: 106.9000);
    expect(e.tags.any((t) => t.first == 'price'), isFalse);
    final p = parseRideRequest(e);
    expect(p.pickupGeohash.length, 6);
    expect(p.destGeohash.length, 6);
  });

  test('a price tag from an older client is ignored rather than parsed', () {
    // Reading it would put the removed behaviour back on the driver's
    // screen through the back door: a driver who sees "the passenger wants
    // to pay 3000₮" is anchored by it whoever sent it.
    final e = buildRideRequest(
        pubkey: 'ab' * 32,
        now: 1000,
        pickupLat: 47.9186,
        pickupLon: 106.9176,
        destLat: 47.9100,
        destLon: 106.9000);
    final legacy = NostrEvent(
        pubkey: e.pubkey,
        createdAt: e.createdAt,
        kind: e.kind,
        tags: [
          ...e.tags,
          ['price', '3000']
        ],
        content: e.content);
    final parsed = parseRideRequest(legacy);
    expect(parsed.pickupGeohash, isNotEmpty);
    expect(parsed.destGeohash, isNotEmpty);
  });

  test(
      'a trip receipt carries the waiting side of the fare, so both '
      'signatures cover the same breakdown and not just the same total', () {
    final e = buildTripReceipt(
        pubkey: 'cd' * 32,
        now: 2000,
        tripId: 'trip-wait',
        counterpartyPubkey: 'ef' * 32,
        role: 'driver',
        ratingStars: 5,
        distanceMeters: 6000,
        durationSeconds: 1500,
        priceMnt: 9600,
        waitingSeconds: 120,
        waitingFareMnt: 600);
    final p = parseTripReceipt(e);
    expect(p.priceMnt, 9600);
    expect(p.waitingSeconds, 120);
    expect(p.waitingFareMnt, 600);
    // Derived, never stored twice: the distance row can never contradict
    // the total both sides signed.
    expect(p.distanceFareMnt, 9000);
  });

  test(
      'a receipt published before waiting fares existed still parses, as a '
      'trip that was all distance and no waiting', () {
    final legacy = NostrEvent(
        pubkey: 'cd' * 32,
        createdAt: 2000,
        kind: kKindTripReceipt,
        tags: [
          ['d', 'trip-old'],
          ['p', 'ef' * 32],
          ['role', 'passenger'],
          ['rating', '4'],
          ['dist', '6000'],
          ['dur', '900'],
          ['price', '9000'],
        ],
        content: '');
    final p = parseTripReceipt(legacy);
    expect(p.waitingSeconds, 0);
    expect(p.waitingFareMnt, 0);
    expect(p.distanceFareMnt, 9000);
  });

  test('a fixed-price receipt still states plainly that nothing was waited',
      () {
    final e = buildTripReceipt(
        pubkey: 'cd' * 32,
        now: 2000,
        tripId: 'trip-fixed',
        counterpartyPubkey: 'ef' * 32,
        role: 'passenger',
        ratingStars: 5,
        distanceMeters: 6000,
        durationSeconds: 900,
        priceMnt: 9000);
    expect(e.tags.any((t) => t.first == 'wait' && t[1] == '0'), isTrue);
    expect(e.tags.any((t) => t.first == 'waitprice' && t[1] == '0'), isTrue);
  });
}
