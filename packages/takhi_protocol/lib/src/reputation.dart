// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'takhi_events.dart';

class Reputation {
  final int pairedTripCount;
  final double averageRating;
  final double trustWeight;
  const Reputation(this.pairedTripCount, this.averageRating, this.trustWeight);
}

Reputation computeReputation({
  required String subjectPubkey,
  required List<TripReceipt> allReceipts,
  Set<String> viewerTrusted = const {},
}) {
  // Index receipts by (author, counterparty, tripId) for pairing lookup.
  bool hasCounter(String author, String about, String trip) =>
      allReceipts.any((x) =>
          x.authorPubkey == about &&
          x.counterpartyPubkey == author &&
          x.tripId == trip);

  // Receipts ABOUT the subject that are genuinely paired.
  final paired = allReceipts
      .where((x) =>
          x.counterpartyPubkey == subjectPubkey &&
          x.authorPubkey != subjectPubkey &&
          hasCounter(x.authorPubkey, subjectPubkey, x.tripId))
      .toList();

  if (paired.isEmpty) return const Reputation(0, 0, 0);

  final avg =
      paired.map((e) => e.ratingStars).reduce((a, b) => a + b) / paired.length;

  // Distinct-counterparty diversity: sum log(1 + trips_from_author) per
  // distinct author, so many trips from one author diminish sharply.
  final byAuthor = <String, int>{};
  for (final rcpt in paired) {
    byAuthor[rcpt.authorPubkey] = (byAuthor[rcpt.authorPubkey] ?? 0) + 1;
  }
  var weight = 0.0;
  byAuthor.forEach((author, count) {
    final base = math.log(1 + count); // diminishing within one author
    final trustBoost = viewerTrusted.contains(author) ? 3.0 : 1.0;
    weight += base * trustBoost;
  });

  return Reputation(paired.length, avg, weight);
}
