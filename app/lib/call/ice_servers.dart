// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

/// Public STUN servers, used for NAT address discovery only (spec §7.3-①:
/// "STUN нь зөвхөн хаяг-олох stateless үйлчилгээ"). No media or signaling
/// ever passes through these -- they only tell each side its own
/// public-facing address/port so the ICE agent can attempt a direct path.
/// This is an editable list, not author infrastructure (Global
/// Constraints): every URL here is a well-known public STUN service
/// already used by countless WebRTC apps, none of it operated by this
/// project. The exact default set is an open protocol question (see this
/// plan's Self-Review) -- Google's and Cloudflare's are widely mirrored
/// and known to work from Mongolian ISPs as of this writing, which is why
/// they're the seed default, not because they're specially endorsed.
const List<String> kDefaultStunServers = [
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
  'stun:stun.cloudflare.com:3478',
];

/// Builds the `iceServers` list `flutter_webrtc`'s `RTCConfiguration`
/// expects: [stunServers] first, then one `turn:` entry per [helpers] --
/// volunteer-run blind relays (spec §6/§7.3-①), each built from its
/// announced host/port, with `credential`/`username` included only when
/// the announcement actually published one (an open/unauthenticated relay
/// omits both, which flutter_webrtc treats as "no TURN auth needed").
///
/// P2P-direct and TURN-relayed connections are deliberately NOT modeled
/// as two separate app-level attempts here: this is the *entire* app-side
/// involvement in that choice. Once this list is handed to
/// `RTCPeerConnection`, WebRTC's own ICE agent gathers host (direct),
/// server-reflexive (via STUN), and relay (via TURN) candidates together
/// and picks whichever pair actually connects end to end, automatically
/// preferring a direct path when one exists -- that preference and
/// fallback behavior is standard ICE (RFC 8445), not something this
/// project implements. Pure and synchronous, so this whole merge is
/// unit-testable with zero network/WebRTC dependency; `CallService`
/// (Task 7) is responsible for keeping [helpers] fresh via
/// `HelperDirectoryService`.
List<Map<String, dynamic>> buildIceServers({
  List<String> stunServers = kDefaultStunServers,
  List<HelperAnnouncement> helpers = const [],
}) {
  return [
    {'urls': stunServers},
    for (final h in helpers)
      {
        'urls': ['turn:${h.host}:${h.port}'],
        if (h.credential.isNotEmpty) 'credential': h.credential,
        if (h.credential.isNotEmpty) 'username': h.helperId,
      },
  ];
}
