// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';

/// `#RRGGBB`, the spelling both `pubspec.yaml` and the generated Android
/// themes use.
String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// Every `color:` / `color_dark:` value inside `pubspec.yaml`'s
/// `flutter_native_splash:` block. There are two of each -- the top-level
/// pair and the `android_12:` pair -- and they are independent settings, so
/// both are collected rather than just the first.
List<String> _pubspecSplashColors(String key) {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final start = lines.indexWhere((l) => l.startsWith('flutter_native_splash:'));
  expect(start, isNot(-1), reason: 'pubspec.yaml has no splash config at all');

  final pattern = RegExp('^\\s+$key:\\s*"?(#[0-9A-Fa-f]{6})"?\\s*\$');
  final found = <String>[];
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    // A new top-level key ends the block; blank and comment lines inside
    // it do not.
    final leavesBlock =
        line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#');
    if (leavesBlock) break;
    final match = pattern.firstMatch(line);
    if (match != null) found.add(match.group(1)!.toUpperCase());
  }
  return found;
}

/// The `windowSplashScreenBackground` out of a generated Android 12+ theme.
String _generatedSplashColor(String valuesDir) {
  final file = File('android/app/src/main/res/$valuesDir/styles.xml');
  expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
  final match = RegExp(
    r'windowSplashScreenBackground">(#[0-9A-Fa-f]{6})<',
  ).firstMatch(file.readAsStringSync());
  expect(
    match,
    isNotNull,
    reason: '${file.path} declares no windowSplashScreenBackground',
  );
  return match!.group(1)!.toUpperCase();
}

void main() {
  // The native splash is the first thing on screen and Flutter's own first
  // frame is the second. If the two grounds are not the same colour the
  // handover *flashes*, and it does so on every single launch. That is
  // exactly what shipped: `color_dark` was `#1C1A16` (`TakhiColors.ink`,
  // the silhouette colour) while the app's dark surface is `#211E19`.
  //
  // Reading the real files rather than restating the hexes is the point:
  // this fails if `pubspec.yaml` changes, if the theme changes, or if
  // somebody edits `pubspec.yaml` and forgets to re-run
  // `dart run flutter_native_splash:create`.
  test('flutter_native_splash paints the same light ground as the Flutter '
      'light theme', () {
    final surface = _hex(takhiTheme(Brightness.light).colorScheme.surface);
    final declared = _pubspecSplashColors('color');

    expect(
      declared,
      hasLength(2),
      reason: 'expected a top-level and an android_12 "color:"',
    );
    expect(declared, everyElement(surface));
  });

  test('flutter_native_splash paints the same dark ground as the Flutter '
      'dark theme', () {
    final surface = _hex(takhiTheme(Brightness.dark).colorScheme.surface);
    final declared = _pubspecSplashColors('color_dark');

    expect(
      declared,
      hasLength(2),
      reason: 'expected a top-level and an android_12 "color_dark:"',
    );
    expect(declared, everyElement(surface));
  });

  test('the generated Android 12 splash themes carry the colours pubspec '
      'declares (i.e. flutter_native_splash:create was actually re-run)', () {
    expect(
      _generatedSplashColor('values-v31'),
      _hex(takhiTheme(Brightness.light).colorScheme.surface),
    );
    expect(
      _generatedSplashColor('values-night-v31'),
      _hex(takhiTheme(Brightness.dark).colorScheme.surface),
    );
  });
}
