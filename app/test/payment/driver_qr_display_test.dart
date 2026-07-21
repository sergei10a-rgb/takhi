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

/// Same shape as [_FakeDriverQrStore], plus a call counter on [load] --
/// used to prove `DriverQrDisplay` reads the file at most once per mount
/// (via `driverQrBytesProvider`) instead of once per rebuild.
class _CountingDriverQrStore implements DriverQrStore {
  _CountingDriverQrStore([this._bytes]);

  Uint8List? _bytes;
  int loadCount = 0;

  @override
  Future<void> save(Uint8List pngBytes) async => _bytes = pngBytes;

  @override
  Future<Uint8List?> load() async {
    loadCount++;
    return _bytes;
  }

  @override
  Future<void> clear() async => _bytes = null;
}

/// Wraps `DriverQrDisplay` with a button that forces a rebuild of a brand
/// new (deliberately non-`const`) `DriverQrDisplay` instance -- both real
/// call sites (`ActiveTripView._DoneView`, `TaximeterPage._FinishedStep`)
/// happen to use `const DriverQrDisplay()`, which Flutter's own const-widget
/// diffing can skip rebuilding entirely; this harness exists specifically
/// to exercise the case where `build()` really does run again.
class _RebuildHarness extends StatefulWidget {
  const _RebuildHarness();

  @override
  State<_RebuildHarness> createState() => _RebuildHarnessState();
}

class _RebuildHarnessState extends State<_RebuildHarness> {
  int _rebuilds = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // ignore: prefer_const_constructors -- must be a fresh instance each
      // rebuild to actually exercise DriverQrDisplay.build() running again.
      DriverQrDisplay(),
      TextButton(
        onPressed: () => setState(() => _rebuilds++),
        child: const Text('rebuild'),
      ),
    ],
  );
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

  testWidgets(
    'rebuilding after the QR has already loaded reuses the cached bytes -- '
    'no flicker back to the "not set" hint, no re-reading the file',
    (tester) async {
      final store = _CountingDriverQrStore(_pngBytes);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [driverQrStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('mn'),
            home: const Scaffold(body: _RebuildHarness()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(store.loadCount, 1);

      // Each tap sets state on the harness, handing `DriverQrDisplay` a
      // brand new (non-const) widget instance every time -- the pre-fix
      // `FutureBuilder<Uint8List?>(future: ref.read(...).load(), ...)`
      // would have created a fresh `Future` and re-read the file on each
      // of these, flashing back to the "not set" hint for a frame.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('rebuild'));
        await tester.pump();
      }

      expect(find.byType(Image), findsOneWidget);
      expect(
        find.text('Та банкны QR-аа хараахан оруулаагүй байна'),
        findsNothing,
      );
      expect(store.loadCount, 1);
    },
  );
}
