// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../home/home_status_row.dart' show shortenNpub;

/// A 32-byte Nostr public key, lowercase hex.
///
/// Used to decide whether [shortPubkeyLabel] may bech32-encode a key at all:
/// `hexToNpub` throws on anything else, and the string being formatted here
/// arrives over a relay from a stranger. A malformed key must cost a screen
/// its subtitle, never crash it mid-trip.
final _kPubkeyHexPattern = RegExp(r'^[0-9a-f]{64}$');

/// The counterparty's key in the one form a person can compare by eye.
///
/// The `npub`, abbreviated exactly the way the home sheet abbreviates the
/// user's own key -- so a passenger checking that the person in front of
/// them is the one whose offer they accepted is comparing two strings
/// written the same way. `null` when the key is not encodable, in which case
/// the caller simply has no line to show.
///
/// Shared rather than reimplemented per screen: this abbreviation *is* the
/// app's only notion of "who the other person is" (there are no accounts and
/// no names), so the trip screen and the call screen have to render it
/// identically or the comparison stops working.
String? shortPubkeyLabel(String pubHex) =>
    _kPubkeyHexPattern.hasMatch(pubHex) ? shortenNpub(hexToNpub(pubHex)) : null;
