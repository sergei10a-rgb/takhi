// SPDX-License-Identifier: AGPL-3.0-or-later
import 'takhi_events.dart';

/// Whether [mine] — a receipt this device already published — has its
/// reciprocal counterpart in [candidates]: the other side's own kind-30177
/// receipt for the same trip, pointing back (spec §9 "хос гарын үсэгтэй
/// баримт" / §4.3 "Хос баримтын дүрэм").
///
/// This is a single-trip UI-facing check ("has my counterparty signed
/// yet?"), distinct from `computeReputation`'s internal `hasCounter`,
/// which answers the aggregate "how much does this pubkey's whole history
/// weigh" question across every trip at once. Both walk the same
/// three-field match (`tripId` + swapped author/counterparty); kept as two
/// small functions rather than one shared helper because they serve
/// different callers with different return shapes (bool vs. a weighted
/// score) and unifying them would only add an indirection neither call
/// site needs.
bool isTripReceiptPaired({
  required TripReceipt mine,
  required List<TripReceipt> candidates,
}) {
  return candidates.any((other) =>
      other.tripId == mine.tripId &&
      other.authorPubkey == mine.counterpartyPubkey &&
      other.counterpartyPubkey == mine.authorPubkey);
}
