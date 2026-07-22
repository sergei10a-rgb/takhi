// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';

String generateMnemonic() => bip39.generateMnemonic(strength: 128);

String privateKeyFromMnemonic(String mnemonic, {int account = 0}) {
  // pub.dev bip39 1.0.6's bundled English wordlist was independently
  // diffed word-for-word (all 2048 entries, same order) against the
  // audited @scure/bip39 canonical English wordlist and is identical —
  // it is not corrupted. `bip39.validateMnemonic` therefore performs
  // full BIP-39 validation (wordlist membership + checksum) correctly
  // and must be used instead of a structural word-count check, which
  // would silently accept mistyped or non-BIP-39 word lists and derive
  // a different, wrong private key with no warning.
  if (!bip39.validateMnemonic(mnemonic)) {
    throw ArgumentError('invalid BIP-39 mnemonic');
  }
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final child = root.derivePath("m/44'/1237'/$account'/0/0");
  final priv = child.privateKey;
  if (priv == null) throw StateError('derivation produced no private key');
  return hex.encode(priv);
}
