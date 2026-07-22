// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/payment/driver_qr_store.dart';

void main() {
  late Directory tempDir;
  late FileDriverQrStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('takhi_qr_test');
    store = FileDriverQrStore(() async => tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('load returns null when nothing has been saved', () async {
    expect(await store.load(), isNull);
  });

  test('save then load round-trips the exact bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await store.save(bytes);
    final loaded = await store.load();
    expect(loaded, bytes);
  });

  test('save overwrites a previously saved image', () async {
    await store.save(Uint8List.fromList([1]));
    await store.save(Uint8List.fromList([9, 9]));
    expect(await store.load(), Uint8List.fromList([9, 9]));
  });

  test('clear removes the saved image', () async {
    await store.save(Uint8List.fromList([1, 2, 3]));
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('clear is a no-op when nothing was saved', () async {
    await store.clear();
    expect(await store.load(), isNull);
  });
}
