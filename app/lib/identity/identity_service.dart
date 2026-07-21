// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/services.dart' show PlatformException;
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

/// Thrown when the native secure-storage backend (Android Keystore, iOS/macOS
/// Keychain, etc.) fails to service a read/write/delete — e.g. a corrupted
/// entry, denied OS-level access, or an unsupported platform. Wraps the
/// original [PlatformException] so callers depend on a stable, storage-agnostic
/// error type instead of a raw platform-channel exception.
class SecureStoreException implements Exception {
  final String message;
  final Object cause;
  const SecureStoreException(this.message, this.cause);

  @override
  String toString() => 'SecureStoreException: $message ($cause)';
}

class SecureKeyStore implements KeyStore {
  static const _k = 'takhi_priv';
  final _s = const FlutterSecureStorage();

  @override
  Future<void> write(String p) async {
    try {
      await _s.write(key: _k, value: p);
    } on PlatformException catch (e) {
      throw SecureStoreException(
        'failed to write identity to secure storage',
        e,
      );
    }
  }

  @override
  Future<String?> read() async {
    try {
      return await _s.read(key: _k);
    } on PlatformException catch (e) {
      throw SecureStoreException(
        'failed to read identity from secure storage',
        e,
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _k);
    } on PlatformException catch (e) {
      throw SecureStoreException(
        'failed to clear identity from secure storage',
        e,
      );
    }
  }
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
