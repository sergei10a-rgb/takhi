// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import 'share_link.dart';

/// One active "аялал хуваалцах" session: a throwaway keypair minted the
/// moment the user taps "share", used only to receive a *second* copy of
/// this device's own live-location pings (wired in `ActiveTripView`) and
/// to build the link handed to `share_plus`. Never persisted -- a fresh
/// [ShareSession] every time sharing is (re-)started, so an old link
/// naturally stops receiving new pings once the trip's live-location
/// stream ends (`ActiveTripView`'s tracking step disposes, per Plan 4).
class ShareSession {
  final KeyPair shareKeyPair;
  ShareSession() : shareKeyPair = generateKeyPair();

  String urlFor(String tripId, List<String> relayUrls) => buildShareUrl(
    baseUrl: kShareBaseUrl,
    shareKeyHex: shareKeyPair.privateHex,
    tripId: tripId,
    relayUrls: relayUrls,
  );
}
