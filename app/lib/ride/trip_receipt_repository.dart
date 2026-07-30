// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';

/// Fetches the trip receipts already published about a pubkey (kind
/// 30177, spec §9), so [rankRideOffers] can weigh a driver's history.
/// Deliberately a snapshot fetch, not a long-lived subscription: it
/// collects whatever a relay has stored for [timeout], then closes.
class TripReceiptRepository {
  final RelayPool _pool;
  TripReceiptRepository(this._pool);

  /// Fetches both directions needed for [computeReputation]'s pairing check
  /// (spec §9): receipts written ABOUT [subjectPubkey] (`#p` tag) *and*
  /// receipts [subjectPubkey] themselves authored about a counterparty
  /// (`authors`). Without the latter, `hasCounter()` in
  /// `packages/takhi_protocol/lib/src/reputation.dart` can never find a
  /// reciprocal receipt, `paired` is always empty, and every driver's
  /// `trustWeight` is always 0.
  Future<List<TripReceipt>> receiptsAbout(
    String subjectPubkey, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final aboutFilter = RelayFilter(
      kinds: [kKindTripReceipt],
      tagFilters: {
        '#p': [subjectPubkey],
      },
    );
    final authoredFilter = RelayFilter(
      kinds: [kKindTripReceipt],
      authors: [subjectPubkey],
    );

    // Keyed by event id so a receipt matched by both filters (e.g. a relay
    // that echoes both queries) is only counted once.
    final receiptsById = <String, TripReceipt>{};
    void onEvent(NostrEvent event) {
      final id = event.id;
      if (id == null) return;
      try {
        receiptsById[id] = parseTripReceipt(event);
      } on FormatException {
        // A malformed/foreign kind-30177 event; skip it rather than fail
        // the whole fetch.
      }
    }

    final subs = [
      _pool.subscribe(aboutFilter).listen(onEvent),
      _pool.subscribe(authoredFilter).listen(onEvent),
    ];
    await Future<void>.delayed(timeout);
    for (final sub in subs) {
      await sub.cancel();
    }
    return receiptsById.values.toList();
  }

  /// Builds, signs, and publishes this device's own trip receipt (spec
  /// §7.1 step 6 / §9): one call per side, both on the same [tripId], each
  /// naming the other as [counterpartyPubkey]. Pairing (whether the other
  /// side has published theirs yet) is a separate read via
  /// [receiptsAbout] + `isTripReceiptPaired` — this method only ever
  /// writes.
  Future<NostrEvent> publish({
    required String privHex,
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
  }) async {
    final pubHex = pubkeyFromPrivate(privHex);
    final unsigned = buildTripReceipt(
      pubkey: pubHex,
      now: now,
      tripId: tripId,
      counterpartyPubkey: counterpartyPubkey,
      role: role,
      ratingStars: ratingStars,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      priceMnt: priceMnt,
      waitingSeconds: waitingSeconds,
      waitingFareMnt: waitingFareMnt,
      comment: comment,
    );
    final signed = signEvent(unsigned, privHex);
    await _pool.publish(signed);
    return signed;
  }
}
