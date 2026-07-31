// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/widgets/driver_portrait.dart';

/// A real, decodable JPEG -- small enough to be cheap, real enough that
/// `Image.memory` takes the success path rather than the error one.
Uint8List _realJpeg() =>
    img.encodeJpg(img.Image(width: 16, height: 16), quality: 60);

/// Bytes that are emphatically not an image. `Image.memory` cannot know that
/// until it tries to decode, which is the whole point: the fallback has to
/// happen after the frame is already on screen.
Uint8List _garbage() => Uint8List.fromList(List<int>.filled(64, 0x7F));

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('mn'),
  home: Scaffold(body: Center(child: child)),
);

const _portraitSize = 120.0;

void main() {
  testWidgets('a portrait with decodable bytes draws the photograph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        DriverPortrait(
          jpegBytes: _realJpeg(),
          initials: 'БА',
          size: _portraitSize,
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    // The initials mark must not be drawn underneath a photo: two marks for
    // one person is how a stale fallback goes unnoticed.
    expect(find.text('БА'), findsNothing);
  });

  testWidgets('a portrait with no photo falls back to the initials mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const DriverPortrait(
          jpegBytes: null,
          initials: 'БА',
          size: _portraitSize,
        ),
      ),
    );

    expect(find.text('БА'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a portrait whose bytes will not decode falls back to the same '
      'mark rather than an error glyph', (tester) async {
    await tester.pumpWidget(
      _host(
        DriverPortrait(
          jpegBytes: _garbage(),
          initials: 'БА',
          size: _portraitSize,
        ),
      ),
    );
    // The decode failure surfaces asynchronously, through the image stream.
    await tester.pumpAndSettle();
    // Swallow the decode error the image stream reports -- it is the
    // condition under test, not an unexpected failure.
    tester.takeException();

    expect(find.text('БА'), findsOneWidget);
  });

  testWidgets('a portrait with no photo offers no tap', (tester) async {
    await tester.pumpWidget(
      _host(
        const DriverPortrait(
          jpegBytes: null,
          initials: 'БА',
          size: _portraitSize,
          enlargeable: true,
        ),
      ),
    );

    // Nothing to enlarge, so nothing may look enlargeable: a control that
    // does nothing on tap is worse than no control.
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('tapping an enlargeable portrait opens the photo full screen, '
      'said plainly to be unverified', (tester) async {
    await tester.pumpWidget(
      _host(
        DriverPortrait(
          jpegBytes: _realJpeg(),
          initials: 'БА',
          size: _portraitSize,
          enlargeable: true,
        ),
      ),
    );

    await tester.tap(find.byType(DriverPortrait));
    await tester.pumpAndSettle();

    expect(find.text('Баталгаажаагүй зураг'), findsOneWidget);
    expect(
      find.textContaining('Тэр царай яг энэ жолоочийнх мөн эсэхийг'),
      findsOneWidget,
    );
  });

  testWidgets('the full-screen photo can be left again', (tester) async {
    await tester.pumpWidget(
      _host(
        DriverPortrait(
          jpegBytes: _realJpeg(),
          initials: 'БА',
          size: _portraitSize,
          enlargeable: true,
        ),
      ),
    );

    await tester.tap(find.byType(DriverPortrait));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Хаах'));
    await tester.pumpAndSettle();

    expect(find.text('Баталгаажаагүй зураг'), findsNothing);
    expect(find.byType(DriverPortrait), findsOneWidget);
  });
}
