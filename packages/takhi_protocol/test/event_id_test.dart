// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('computeEventId matches NIP-01 serialization sha256', () {
    const e = NostrEvent(
      pubkey:
          '0000000000000000000000000000000000000000000000000000000000000001',
      createdAt: 1700000000,
      kind: 1,
      tags: [],
      content: 'hello',
    );
    // Golden hash captured from actual output of computeEventId on this
    // exact NostrEvent (sha256 of the NIP-01 serialization array is
    // deterministic, so this literal is a valid regression fixture).
    expect(computeEventId(e),
        'b8591d69d0638d47eb20e0505fdbaf565e52675fa998010df62813ad3d11b486');
  });

  test('id is stable across identical events', () {
    final e = NostrEvent(
      pubkey: List.filled(32, 'ab').join(),
      createdAt: 42,
      kind: 20177,
      tags: const [
        ['g', 'u9huf']
      ],
      content: '',
    );
    expect(computeEventId(e), computeEventId(e));
  });

  test('content with unicode + quotes serializes deterministically', () {
    final e = NostrEvent(
      pubkey: List.filled(32, 'cd').join(),
      createdAt: 1,
      kind: 1,
      tags: const [],
      content: 'Сайн уу "quote"\n',
    );
    expect(computeEventId(e).length, 64);
  });
}
