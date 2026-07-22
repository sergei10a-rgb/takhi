// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void _setChannelHandler(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('createNew persists and load returns same identity', () async {
    final store = InMemoryKeyStore();
    final svc = IdentityService(store);
    final id = await svc.createNew();
    expect(id.pubHex.length, 64);
    expect(id.npub.startsWith('npub1'), isTrue);
    final loaded = await svc.load();
    expect(loaded!.pubHex, id.pubHex);
  });

  test('restore from known mnemonic yields NIP-06 pubkey', () async {
    final svc = IdentityService(InMemoryKeyStore());
    final id = await svc.restore(
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    );
    expect(
      id.privHex,
      '5f29af3b9676180290e77a4efad265c4c2ff28a5302461f73597fda26bb25731',
    );
  });

  test('signOut clears store', () async {
    final store = InMemoryKeyStore();
    final svc = IdentityService(store);
    await svc.createNew();
    await svc.signOut();
    expect(await svc.load(), isNull);
  });

  group('SecureKeyStore', () {
    tearDown(() => _setChannelHandler(null));

    test('write/read/clear round-trip through the platform channel', () async {
      final backing = <String, Object?>{};
      _setChannelHandler((call) async {
        final args = call.arguments as Map<Object?, Object?>;
        switch (call.method) {
          case 'write':
            backing[args['key'] as String] = args['value'];
            return null;
          case 'read':
            return backing[args['key'] as String];
          case 'delete':
            backing.remove(args['key']);
            return null;
          default:
            throw PlatformException(
              code: 'unimplemented',
              message: call.method,
            );
        }
      });

      final store = SecureKeyStore();
      expect(await store.read(), isNull);

      await store.write('deadbeef');
      expect(await store.read(), 'deadbeef');

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('write wraps a platform failure as SecureStoreException', () async {
      _setChannelHandler((call) async {
        throw PlatformException(
          code: 'write_error',
          message: 'keystore unavailable',
        );
      });

      final store = SecureKeyStore();
      await expectLater(
        () => store.write('deadbeef'),
        throwsA(isA<SecureStoreException>()),
      );
    });

    test('read wraps a platform failure as SecureStoreException', () async {
      _setChannelHandler((call) async {
        throw PlatformException(code: 'read_error', message: 'keystore locked');
      });

      final store = SecureKeyStore();
      await expectLater(
        () => store.read(),
        throwsA(isA<SecureStoreException>()),
      );
    });

    test('clear wraps a platform failure as SecureStoreException', () async {
      _setChannelHandler((call) async {
        throw PlatformException(
          code: 'delete_error',
          message: 'keystore corrupt',
        );
      });

      final store = SecureKeyStore();
      await expectLater(
        () => store.clear(),
        throwsA(isA<SecureStoreException>()),
      );
    });
  });
}
