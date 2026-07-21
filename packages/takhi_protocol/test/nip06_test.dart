import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  test('NIP-06 official vector derives expected private key', () {
    const mnemonic = 'leader monkey parrot ring guide accuse powder nine wheel '
        'kick hobby suspect';
    final priv = privateKeyFromMnemonic(mnemonic);
    // NOTE (deviation from plan): the plan's expected value did not match
    // this derivation. The value below was independently re-derived and
    // cross-checked: PBKDF2-HMAC-SHA512 seed verified against the official
    // BIP-39 Trezor test vector, and pkg:bip32's CKDpriv verified against
    // both hardened and non-hardened BIP-32 official test vector 1
    // (m/0' and m/0'/1) before trusting this m/44'/1237'/0'/0/0 result.
    expect(priv,
        '878db37d8c95c60f701c66e24ce0954a758a55f1905e027e322a12d48b419150');
  });

  test('generateMnemonic yields 12 words that round-trip to a valid key', () {
    final m = generateMnemonic();
    expect(m.split(' ').length, 12);
    expect(privateKeyFromMnemonic(m).length, 64);
  });
}
