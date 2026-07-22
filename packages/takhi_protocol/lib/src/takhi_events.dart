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
      ],
      content: comment);
}

class TripReceipt {
  final String tripId, counterpartyPubkey, role, comment, authorPubkey;
  final int ratingStars, distanceMeters, durationSeconds, priceMnt, createdAt;
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
  });
}

TripReceipt parseTripReceipt(NostrEvent e) {
  if (e.kind != kKindTripReceipt) throw FormatException('not a trip receipt');
  String tag(String k) {
    final t = e.tags.firstWhere((x) => x.first == k,
        orElse: () => throw FormatException('missing $k'));
    return t[1];
  }

  return TripReceipt(
      tripId: tag('d'),
      counterpartyPubkey: tag('p'),
      role: tag('role'),
      ratingStars: int.parse(tag('rating')),
      distanceMeters: int.parse(tag('dist')),
      durationSeconds: int.parse(tag('dur')),
      priceMnt: int.parse(tag('price')),
      comment: e.content,
      authorPubkey: e.pubkey,
      createdAt: e.createdAt);
}
