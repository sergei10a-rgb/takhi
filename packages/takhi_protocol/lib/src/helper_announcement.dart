// SPDX-License-Identifier: AGPL-3.0-or-later
import 'event.dart';
import 'takhi_events.dart' show kKindHelper;

/// Builds an unsigned kind-30178 "туслагч" (helper) announcement: a
/// volunteer telling the network "I'm running a blind TURN relay at
/// host:port, here's how long this announcement is good for" (spec §6/
/// §7.3-①). Anyone may call this — including a non-Flutter script, since
/// PROTOCOL.md documents the exact wire shape (§4.4) independently of this
/// implementation — and anyone may announce as many or as few helpers as
/// they like; the author of this app runs none of them (Global
/// Constraints). Unsigned, matching `buildRideRequest`/`buildTripReceipt`'s
/// existing convention: the caller signs with `signEvent` before
/// publishing.
NostrEvent buildHelperAnnouncement({
  required String pubkey,
  required int now,
  required String helperId,
  required String host,
  required int port,
  String credential = '',
  int expirySeconds = 3600,
}) {
  return NostrEvent(
    pubkey: pubkey,
    createdAt: now,
    kind: kKindHelper,
    tags: [
      ['d', helperId],
      ['host', host],
      ['port', port.toString()],
      ['expiration', (now + expirySeconds).toString()],
    ],
    content: credential,
  );
}

/// A helper announcement recovered from [parseHelperAnnouncement]. TURN
/// `credential` travels as plaintext `content` -- deliberately not
/// NIP-44-encrypted, since the whole point of a kind-30178 announcement is
/// that *any* stranger's client can discover and use the relay (spec
/// §7.3-①: "хэн ч зарлаж, хэн ч ашиглана"). A helper operator who wants
/// the credential to rotate or stay private to a smaller circle should
/// re-announce more often (`expirySeconds`) or omit `credential` entirely
/// and run an open/unauthenticated TURN relay instead -- both are valid,
/// neither is this schema's concern.
class HelperAnnouncement {
  final String helperId;
  final String host;
  final int port;
  final String credential;
  final String announcerPubkey;
  final int expiration;
  final int createdAt;

  const HelperAnnouncement({
    required this.helperId,
    required this.host,
    required this.port,
    required this.credential,
    required this.announcerPubkey,
    required this.expiration,
    required this.createdAt,
  });
}

/// Reverses [buildHelperAnnouncement]. Throws [FormatException] for the
/// wrong kind or any missing required tag -- mirrors
/// `parseRideRequest`/`parseTripReceipt`'s existing `tag()` helper
/// pattern exactly, including not re-verifying the signature (every event
/// reaching application code through `RelayPool.subscribe` is already
/// signature-verified there).
HelperAnnouncement parseHelperAnnouncement(NostrEvent e) {
  if (e.kind != kKindHelper) {
    throw FormatException('not a helper announcement (kind ${e.kind})');
  }
  String tag(String k) {
    final t = e.tags.firstWhere((x) => x.first == k,
        orElse: () => throw FormatException('missing $k'));
    return t[1];
  }

  return HelperAnnouncement(
    helperId: tag('d'),
    host: tag('host'),
    port: int.parse(tag('port')),
    credential: e.content,
    announcerPubkey: e.pubkey,
    expiration: int.parse(tag('expiration')),
    createdAt: e.createdAt,
  );
}
