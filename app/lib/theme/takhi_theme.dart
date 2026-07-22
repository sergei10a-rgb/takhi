// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

class TakhiColors {
  static const gold = Color(0xFFC99A3C);
  static const goldDeep = Color(0xFFA67C28);
  static const ink = Color(0xFF1C1A16);
  static const steppe = Color(0xFF2E6E5E);
  static const paper = Color(0xFFF4F1E9);
  static const sand = Color(0xFFE7DEC9);

  /// The one error/warning red used app-wide -- matches [takhiTheme]'s own
  /// `ColorScheme.error` exactly. Named here so onboarding's inline error
  /// texts and the seed-backup warning banner (previously three separate
  /// `Color(0x...)` literals, two of them accidentally different shades of
  /// the same intent) reference a single token instead of re-hardcoding a
  /// hex value outside this file (design-system audit, Task 10 Step 2).
  static const error = Color(0xFF9E3327);
}

ThemeData takhiTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: TakhiColors.gold,
    onPrimary: TakhiColors.ink,
    secondary: TakhiColors.steppe,
    onSecondary: Colors.white,
    surface: dark ? const Color(0xFF211E19) : TakhiColors.paper,
    onSurface: dark ? TakhiColors.paper : TakhiColors.ink,
    error: TakhiColors.error,
    onError: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'NotoSans', // bundled: assets/fonts/ (Cyrillic-complete)
  );
}
