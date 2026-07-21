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

  Future<List<TripReceipt>> receiptsAbout(
    String subjectPubkey, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final filter = RelayFilter(
      kinds: [kKindTripReceipt],
      tagFilters: {
        '#p': [subjectPubkey],
      },
    );
    final receipts = <TripReceipt>[];
    final sub = _pool.subscribe(filter).listen((event) {
      try {
        receipts.add(parseTripReceipt(event));
      } on FormatException {
        // A malformed/foreign kind-30177 event; skip it rather than fail
        // the whole fetch.
      }
    });
    await Future<void>.delayed(timeout);
    await sub.cancel();
    return receipts;
  }
}
