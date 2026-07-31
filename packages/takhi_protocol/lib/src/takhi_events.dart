// SPDX-License-Identifier: AGPL-3.0-or-later
import 'event.dart';
import 'geohash.dart';

const kKindProfile = 0;
const kKindRideRequest = 20177;
const kKindLiveLocation = 20178;
const kKindTripReceipt = 30177;
const kKindHelper = 30178;

NostrEvent buildRideRequest({
  required String pubkey,
  required int now,
  required double pickupLat,
  required double pickupLon,
  required double destLat,
  required double destLon,
  int? offeredMnt,
  String note = '',
  int expirySeconds = 240,
}) {
  final tags = <List<String>>[
    ['g', geohashEncode(pickupLat, pickupLon, precision: 6)],
    ['dest', geohashEncode(destLat, destLon, precision: 6)],
    ['expiration', (now + expirySeconds).toString()],
  ];
  if (offeredMnt != null) tags.add(['price', offeredMnt.toString()]);
  return NostrEvent(
      pubkey: pubkey,
      createdAt: now,
      kind: kKindRideRequest,
      tags: tags,
      content: note);
}

class RideRequest {
  final String pickupGeohash, destGeohash;
  final int? offeredMnt;
  final int expiration;
  final String note;
  const RideRequest(this.pickupGeohash, this.destGeohash, this.offeredMnt,
      this.expiration, this.note);
}

RideRequest parseRideRequest(NostrEvent e) {
  if (e.kind != kKindRideRequest) throw FormatException('not a ride request');
  String tag(String k) {
    final t = e.tags.firstWhere((x) => x.first == k,
        orElse: () => throw FormatException('missing $k'));
    return t[1];
  }

  final priceTag = e.tags.where((x) => x.first == 'price').toList();
  return RideRequest(
      tag('g'),
      tag('dest'),
      priceTag.isEmpty ? null : int.parse(priceTag.first[1]),
      int.parse(tag('expiration')),
      e.content);
}

NostrEvent buildTripReceipt({
  required String pubkey,
  required int now,
  required String tripId,
  required String counterpartyPubkey,
  required String role,
  required int ratingStars,
  required int distanceMeters,
  required int durationSeconds,
  required int priceMnt,
  int waitingSeconds = 0,
  int waitingFareMnt = 0,
  String comment = '',
}) {
  if (ratingStars < 1 || ratingStars > 5) {
    throw ArgumentError('rating must be 1..5');
  }
  return NostrEvent(
      pubkey: pubkey,
      createdAt: now,
      kind: kKindTripReceipt,
      tags: [
        ['d', tripId],
        ['p', counterpartyPubkey],
        ['role', role],
        ['rating', ratingStars.toString()],
        ['dist', distanceMeters.toString()],
        ['dur', durationSeconds.toString()],
        ['price', priceMnt.toString()],
        // How much of `price` was time rather than distance (spec §7.4).
        // Written on every receipt, zero included: the pair of receipts a
        // trip leaves behind is the only lasting record of what was agreed,
        // and "waiting cost nothing" is a fact worth stating rather than
        // inferring from a missing tag. The distance half is deliberately
        // not written — it is `price` minus this, and two stored numbers
        // that must agree are two numbers that can disagree.
        ['wait', waitingSeconds.toString()],
        ['waitprice', waitingFareMnt.toString()],
      ],
      content: comment);
}

class TripReceipt {
  final String tripId, counterpartyPubkey, role, comment, authorPubkey;
  final int ratingStars, distanceMeters, durationSeconds, priceMnt, createdAt;

  /// The waiting half of [priceMnt] and the time it covers (spec §7.4).
  /// Both zero on a receipt written before waiting fares existed, which is
  /// also the truth about such a trip: it was billed on distance alone.
  final int waitingSeconds, waitingFareMnt;

  const TripReceipt({
    required this.tripId,
    required this.counterpartyPubkey,
    required this.role,
    required this.ratingStars,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.priceMnt,
    required this.comment,
    required this.authorPubkey,
    required this.createdAt,
    this.waitingSeconds = 0,
    this.waitingFareMnt = 0,
  });

  /// The distance half of [priceMnt] — derived, never carried, so the two
  /// halves shown to a passenger always sum to the total both sides signed.
  int get distanceFareMnt => priceMnt - waitingFareMnt;
}

TripReceipt parseTripReceipt(NostrEvent e) {
  if (e.kind != kKindTripReceipt) throw FormatException('not a trip receipt');
  String tag(String k) {
    final t = e.tags.firstWhere((x) => x.first == k,
        orElse: () => throw FormatException('missing $k'));
    return t[1];
  }

  // A receipt published before waiting fares existed simply has no such
  // tag; that is an older peer, not a malformed event, so it parses as the
  // all-distance trip it was rather than failing the whole fetch.
  int optionalIntTag(String k) {
    final t = e.tags.where((x) => x.first == k).toList();
    return t.isEmpty ? 0 : int.parse(t.first[1]);
  }

  return TripReceipt(
      tripId: tag('d'),
      counterpartyPubkey: tag('p'),
      role: tag('role'),
      ratingStars: int.parse(tag('rating')),
      distanceMeters: int.parse(tag('dist')),
      durationSeconds: int.parse(tag('dur')),
      priceMnt: int.parse(tag('price')),
      waitingSeconds: optionalIntTag('wait'),
      waitingFareMnt: optionalIntTag('waitprice'),
      comment: e.content,
      authorPubkey: e.pubkey,
      createdAt: e.createdAt);
}
