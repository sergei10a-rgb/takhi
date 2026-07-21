import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';

void main() {
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
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about');
    expect(id.privHex,
        '5f29af3b9676180290e77a4efad265c4c2ff28a5302461f73597fda26bb25731');
  });

  test('signOut clears store', () async {
    final store = InMemoryKeyStore();
    final svc = IdentityService(store);
    await svc.createNew();
    await svc.signOut();
    expect(await svc.load(), isNull);
  });
}
