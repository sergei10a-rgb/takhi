// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('countLeadingZeroBits matches NIP-13 example', () {
    expect(
        countLeadingZeroBits(
            '000000000e9d97a1ab09fc381030b346cdd7a142ad57e6df0b46dc9bef6c7e2d'),
        36);
    expect(countLeadingZeroBits('f'.padRight(64, 'f')), 0);
  });

  test('minePow produces an id with required difficulty', () {
    final base = NostrEvent(
        pubkey: 'ab' * 32, createdAt: 1, kind: 20177, tags: [], content: '');
    final mined = minePow(base, 8);
    expect(countLeadingZeroBits(mined.id!), greaterThanOrEqualTo(8));
    expect(mined.tags.any((t) => t.first == 'nonce'), isTrue);
  });
}
