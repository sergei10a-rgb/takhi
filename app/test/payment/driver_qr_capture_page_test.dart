// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/payment/driver_qr_capture_page.dart';
import 'package:takhi/payment/driver_qr_store.dart';
import 'package:takhi/payment/payment_providers.dart';

/// A real (if tiny) 1x1 transparent PNG. `DriverQrCapturePage` renders the
/// picked bytes through `Image.memory`, which actually decodes them --
/// arbitrary non-image bytes throw inside the image codec and fail the
/// test with an unrelated "Invalid image data" error, so picked/saved
/// bytes in this file must be genuine image data.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

/// An in-memory [DriverQrStore] test double so widget tests never touch the
/// real filesystem, and can be told to fail the next `save` on demand to
/// exercise `_save`'s error path -- the same shape as `_FailingKeyStore` in
/// `app/test/onboarding_widget_test.dart`.
class _FakeDriverQrStore implements DriverQrStore {
  Uint8List? saved;
  bool failNextSave = false;

  @override
  Future<void> save(Uint8List pngBytes) async {
    if (failNextSave) {
      throw const FileSystemException('disk full', 'driver_qr.bin');
    }
    saved = pngBytes;
  }

  @override
  Future<Uint8List?> load() async => saved;

  @override
  Future<void> clear() async => saved = null;
}

/// A minimal [ImagePickerPlatform] fake that hands back canned bytes for a
/// gallery pick. `image_picker` has no built-in method-channel test mock
/// (unlike `flutter_secure_storage`), but its platform-interface seam is
/// designed to be swapped in tests exactly like this.
class _FakeImagePickerPlatform extends ImagePickerPlatform {
  Uint8List? nextPick;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    final bytes = nextPick;
    if (bytes == null) return null;
    return XFile.fromData(bytes, name: 'qr.png');
  }
}

void main() {
  late _FakeDriverQrStore store;
  late _FakeImagePickerPlatform picker;

  setUp(() {
    store = _FakeDriverQrStore();
    picker = _FakeImagePickerPlatform();
    ImagePickerPlatform.instance = picker;
  });

  // Mirrors the real navigation shape (`DriverQrDisplay` pushes
  // `DriverQrCapturePage` via `Navigator.push`) so that `Navigator.pop()`
  // inside `_save()` has a route to pop back to, instead of being the sole
  // (unpoppable) route in the stack.
  Future<void> pumpPushed(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [driverQrStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DriverQrCapturePage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'save button reads "Хадгалах" and is disabled before any image is '
    'picked -- never claims "QR saved" up front',
    (tester) async {
      await pumpPushed(tester);

      expect(find.text('Хадгалах'), findsOneWidget);
      expect(find.text('QR хадгалагдлаа'), findsNothing);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      // Tapping the disabled button does nothing -- no save was attempted.
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();
      expect(store.saved, isNull);
    },
  );

  testWidgets(
    'picking an image enables the save button; saving persists the bytes, '
    'shows the confirmation, and pops back',
    (tester) async {
      picker.nextPick = _pngBytes;
      await pumpPushed(tester);

      await tester.tap(find.text('Зураг сонгох'));
      await tester.pumpAndSettle();

      final enabledButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(enabledButton.onPressed, isNotNull);

      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      expect(store.saved, _pngBytes);
      expect(find.text('QR хадгалагдлаа'), findsOneWidget);
      expect(find.byType(DriverQrCapturePage), findsNothing);
    },
  );

  testWidgets(
    'a save failure surfaces an error SnackBar and leaves the page open, '
    'instead of crashing or falsely confirming success',
    (tester) async {
      picker.nextPick = _pngBytes;
      store.failNextSave = true;
      await pumpPushed(tester);

      await tester.tap(find.text('Зураг сонгох'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Хадгалах'));
      await tester.pumpAndSettle();

      expect(
        find.text('QR хадгалж чадсангүй. Дахин оролдоно уу.'),
        findsOneWidget,
      );
      expect(find.text('QR хадгалагдлаа'), findsNothing);
      expect(find.byType(DriverQrCapturePage), findsOneWidget);
    },
  );
}
