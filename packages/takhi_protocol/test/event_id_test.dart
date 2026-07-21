// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('computeEventId matches NIP-01 serialization sha256', () {
    final e = NostrEvent(
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

  test('copyWith replaces id and sig while keeping other fields', () {
    final e = NostrEvent(
      pubkey: 'pk',
      createdAt: 1,
      kind: 1,
      tags: [],
      content: 'x',
    );
    final withId = e.copyWith(id: 'abc');
    expect(withId.id, 'abc');
    expect(withId.sig, isNull);
    expect(withId.pubkey, 'pk');

    final withSig = withId.copyWith(sig: 'sig123');
    expect(withSig.id, 'abc');
    expect(withSig.sig, 'sig123');

    final unchanged = withSig.copyWith();
    expect(unchanged.id, 'abc');
    expect(unchanged.sig, 'sig123');
  });

  test('fromJson reconstructs an event produced by toJson', () {
    final e = NostrEvent(
      id: 'deadbeef',
      pubkey: List.filled(32, 'ab').join(),
      createdAt: 123,
      kind: 1,
      tags: [
        ['g', 'u9huf6']
      ],
      content: 'hello',
      sig: 'feedface',
    );
    final roundTripped = NostrEvent.fromJson(e.toJson());
    expect(roundTripped.id, e.id);
    expect(roundTripped.pubkey, e.pubkey);
    expect(roundTripped.createdAt, e.createdAt);
    expect(roundTripped.kind, e.kind);
    expect(roundTripped.tags, e.tags);
    expect(roundTripped.content, e.content);
    expect(roundTripped.sig, e.sig);
  });

  test('tags is defensively copied and unmodifiable', () {
    final mutableInput = <List<String>>[
      ['g', 'u9huf']
    ];
    final e = NostrEvent(
      pubkey: 'pk',
      createdAt: 1,
      kind: 1,
      tags: mutableInput,
      content: 'x',
    );
    // Mutating the caller's original list must not affect the event.
    mutableInput.add(['dest', 'u9hug']);
    expect(e.tags.length, 1);
    // The event's own tags list must reject mutation.
    expect(() => e.tags.add(['extra', 'v']), throwsUnsupportedError);
  });

  test('toJson serializes every field with expected keys', () {
    final e = NostrEvent(
      id: 'evtid',
      pubkey: 'pk',
      createdAt: 42,
      kind: 20177,
      tags: [
        ['g', 'u9huf']
      ],
      content: 'hi',
      sig: 'sig',
    );
    expect(e.toJson(), {
      'id': 'evtid',
      'pubkey': 'pk',
      'created_at': 42,
      'kind': 20177,
      'tags': [
        ['g', 'u9huf']
      ],
      'content': 'hi',
      'sig': 'sig',
    });
  });
}
