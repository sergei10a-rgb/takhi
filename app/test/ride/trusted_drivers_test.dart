// SPDX-License-Identifier: AGPL-3.0-or-later
//
// `computeReputation` has taken a `viewerTrusted` set since it was written,
// and until v0.4.0 every call site passed `const {}`. The whole trust half
// of the offer ranking sat there doing nothing — an algorithm with no input
// is not a feature, it is a plan.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/trusted_drivers_store.dart';

void main() {
  test('a vouch survives being read back', () async {
    final store = InMemoryTrustedDriversStore();
    await store.trust('abc123');

    expect(await store.load(), {'abc123'});
  });

  test('vouching twice says the same thing once', () async {
    final store = InMemoryTrustedDriversStore()
      ..trust('abc123')
      ..trust('abc123');
    await Future<void>.delayed(Duration.zero);

    expect((await store.load()).length, 1);
  });

  test('a vouch can be taken back', () async {
    final store = InMemoryTrustedDriversStore();
    await store.trust('abc123');
    await store.untrust('abc123');

    expect(await store.load(), isEmpty);
  });

  test('an empty pubkey is not a vouch', () async {
    // Guards the path where a counterparty key never arrived: an empty
    // string in the trusted set would match nothing, but it would also sit
    // in a driver's list of vouches forever looking like somebody.
    final store = InMemoryTrustedDriversStore();
    await store.trust('');

    expect(await store.load(), isEmpty);
  });

  test('the set starts empty, which is every passenger on their first ride',
      () async {
    expect(await InMemoryTrustedDriversStore().load(), isEmpty);
  });
}
