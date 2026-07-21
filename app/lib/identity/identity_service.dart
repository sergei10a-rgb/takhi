// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

class Identity {
  final String privHex;
  final String pubHex;
  const Identity(this.privHex, this.pubHex);
  String get npub => hexToNpub(pubHex);
}

abstract class KeyStore {
  Future<void> write(String privHex);
  Future<String?> read();
  Future<void> clear();
}

class InMemoryKeyStore implements KeyStore {
  String? _v;
  @override
  Future<void> write(String p) async => _v = p;
  @override
  Future<String?> read() async => _v;
  @override
  Future<void> clear() async => _v = null;
}

class SecureKeyStore implements KeyStore {
  static const _k = 'takhi_priv';
  final _s = const FlutterSecureStorage();
  @override
  Future<void> write(String p) => _s.write(key: _k, value: p);
  @override
  Future<String?> read() => _s.read(key: _k);
  @override
  Future<void> clear() => _s.delete(key: _k);
}

class IdentityService {
  final KeyStore _store;
  IdentityService(this._store);

  Future<Identity> createNew() async {
    final (_, id) = await createNewWithMnemonic();
    return id;
  }

  Future<(String, Identity)> createNewWithMnemonic() async {
    final mnemonic = generateMnemonic();
    final id = _fromMnemonic(mnemonic);
    await _store.write(id.privHex);
    return (mnemonic, id);
  }

  Future<Identity> restore(String mnemonic) async {
    final id = _fromMnemonic(mnemonic.trim());
    await _store.write(id.privHex);
    return id;
  }

  Future<Identity?> load() async {
    final priv = await _store.read();
    if (priv == null) return null;
    return Identity(priv, pubkeyFromPrivate(priv));
  }

  Future<void> signOut() => _store.clear();

  Identity _fromMnemonic(String m) {
    final priv = privateKeyFromMnemonic(m);
    return Identity(priv, pubkeyFromPrivate(priv));
  }
}
