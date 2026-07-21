// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('derives known x-only pubkey from private key (BIP-340 vector)', () {
    // BIP-340 test vector index 1
    const priv =
        'B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF';
    final pub = pubkeyFromPrivate(priv.toLowerCase());
    expect(
      pub,
      'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    );
  });

  test('generateKeyPair from fixed randomness is deterministic', () {
    final rnd = List<int>.filled(32, 7);
    final kp = generateKeyPair(rnd);
    expect(kp.privateHex.length, 64);
    expect(kp.publicHex.length, 64);
    expect(kp.publicHex, pubkeyFromPrivate(kp.privateHex));
  });
}
