// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

class TakhiColors {
  static const gold = Color(0xFFC99A3C);
  static const goldDeep = Color(0xFFA67C28);
  static const ink = Color(0xFF1C1A16);
  static const steppe = Color(0xFF2E6E5E);
  static const paper = Color(0xFFF4F1E9);
  static const sand = Color(0xFFE7DEC9);

  /// The error/warning red used on the light theme's paper surface --
  /// matches [takhiTheme]'s own `ColorScheme.error` for `Brightness.light`.
  /// ~6.29:1 contrast against [paper] (WCAG AA for normal text).
  ///
  /// Named here so onboarding's inline error texts and the seed-backup
  /// warning banner (previously three separate `Color(0x...)` literals, two
  /// of them accidentally different shades of the same intent) reference a
  /// single token instead of re-hardcoding a hex value outside this file
  /// (design-system audit, Task 10 Step 2).
  ///
  /// Do NOT reference this constant directly from widget code -- it is only
  /// correct against the light surface. Widgets must read
  /// `Theme.of(context).colorScheme.error` instead, which resolves to this
  /// value in light mode and to [errorDark] in dark mode.
  static const error = Color(0xFF9E3327);

  /// The error/warning red used on the dark theme's surface. [error] itself
  /// only clears ~2.34:1 against the dark surface (0xFF211E19) -- well below
  /// the 3:1 minimum even for large text -- because a single fixed red
  /// cannot be well-tuned for both a near-black and a near-white surface at
  /// once. This lighter, more saturated red clears ~6.2:1 against the dark
  /// surface instead (WCAG AA for normal text).
  static const errorDark = Color(0xFFE18579);
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
    error: dark ? TakhiColors.errorDark : TakhiColors.error,
    onError: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'NotoSans', // bundled: assets/fonts/ (Cyrillic-complete)
  );
}
