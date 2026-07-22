// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/safety/emergency_contact_store.dart';

void main() {
  test('loadPhone is null until savePhone is called', () async {
    final store = InMemoryEmergencyContactStore();
    expect(await store.loadPhone(), isNull);
    await store.savePhone('99887766');
    expect(await store.loadPhone(), '99887766');
  });
}
