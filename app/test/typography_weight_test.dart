// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';

/// The family `takhi_theme.dart` sets as `ThemeData.fontFamily`, and the one
/// file `pubspec.yaml` binds to it.
const _kFamily = 'NotoSans';

/// Read off disk rather than through `rootBundle`: this test exists to say
/// something about *the bundled file*, so it has to open that file rather
/// than whatever the test harness would resolve the asset name to.
const _kAssetPath = 'assets/fonts/NotoSans-Regular.ttf';

/// Cyrillic, because that is the script the weight has to hold up in --
/// a Latin probe would pass over a font with no Cyrillic bold at all.
const _kProbe = 'Хаашаа явах вэ?';

/// Width of [_kProbe] set at [weight], everything else held constant.
///
/// Width is the observable that separates a real weight axis from a fake
/// one: heavier glyphs are wider. Comparing rendered widths is therefore a
/// direct measurement of whether the bundled font can actually produce the
/// weights the type scale asks for.
double _widthAt(FontWeight weight) {
  final painter = TextPainter(
    text: TextSpan(
      text: _kProbe,
      style: TextStyle(fontFamily: _kFamily, fontSize: 48, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File(_kAssetPath).readAsBytesSync();
    await (FontLoader(
      _kFamily,
    )..addFont(Future.value(bytes.buffer.asByteData()))).load();
  });

  test('the bundled font renders every weight the type scale asks for, so '
      'the heading hierarchy is real on a device and not only on paper', () {
    final body = _widthAt(TakhiType.body.fontWeight!);
    final heading = _widthAt(TakhiType.heading.fontWeight!);
    final display = _widthAt(TakhiType.display.fontWeight!);

    // Strictly increasing, and asserted pairwise rather than as one chain,
    // so a failure names which step collapsed. Two ways this breaks, both
    // silent in review and both invisible until someone looks at a phone:
    // swapping in a static single-weight file flattens all three to one
    // number, and synthetic bold -- which the engine falls back to for a
    // font that cannot do the weight -- is one on/off setting, so it makes
    // `heading` and `display` identical while leaving `body` behind.
    expect(
      heading,
      greaterThan(body),
      reason:
          'w${TakhiType.heading.fontWeight!.value} does not set any '
          'heavier than w${TakhiType.body.fontWeight!.value}',
    );
    expect(
      display,
      greaterThan(heading),
      reason:
          'w${TakhiType.display.fontWeight!.value} does not set any '
          'heavier than w${TakhiType.heading.fontWeight!.value} -- the '
          'display line is the "very heavy" one the direction is built on',
    );
  });

  test('the type scale keeps a real weight jump between its tiers, not just '
      'a size one', () {
    // The widths above only prove the *font* can do it. This proves the
    // scale still asks: a heading dropped to the body weight would keep
    // every layout test passing while quietly costing the hierarchy.
    expect(
      TakhiType.display.fontWeight!.value,
      greaterThan(TakhiType.heading.fontWeight!.value),
    );
    expect(
      TakhiType.heading.fontWeight!.value,
      greaterThan(TakhiType.body.fontWeight!.value),
    );
  });
}
