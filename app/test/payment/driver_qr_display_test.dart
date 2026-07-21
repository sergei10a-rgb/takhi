// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/payment/driver_qr_capture_page.dart';
import 'package:takhi/payment/driver_qr_display.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';

/// A real (if tiny) 1x1 transparent PNG -- `DriverQrDisplay` renders saved
/// bytes through `Image.memory`, which actually decodes them, so arbitrary
/// non-image bytes would fail the test with an unrelated image-codec error.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

/// In-memory [DriverQrStore] test double, same shape as the one in
/// `driver_qr_capture_page_test.dart` -- kept file-local rather than
/// shared, matching how `_FailingKeyStore` in `onboarding_widget_test.dart`
/// is not shared either.
class _FakeDriverQrStore implements DriverQrStore {
  _FakeDriverQrStore({this.initial});

  Uint8List? initial;

  @override
  Future<void> save(Uint8List pngBytes) async => initial = pngBytes;

  @override
  Future<Uint8List?> load() async => initial;

  @override
  Future<void> clear() async => initial = null;
}

Future<void> pumpDisplay(WidgetTester tester, DriverQrStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [driverQrStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const Scaffold(body: DriverQrDisplay()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows the "not set" hint and a link to DriverQrCapturePage when no '
    'QR has been saved yet',
    (tester) async {
      await pumpDisplay(tester, _FakeDriverQrStore());

      expect(
        find.text('Та банкны QR-аа хараахан оруулаагүй байна'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.text('Зураг сонгох'));
      await tester.pumpAndSettle();
      expect(find.byType(DriverQrCapturePage), findsOneWidget);
    },
  );

  testWidgets('renders the saved QR image bytes when one exists', (
    tester,
  ) async {
    await pumpDisplay(tester, _FakeDriverQrStore(initial: _pngBytes));

    expect(
      find.text('Та банкны QR-аа хараахан оруулаагүй байна'),
      findsNothing,
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, _pngBytes);
  });
}
