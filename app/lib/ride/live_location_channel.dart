// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';

/// Publishes and subscribes to kind-20178 live-location pings (spec §6/
/// §7.1 step 5) over a [RelayPool] — the position-heartbeat sibling of
/// [RideDmChannel], deliberately NOT built on it: live location skips the
/// NIP-17 gift-wrap layer entirely (see `buildLiveLocationEvent`'s doc
/// comment) and calls `pool.publish`/`pool.subscribe` directly with a
/// plain NIP-44-encrypted kind-20178 event.
class LiveLocationChannel {
  final RelayPool _pool;
  LiveLocationChannel(this._pool);

  Future<void> send({
    required String senderPrivHex,
    required String recipientPubHex,
    required String tripId,
    required double lat,
    required double lon,
    required int now,
  }) async {
    final event = buildLiveLocationEvent(
      senderPrivHex: senderPrivHex,
      recipientPubHex: recipientPubHex,
      now: now,
      tripId: tripId,
      lat: lat,
      lon: lon,
    );
    await _pool.publish(event);
  }

  /// Every live-location ping addressed to [myPubHex] for [tripId] —
  /// scoped to one trip so a device with more than one concurrent trip
  /// (not expected in this MVP, but not structurally prevented either)
  /// never mixes their position streams.
  Stream<LiveLocation> watch(String myPubHex, String myPrivHex, String tripId) {
    final filter = RelayFilter(
      kinds: [kKindLiveLocation],
      tagFilters: {
        '#p': [myPubHex],
        '#d': [tripId],
      },
    );
    return _pool.subscribe(filter).asyncExpand((event) async* {
      try {
        final parsed = parseLiveLocationEvent(event, myPrivHex);
        // Belt-and-suspenders: the relay's '#d' tag filter already scopes
        // this subscription to [tripId], but a non-compliant/misbehaving
        // relay could still deliver a foreign-trip ping (the tag filter is
        // server-trusted, same caveat as `TripReceiptRepository`). The
        // encrypted payload's own tripId is the one field the relay cannot
        // forge, so re-check it client-side before it ever reaches the UI.
        if (parsed.tripId != tripId) return;
        yield parsed;
      } on Exception {
        // Not decryptable with our key, or malformed; drop rather than
        // surfacing it as an error — same policy as `RideDmChannel.inbox`.
      }
    });
  }
}
