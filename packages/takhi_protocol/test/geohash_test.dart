// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('encodes Ulaanbaatar center to precision 6', () {
    // UB Sukhbaatar Square ~ 47.9186, 106.9176
    final h = geohashEncode(47.9186, 106.9176, precision: 6);
    expect(h.length, 6);
    // decode center is within one cell (~1.2km lat / 0.6km lon)
    final c = geohashDecodeCenter(h);
    expect((c.lat - 47.9186).abs() < 0.02, isTrue);
    expect((c.lon - 106.9176).abs() < 0.02, isTrue);
  });

  test('neighbors returns 8 distinct adjacent cells', () {
    final n = geohashNeighbors('u9huf6');
    expect(n.length, 8);
    expect(n.toSet().length, 8);
    expect(n.contains('u9huf6'), isFalse);
  });

  test(
      'neighbors returns 8 distinct self-excluding cells at low precision '
      '(regression: jitter approach previously self-included at precision '
      '1-4)', () {
    for (var p = 2; p <= 6; p++) {
      final h = geohashEncode(47.9186, 106.9176, precision: p);
      final n = geohashNeighbors(h);
      expect(n.length, 8, reason: 'precision $p hash $h neighbors $n');
      expect(n.toSet().length, 8, reason: 'precision $p hash $h');
      expect(n.contains(h), isFalse, reason: 'precision $p hash $h');
    }
  });

  test(
      'neighbors wraps across the antimeridian instead of self-including '
      '(regression: lon ~179.99 previously returned only 6 neighbors '
      'including itself)', () {
    final h = geohashEncode(0.0, 179.99, precision: 6);
    final n = geohashNeighbors(h);
    expect(n.length, 8);
    expect(n.toSet().length, 8);
    expect(n.contains(h), isFalse);
  });
}
