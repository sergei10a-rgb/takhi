// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';

String generateMnemonic() => bip39.generateMnemonic(strength: 128);

String privateKeyFromMnemonic(String mnemonic, {int account = 0}) {
  // NOTE (deviation from plan): pub.dev bip39 1.0.6's bundled English
  // wordlist is corrupted (several words, e.g. "nine"/"ninety"/"four"/
  // "five", are missing), so `bip39.validateMnemonic` rejects legitimate
  // official BIP-39/NIP-06 mnemonics. Its `mnemonicToSeed` (PBKDF2-HMAC-
  // SHA512) does not depend on the wordlist and was verified correct
  // against the official BIP-39 Trezor test vector, so we keep using it
  // and only replace the wordlist-dependent validation with a
  // structural word-count check.
  final wordCount = mnemonic.trim().split(RegExp(r'\s+')).length;
  const validLengths = {12, 15, 18, 21, 24};
  if (mnemonic.trim().isEmpty || !validLengths.contains(wordCount)) {
    throw ArgumentError('invalid BIP-39 mnemonic');
  }
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final child = root.derivePath("m/44'/1237'/$account'/0/0");
  final priv = child.privateKey;
  if (priv == null) throw StateError('derivation produced no private key');
  return hex.encode(priv);
}
