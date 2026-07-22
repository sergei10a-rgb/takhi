// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('NIP-06 official vector derives expected private key', () {
    // Official NIP-06 spec vector 1 (nostr-protocol/nips, 06.md).
    const mnemonic = 'leader monkey parrot ring guide accident before fence '
        'cannon height naive bean';
    final priv = privateKeyFromMnemonic(mnemonic);
    expect(priv,
        '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a');
  });

  test('generateMnemonic yields 12 words that round-trip to a valid key', () {
    final m = generateMnemonic();
    expect(m.split(' ').length, 12);
    expect(privateKeyFromMnemonic(m).length, 64);
  });

  test('rejects a mnemonic with a mistyped word', () {
    // Same as the official vector but with the last word typoed
    // ("bean" -> "beach"): must fail checksum validation, not silently
    // derive a different key.
    const typoMnemonic =
        'leader monkey parrot ring guide accident before fence '
        'cannon height naive beach';
    expect(() => privateKeyFromMnemonic(typoMnemonic),
        throwsA(isA<ArgumentError>()));
  });

  test('rejects words that are not in the BIP-39 wordlist', () {
    const notWordlist =
        'foo bar baz qux quux corge grault garply waldo fred plugh xyzzy';
    expect(() => privateKeyFromMnemonic(notWordlist),
        throwsA(isA<ArgumentError>()));
  });
}
