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

  /// The sheet a dialog is painted on, light theme. Material 3 resolves
  /// `ColorScheme.surfaceContainerHigh` here, and this app builds its
  /// [ColorScheme] by hand -- every role it does not name falls back to
  /// `surface`, so before this token existed a dialog sat on the very same
  /// paper as the page behind it with nothing but a shadow between them.
  /// A hair lighter than [paper] lifts the sheet onto its own plane
  /// without introducing a second neutral into the palette.
  static const dialogPaper = Color(0xFFFBF8F1);

  /// The sheet a dialog is painted on, dark theme -- [ink] lifted the same
  /// way, since in dark rooms "raised" reads as lighter, not darker.
  static const dialogInk = Color(0xFF2B2721);
}

/// How loud a dialog's action is allowed to be.
///
/// Dialog buttons are the one place in the app where *which button looks
/// louder* is a safety decision rather than a styling one, so a call site
/// picks a named role and the mapping to actual colours lives here, in the
/// single file that is allowed to know hex values. The rule the roles
/// encode:
///
/// * an action the user deliberately reached for gets [primary];
/// * an action a *reflex* can reach -- the "leave" half of a back-guard
///   dialog, which the back gesture itself opened -- gets [caution], so the
///   emphasis stays on the safe side;
/// * only irreversible loss of user data gets [destructive].
enum DialogActionTone {
  /// The quiet way out: plain label text on the dialog sheet, in the
  /// surface's own foreground colour. The default for "Цуцлах" beside an
  /// emphasised confirm.
  neutral,

  /// A damaging answer that must nonetheless stay *quieter* than the safe
  /// one beside it -- "Гарах" on a back-guard dialog. Warning-coloured
  /// label text, no fill: visible, legible, not inviting.
  caution,

  /// The emphasised answer, solid brand fill. Used for the step the user
  /// came here to take, and for the *safe* half of a back-guard dialog.
  primary,

  /// The emphasised destructive answer, solid error fill. Reserved for
  /// irreversible loss -- overwriting a private key, and nothing else.
  destructive,
}

/// The label and fill colours [tone] paints with under [scheme].
///
/// `background` is `null` for the two text-only tones, which sit directly
/// on the dialog sheet -- so a caller measuring contrast falls back to
/// `ThemeData.dialogTheme.backgroundColor` for those, and to the returned
/// fill for the others. Both pairs are asserted against WCAG AA, in both
/// brightnesses, in `theme_test.dart`.
({Color foreground, Color? background}) dialogActionColors(
  DialogActionTone tone,
  ColorScheme scheme,
) => switch (tone) {
  // Never `scheme.primary` (the Material default for a `TextButton`
  // foreground): brand gold on the light sheet is 2.28:1.
  DialogActionTone.neutral => (foreground: scheme.onSurface, background: null),
  DialogActionTone.caution => (foreground: scheme.error, background: null),
  DialogActionTone.primary => (
    foreground: TakhiColors.ink,
    background: scheme.primary,
  ),
  DialogActionTone.destructive => (
    foreground: scheme.onError,
    background: scheme.error,
  ),
};

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
    // Per-brightness for the same reason `error` is: white reads at
    // 7.10:1 on the light theme's deep red but only 2.68:1 on the dark
    // theme's light red, which left the dark "overwrite my private key"
    // button -- the one filled-error button in the app -- unreadable.
    onError: dark ? TakhiColors.ink : Colors.white,
  );
  // Built first so the dialog text styles below can inherit the bundled
  // Cyrillic font: a bare `TextStyle` handed to `DialogThemeData` carries
  // no family and would silently fall back to the platform default.
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'NotoSans', // bundled: assets/fonts/ (Cyrillic-complete)
  );
  return base.copyWith(
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? TakhiColors.dialogInk : TakhiColors.dialogPaper,
      // Material 3 would otherwise blend `primary` into the sheet by an
      // amount that depends on elevation, quietly moving every contrast
      // ratio `theme_test.dart` measures away from the value it asserts.
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black,
      // Darker than the M3 default `black54`, so the sheet reads as the
      // only live thing on screen while a decision is pending.
      barrierColor: Colors.black.withValues(alpha: dark ? 0.68 : 0.55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      // The M3 default of 40 costs 80dp of width on every phone; on a
      // 320dp screen that is a quarter of the sheet, and the action row is
      // exactly what runs out of room first in Mongolian.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
        fontSize: 15,
        height: 1.45,
      ),
    ),
  );
}
