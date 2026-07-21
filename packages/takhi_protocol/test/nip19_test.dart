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
}
