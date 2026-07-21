// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';
import 'ride_dm_payload.dart';

/// The rumor kind used for every takhi ride DM. Distinct from any kind
/// this app ever publishes directly to a relay (`kKindRideRequest`,
/// `kKindTripReceipt`, ...) -- a rumor's kind lives only inside the
/// encrypted gift-wrap content, never on the wire by itself, but keeping
/// the numbers disjoint avoids confusing a future PROTOCOL.md reader.
const int kRumorKindRideDm = 20179;

/// A private takhi message a caller received: the sender's real pubkey
/// (recovered and verified by `nip17Unwrap`, spec §6 privacy tiering) and
/// the decoded [RideDmPayload].
class InboundRideDm {
  final String senderPubkey;
  final RideDmPayload payload;

  /// The gift wrap event's own `createdAt`. Per NIP-59 privacy tiering
  /// this is deliberately randomized up to
  /// `kGiftWrapRandomizationWindowSeconds` into the past by the sender
  /// (see `randomTimestamp`/`nip17Wrap` in takhi_protocol) so relays and
  /// observers cannot correlate wrap timing with the real message time.
  /// It is therefore NOT when this device received the message -- do not
  /// use it for a "received Xm ago" display or to order messages by
  /// recency. Use [receivedAt] for that.
  final int wrapCreatedAt;

  /// The local wall-clock time (unix seconds) at which this device
  /// decrypted and decoded the wrap -- the real receipt time, safe to use
  /// for recency displays and ordering.
  final int receivedAt;

  const InboundRideDm(
    this.senderPubkey,
    this.payload,
    this.wrapCreatedAt,
    this.receivedAt,
  );
}

/// Sends and receives NIP-17 gift-wrapped [RideDmPayload] messages over a
/// [RelayPool] -- the shared transport behind ride offers (Task 6),
/// handoffs (Task 7), and cancellations (Task 4). Kept separate from the
/// payload codec (`ride_dm_payload.dart`) and from the pure ranking/state
/// logic built on top of it, so each piece stays independently testable.
class RideDmChannel {
  final RelayPool _pool;
  RideDmChannel(this._pool);

  /// Wraps [payload] for [recipientPubHex] and publishes it. Returns the
  /// gift wrap event actually sent (its own `id`/timestamp carry no
  /// meaning to the recipient -- only the decrypted rumor does).
  Future<NostrEvent> send({
    required String senderPrivHex,
    required String recipientPubHex,
    required RideDmPayload payload,
    required int now,
  }) async {
    final wrap = nip17Wrap(
      senderPrivHex: senderPrivHex,
      recipientPubHex: recipientPubHex,
      rumorKind: kRumorKindRideDm,
      content: payload.encode(),
      now: now,
    );
    await _pool.publish(wrap);
    return wrap;
  }

  /// Subscribes to every gift wrap tagged for [myPubHex] and yields each
  /// one that successfully unwraps and decodes with [myPrivHex]. A wrap
  /// that fails to decrypt (addressed to someone else, forwarded anyway
  /// by a misbehaving relay) or fails to decode (a malformed or future,
  /// unrecognized payload) is dropped rather than surfaced -- this is a
  /// routing-layer stream, not a place to report malformed/foreign
  /// traffic to the UI.
  ///
  /// [now] returns the current local wall-clock time in unix seconds and
  /// is called once per successfully decoded wrap to stamp
  /// [InboundRideDm.receivedAt]; it defaults to the real system clock and
  /// only needs overriding in tests that require a deterministic value.
  Stream<InboundRideDm> inbox(
    String myPubHex,
    String myPrivHex, {
    int Function() now = _systemNowSeconds,
  }) {
    final filter = RelayFilter(
      kinds: [kKindGiftWrap],
      tagFilters: {
        '#p': [myPubHex],
      },
    );
    return _pool.subscribe(filter).asyncExpand((wrap) async* {
      try {
        final unwrapped = nip17Unwrap(wrap, myPrivHex);
        if (unwrapped.rumor.kind != kRumorKindRideDm) return;
        final payload = RideDmPayload.decode(unwrapped.rumor.content);
        yield InboundRideDm(
          unwrapped.senderPubkey,
          payload,
          wrap.createdAt,
          now(),
        );
      } on Exception {
        // Not decryptable with our key, or malformed/foreign content;
        // drop rather than surfacing it as an error.
      }
    });
  }
}

/// The default clock for [RideDmChannel.inbox]'s `now` parameter --
/// unix seconds, matching [NostrEvent.createdAt]'s unit.
int _systemNowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
