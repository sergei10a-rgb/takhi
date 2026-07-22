// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/call/call_engine.dart';

void main() {
  test('IceCandidateData carries candidate/sdpMid/sdpMLineIndex verbatim', () {
    const c = IceCandidateData('candidate:1 1 UDP ...', 'audio', 0);
    expect(c.candidate, 'candidate:1 1 UDP ...');
    expect(c.sdpMid, 'audio');
    expect(c.sdpMLineIndex, 0);
  });

  test('LocalSessionDescription carries sdp/type verbatim', () {
    const d = LocalSessionDescription('v=0\r\n...', 'offer');
    expect(d.sdp, 'v=0\r\n...');
    expect(d.type, 'offer');
  });
}
