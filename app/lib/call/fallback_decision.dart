// SPDX-License-Identifier: AGPL-3.0-or-later

/// The next rung of the calling fallback chain (spec §7.3): keep trying
/// WebRTC (P2P direct or helper-relayed -- both are the same "WebRTC
/// attempt" from this decision's point of view, see `ice_servers.dart`'s
/// doc comment), or drop to a plain phone call, or drop straight to a
/// short voice message. `offerHelperRelay` is deliberately NOT a distinct
/// value here: STUN vs. TURN-via-helper is resolved *inside* one WebRTC
/// connection attempt by the ICE agent itself (RFC 8445), not by this
/// app retrying with different servers -- so there is exactly one
/// external app-level decision point (did WebRTC connect before timing
/// out?), not three.
enum CallFallbackAction { keepTryingWebrtc, offerPhoneCall, offerVoiceMessage }

/// Pure and total -- every input combination maps to exactly one action,
/// so the whole chain's ordering is covered by ordinary unit tests with
/// no WebRTC/network dependency. `CallService` (Task 7) calls this once
/// per relevant state change (a connection-state update, or its own
/// timeout firing) rather than polling it.
CallFallbackAction decideFallbackAction({
  required bool webrtcConnected,
  required bool webrtcTimedOut,
  required bool counterpartyPhoneKnown,
  required bool phoneShareEnabled,
}) {
  if (webrtcConnected || !webrtcTimedOut) {
    return CallFallbackAction.keepTryingWebrtc;
  }
  if (counterpartyPhoneKnown && phoneShareEnabled) {
    return CallFallbackAction.offerPhoneCall;
  }
  return CallFallbackAction.offerVoiceMessage;
}
