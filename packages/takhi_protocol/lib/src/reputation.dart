// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'takhi_events.dart';

class Reputation {
  final int pairedTripCount;
  final double averageRating;
  final double trustWeight;

  /// How many *different* counterparties are behind [pairedTripCount].
  ///
  /// Carried out of this function rather than left inside it because it is
  /// the number that makes the trip count mean anything: "nine trips" from
  /// one person and "nine trips" from nine people are the same figure and
  /// very different evidence, and [trustWeight] -- which does know the
  /// difference -- is a damped score no rider can read. A screen that shows
  /// only the trip count is showing the half an attacker finds cheapest to
  /// inflate.
  final int distinctCounterpartyCount;

  /// Unix seconds of the oldest and newest paired receipt about the subject,
  /// or `null` when there are none.
  ///
  /// The oldest is how long the history has been accumulating, which is the
  /// other half of "is this real": a hundred trips minted last Tuesday is a
  /// different claim from a hundred trips over two years, and receipts carry
  /// the timestamps that tell them apart. Left as raw seconds because
  /// formatting a date is a locale decision this pure-Dart package has no
  /// business making.
  final int? firstPairedAt;
  final int? lastPairedAt;

  const Reputation(
    this.pairedTripCount,
    this.averageRating,
    this.trustWeight, {
    this.distinctCounterpartyCount = 0,
    this.firstPairedAt,
    this.lastPairedAt,
  });
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
  //
  // Sybil-resistance caveat: a pubkey is free to mint, so a *single* new
  // pseudonym rating the subject once is, on receipt data alone,
  // cryptographically indistinguishable from a genuine new rider doing the
  // same thing. Rule 2 above only defeats the *lazy* Sybil who reuses one
  // pubkey across many trips (repeats from that author diminish sharply).
  // It does NOT defeat an attacker willing to mint N distinct throwaway
  // pubkeys, one trip each -- per spec (docs/superpowers/specs/
  // 2026-07-21-takhi-design.md, "Sybil" section) that attack is meant to be
  // deterred by cost (two identities + PoW + time per pair) and by the
  // viewer's own web-of-trust (Rule 3: `viewerTrusted`), not by this
  // function inventing a signal that doesn't exist in the data.
  //
  // What we CAN fix without a trust anchor: without Rule 3 vouching for an
  // author, per-author contributions are summed and then damped with an
  // outer sqrt() so minting more distinct throwaway pubkeys yields
  // strictly diminishing (sub-linear), not unbounded-linear, returns --
  // raising the cost/benefit ratio of a minting attack even though it can
  // never be driven to zero from receipts alone. Trusted authors (Rule 3)
  // are exempt from this outer damping since the viewer already vouches
  // for their identity, so genuine trust relationships aren't penalized.
  final byAuthor = <String, int>{};
  for (final rcpt in paired) {
    byAuthor[rcpt.authorPubkey] = (byAuthor[rcpt.authorPubkey] ?? 0) + 1;
  }
  var trustedWeight = 0.0;
  var untrustedRaw = 0.0;
  byAuthor.forEach((author, count) {
    final base = math.log(1 + count); // diminishing within one author
    if (viewerTrusted.contains(author)) {
      trustedWeight +=
          base * 3.0; // Rule 3: vouched-for identities count in full.
    } else {
      untrustedRaw += base;
    }
  });
  // Rule 4: outer sub-linear damping on the unvouched-for pool bounds the
  // payoff of minting many distinct throwaway pubkeys.
  final weight = trustedWeight + math.sqrt(untrustedRaw);

  // Both timestamps come off the receipts themselves rather than off any
  // clock here: this function is pure, and "when did this history start" has
  // to be a claim two signatures already stand behind.
  final times = paired.map((e) => e.createdAt).toList()..sort();

  return Reputation(
    paired.length,
    avg,
    weight,
    distinctCounterpartyCount: byAuthor.length,
    firstPairedAt: times.first,
    lastPairedAt: times.last,
  );
}
