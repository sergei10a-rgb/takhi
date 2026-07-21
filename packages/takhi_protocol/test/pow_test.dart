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

  test(
      'minePow throws PowExhausted when the budget runs out before the '
      'target difficulty is reached', () {
    final base = NostrEvent(
        pubkey: 'ab' * 32, createdAt: 1, kind: 20177, tags: [], content: '');
    // A sha256 hex id has at most 256 leading zero bits (all-zero hash),
    // so difficulty 300 can never be satisfied — this deterministically
    // exhausts the tiny iteration budget below rather than relying on
    // getting unlucky within a probabilistic difficulty target.
    expect(
        () => minePow(base, 300, maxIterations: 5),
        throwsA(isA<PowExhausted>()
            .having((e) => e.difficulty, 'difficulty', 300)));
  });
}
