// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('encodes and decodes back near the same point', () {
    final code = plusCodeEncode(47.9186, 106.9176);
    expect(code.contains('+'), isTrue);
    final c = plusCodeDecodeCenter(code);
    expect((c.lat - 47.9186).abs() < 0.001, isTrue);
    expect((c.lon - 106.9176).abs() < 0.001, isTrue);
  });
}
