// SPDX-License-Identifier: AGPL-3.0-or-later
import 'event.dart';

class PowExhausted implements Exception {
  final int difficulty;
  PowExhausted(this.difficulty);
  @override
  String toString() => 'PoW difficulty $difficulty not found in budget';
}

int countLeadingZeroBits(String hexId) {
  var count = 0;
  for (var i = 0; i < hexId.length; i++) {
    final nibble = int.parse(hexId[i], radix: 16);
    if (nibble == 0) {
      count += 4;
    } else {
      count += _clz4(nibble);
      break;
    }
  }
  return count;
}

int _clz4(int nibble) {
  if (nibble >= 8) return 0;
  if (nibble >= 4) return 1;
  if (nibble >= 2) return 2;
  return 3;
}

NostrEvent minePow(NostrEvent base, int difficulty,
    {int maxIterations = 1 << 22}) {
  final otherTags =
      base.tags.where((t) => t.isEmpty || t.first != 'nonce').toList();
  for (var nonce = 0; nonce < maxIterations; nonce++) {
    final tags = [
      ...otherTags,
      ['nonce', nonce.toString(), difficulty.toString()],
    ];
    final candidate = NostrEvent(
      pubkey: base.pubkey,
      createdAt: base.createdAt,
      kind: base.kind,
      tags: tags,
      content: base.content,
    );
    final id = computeEventId(candidate);
    if (countLeadingZeroBits(id) >= difficulty) {
      return candidate.copyWith(id: id);
    }
  }
  throw PowExhausted(difficulty);
}
