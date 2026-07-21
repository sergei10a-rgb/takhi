// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  const hexPub =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  const npub =
      'npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6';

  test('hex -> npub matches NIP-19 example', () {
    expect(hexToNpub(hexPub), npub);
  });
  test('npub -> hex round-trips', () {
    expect(npubToHex(npub), hexPub);
  });
  test('npubToHex rejects nsec prefix', () {
    expect(() => npubToHex('nsec1abc'), throwsArgumentError);
  });

  test('hex -> nsec -> hex round-trips', () {
    const privHex =
        '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
    final nsec = hexToNsec(privHex);
    expect(nsec, startsWith('nsec1'));
    expect(nsecToHex(nsec), privHex);
  });

  test(
      'npubToHex rejects a real (checksum-valid) nsec via the hrp check, '
      'not a bech32 decode failure', () {
    // Unlike 'nsec1abc' above (too short to even pass bech32 checksum
    // validation, so it never reaches the hrp comparison), this value is a
    // genuine, fully valid bech32-encoded nsec. It must be rejected because
    // its human-readable part is 'nsec', not 'npub' — i.e. the `d.hrp !=
    // hrp` branch in `_decode`, not the bech32.decode try/catch above it.
    final validNsec = hexToNsec(hexPub);
    expect(() => npubToHex(validNsec), throwsArgumentError);
  });
}
