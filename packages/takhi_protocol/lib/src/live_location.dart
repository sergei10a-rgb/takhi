// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'event.dart';
import 'keys.dart';
import 'nip44.dart';
import 'sign.dart';
import 'takhi_events.dart' show kKindLiveLocation;

/// Builds a signed, NIP-44-encrypted live-location ping (kind 20178, spec
/// §6/§7.1 step 5): a lightweight position heartbeat sent every 5-10s while
/// a trip is in progress, addressed to exactly one recipient via the
/// public `p` tag.
///
/// Deliberately NOT wrapped through NIP-17/NIP-59 (`nip17Wrap`) like
/// offer/handoff/cancel DMs — those exist to hide the sender's identity and
/// randomize timing for messages exchanged before two strangers have
/// committed to a trip. By the time live location starts, both pubkeys are
/// already mutually known (the passenger picked this driver from a
/// reputation-visible offer, spec §7.1 step 3), so gift-wrap's per-message
/// ephemeral-key signing cost buys no privacy here, only battery. A plain
/// NIP-44-encrypted ephemeral event (the `2xxxx` kind range: relays don't
/// persist it, only relay it to currently-connected subscribers) is the
/// lighter-weight fit spec §6's data-model table calls for.
///
/// Only [lat]/[lon]/[tripId] are encrypted into `content`; the `p`/`d`/
/// `expiration` tags are plaintext relay-routing metadata, same tiering as
/// every other takhi event.
NostrEvent buildLiveLocationEvent({
  required String senderPrivHex,
  required String recipientPubHex,
  required int now,
  required String tripId,
  required double lat,
  required double lon,
  int expirySeconds = 30,
  List<int>? nonce32,
  List<int>? auxRand,
}) {
  final payload = jsonEncode({'tripId': tripId, 'lat': lat, 'lon': lon});
  final encrypted = nip44Encrypt(
    payload,
    senderPrivHex,
    recipientPubHex,
    nonce32: nonce32,
  );
  final unsigned = NostrEvent(
    pubkey: pubkeyFromPrivate(senderPrivHex),
    createdAt: now,
    kind: kKindLiveLocation,
    tags: [
      ['p', recipientPubHex],
      ['d', tripId],
      ['expiration', (now + expirySeconds).toString()],
    ],
    content: encrypted,
  );
  return signEvent(unsigned, senderPrivHex, auxRand: auxRand);
}

/// A live-location ping recovered from [parseLiveLocationEvent]: the
/// sender's pubkey (read straight off the signed event — no seal/unwrap
/// layer needed, unlike a NIP-17 DM) plus the decrypted position.
class LiveLocation {
  final String senderPubkey;
  final String tripId;
  final double lat;
  final double lon;
  const LiveLocation({
    required this.senderPubkey,
    required this.tripId,
    required this.lat,
    required this.lon,
  });
}

/// Reverses [buildLiveLocationEvent]: checks [e]'s kind, decrypts `content`
/// with [recipientPrivHex], and parses the `{tripId, lat, lon}` payload.
///
/// Throws [FormatException] for the wrong kind or a malformed decrypted
/// payload. Throws the underlying [Exception] (from [nip44Decrypt]) if [e]
/// cannot be decrypted with [recipientPrivHex] at all — e.g. it was
/// addressed to someone else. Does not itself call [verifyEvent] — every
/// event reaching application code through `RelayPool.subscribe` (Task 3)
/// is already signature-verified there, matching `parseRideRequest`/
/// `parseTripReceipt`'s existing convention of not re-checking it.
LiveLocation parseLiveLocationEvent(NostrEvent e, String recipientPrivHex) {
  if (e.kind != kKindLiveLocation) {
    throw FormatException('not a live location event (kind ${e.kind})');
  }
  final decrypted = nip44Decrypt(e.content, recipientPrivHex, e.pubkey);
  final decoded = jsonDecode(decrypted);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('live location payload is not a JSON object');
  }
  final tripId = decoded['tripId'];
  final lat = decoded['lat'];
  final lon = decoded['lon'];
  if (tripId is! String) {
    throw FormatException("live location payload: 'tripId' must be a String");
  }
  if (lat is! num) {
    throw FormatException("live location payload: 'lat' must be a number");
  }
  if (lon is! num) {
    throw FormatException("live location payload: 'lon' must be a number");
  }
  return LiveLocation(
    senderPubkey: e.pubkey,
    tripId: tripId,
    lat: lat.toDouble(),
    lon: lon.toDouble(),
  );
}
