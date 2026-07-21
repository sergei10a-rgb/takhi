// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/fallback_decision.dart';

void main() {
  test('keeps trying while WebRTC has not timed out yet', () {
    expect(
      decideFallbackAction(
        webrtcConnected: false,
        webrtcTimedOut: false,
        counterpartyPhoneKnown: true,
        phoneShareEnabled: true,
      ),
      CallFallbackAction.keepTryingWebrtc,
    );
  });

  test('keeps "trying" once connected, regardless of timeout flag', () {
    expect(
      decideFallbackAction(
        webrtcConnected: true,
        webrtcTimedOut: true,
        counterpartyPhoneKnown: true,
        phoneShareEnabled: true,
      ),
      CallFallbackAction.keepTryingWebrtc,
    );
  });

  test('offers a phone call once timed out, when a number was shared and '
      'the toggle is on', () {
    expect(
      decideFallbackAction(
        webrtcConnected: false,
        webrtcTimedOut: true,
        counterpartyPhoneKnown: true,
        phoneShareEnabled: true,
      ),
      CallFallbackAction.offerPhoneCall,
    );
  });

  test('falls straight to a voice message when no phone number is known', () {
    expect(
      decideFallbackAction(
        webrtcConnected: false,
        webrtcTimedOut: true,
        counterpartyPhoneKnown: false,
        phoneShareEnabled: true,
      ),
      CallFallbackAction.offerVoiceMessage,
    );
  });

  test('falls straight to a voice message when phone sharing is disabled '
      'even if a number happens to be known', () {
    expect(
      decideFallbackAction(
        webrtcConnected: false,
        webrtcTimedOut: true,
        counterpartyPhoneKnown: true,
        phoneShareEnabled: false,
      ),
      CallFallbackAction.offerVoiceMessage,
    );
  });
}
