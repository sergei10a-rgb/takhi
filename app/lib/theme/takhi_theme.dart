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

// ---------------------------------------------------------------------------
// Design tokens
//
// Everything below this line is the vocabulary screens are built from. The
// rule the whole layer exists to enforce: a screen never writes a raw number
// or a raw colour. It names a token, and the token is the only thing that
// knows the value. `design_system_audit_test.dart` already forbids
// `Color(0x...)` outside this file; the scales below extend that discipline
// to radii, spacing, type and motion, which drift far more quietly than
// colour does because nobody notices a 13 among the 12s.
// ---------------------------------------------------------------------------

/// Corner radii, one shape per role.
///
/// The scale is deliberately short. Every rounded thing in the app is one of
/// five shapes, and a screen that needs a sixth is a screen that has invented
/// a component the design system does not have yet -- which is a conversation,
/// not a `borderRadius: BorderRadius.circular(13)`.
abstract final class TakhiRadius {
  /// The two top corners of a sheet floating over the map. Large enough to
  /// read as a separate plane from the full-bleed map behind it.
  static const sheet = 18.0;

  /// A content card sitting *inside* a sheet -- always tighter than the
  /// sheet that contains it, so nested corners never look concentric.
  static const card = 14.0;

  /// The rounded square behind a category icon. The squircle-ish middle of
  /// the scale: clearly not a circle, clearly not a box.
  static const tile = 11.0;

  /// A small rectangular badge or tag -- a tariff marker overlaid on a card,
  /// a count. Distinct from `InfoChip`, which is a pill; use this only when
  /// the shape must stay rectangular.
  static const chip = 8.0;

  /// Fully round: buttons, pill fields, chips, avatars. Any value past half
  /// the shorter side gives a capsule, so this is a sentinel rather than a
  /// measurement.
  static const pill = 999.0;

  /// [sheet], applied to the top two corners only -- the bottom of a sheet
  /// runs off the bottom of the screen and must not be rounded there.
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(sheet));

  /// [card], all four corners.
  static const cardAll = BorderRadius.all(Radius.circular(card));

  /// [tile], all four corners.
  static const tileAll = BorderRadius.all(Radius.circular(tile));

  /// [chip], all four corners.
  static const chipAll = BorderRadius.all(Radius.circular(chip));

  /// [pill], all four corners.
  static const pillAll = BorderRadius.all(Radius.circular(pill));
}

/// The spacing scale: multiples of 4, and nothing between them.
///
/// Named rather than numeric at the call site so that "tighten the gap under
/// the heading" is one step down the scale everywhere it appears, instead of
/// a 16 that became a 14 on one screen and a 15 on another.
abstract final class TakhiSpace {
  /// 4 -- hairline gaps: icon to its own label, chip internals.
  static const xxs = 4.0;

  /// 8 -- inside a component: leading dot to text, chip to chip.
  static const xs = 8.0;

  /// 12 -- between siblings in a list, vertical padding inside a field.
  static const sm = 12.0;

  /// 16 -- the default gutter. Horizontal padding of a sheet's content.
  static const md = 16.0;

  /// 20 -- between related groups inside one sheet.
  static const lg = 20.0;

  /// 24 -- between unrelated groups; a sheet's own outer padding.
  static const xl = 24.0;

  /// 32 -- section break. The largest step; anything bigger is a layout
  /// decision (a spacer, a `Flexible`), not spacing.
  static const xxl = 32.0;
}

/// Hit-target floors.
abstract final class TakhiTouch {
  /// The smallest square any tappable thing is allowed to occupy, whatever
  /// its painted size. 48 rather than the 44 the accessibility guidelines
  /// floor at, because this app is also used one-handed in a moving car --
  /// and because 48 is what the rest of the app's dialogs already use.
  ///
  /// A component whose *visual* is smaller (a 40dp circle button, a 34dp
  /// category tile) pads its gesture area out to this, it does not grow the
  /// artwork.
  static const minTarget = 48.0;
}

/// Line thicknesses that are not borders.
abstract final class TakhiStroke {
  /// Arc width of a `CircularProgressIndicator` anywhere in the app.
  ///
  /// One value because there is one kind of spinner. Before this existed the
  /// two places that draw one had drifted to 2.4 and 2.2 -- a difference
  /// nobody could see and nobody had chosen, which is exactly the shape of
  /// drift a token prevents.
  static const indicator = 2.4;
}

/// Durations and curves for micro-interactions.
///
/// The whole range lives inside 150-300ms on purpose: below 150 a transition
/// reads as a glitch, above 300 it reads as lag. Nothing in this app animates
/// for decoration -- motion exists to show where a thing came from.
abstract final class TakhiMotion {
  /// 150ms -- state changes the finger is still touching: press, ripple,
  /// selection, chip toggle.
  static const fast = Duration(milliseconds: 150);

  /// 220ms -- something appearing or moving under its own power: a sheet
  /// growing, a row sliding in.
  static const normal = Duration(milliseconds: 220);

  /// 300ms -- the largest move on screen, used sparingly.
  static const slow = Duration(milliseconds: 300);

  /// Things arriving: fast at first, settling at the end.
  static const enter = Curves.easeOutCubic;

  /// Things leaving: they may accelerate away, nobody is watching the end.
  static const exit = Curves.easeInCubic;

  /// Things moving from one place to another while staying on screen.
  static const emphasized = Curves.easeInOutCubic;
}

/// The type scale: seven roles, each with its own size *and* weight.
///
/// Deliberately colourless. A [TextStyle] here says how big and how heavy;
/// what colour it takes depends on which surface it lands on, and that is
/// [TakhiSurfaces]' job. Call sites compose:
/// `TakhiType.title.copyWith(color: surfaces.onSheet)`.
///
/// One family (bundled NotoSans, Cyrillic-complete) carries all seven --
/// separation comes from size and weight contrast, which is why no two roles
/// are allowed to share a size.
abstract final class TakhiType {
  /// 52/w800 -- the brand name on the first screen, and nowhere else.
  ///
  /// Kept as its own role rather than snapped down to [display]: onboarding is
  /// the one screen with nothing to do but say what the app is, and a word set
  /// at 52 reads as a mark while the same word at 28 reads as a heading. It is
  /// listed here, with that reason, precisely so the next screen that wants
  /// "just a bit bigger" has to justify itself the same way instead of typing
  /// a number.
  /// Tracking is *positive* here, alone in this scale: every other role
  /// tightens as it grows, because a heading is text. This one is a wordmark,
  /// and letters set apart read as a mark rather than as a sentence.
  static const hero = TextStyle(
    fontSize: 52,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 3,
  );

  /// 28/w800 -- the one very heavy line at the top of a sheet. Tight
  /// tracking keeps a long Cyrillic heading from sprawling.
  static const display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.4,
  );

  /// 22/w700 -- a heading inside a sheet, the top half of a [SectionHeading].
  static const heading = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.2,
  );

  /// 16/w600 -- the primary line of a row: an address, a person's name, a
  /// button label.
  static const title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// 15/w400 -- running text. 1.45 line-height because Cyrillic sets denser
  /// than Latin and needs the air.
  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// 13/w400 -- the grey second line under a heading or an address.
  static const support = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// 12/w600 -- a category tile's caption, a chip's text. Slightly open
  /// tracking; these are short and often set beside an icon.
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  /// 11/w600 -- the small grey label sitting *above* a value, and uppercase
  /// eyebrows. +0.6 tracking is not optional: uppercase Cyrillic set tight
  /// runs together into an unreadable band.
  static const micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.6,
  );

  /// 12/w400, fixed pitch -- a report whose columns only line up in a
  /// monospace: today the GPS diagnostic, and nothing that a passenger or a
  /// driver reads while working.
  ///
  /// Deliberately small and deliberately outside the rest of this scale. A
  /// diagnostic is read once, on a bug hunt, by someone who wants the whole
  /// table on one screen; setting it at [support] would wrap every row and
  /// turn aligned columns into prose. Any screen tempted to reach for this
  /// for ordinary text should reach for [body] instead — a fixed pitch is a
  /// statement that the alignment matters more than the reading, which is
  /// almost never true.
  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier'],
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// 20/w700, tabular -- money, distance, time inline in a row.
  ///
  /// Tabular figures are a correctness requirement rather than a refinement:
  /// with proportional digits a live fare re-flows on every tick, and the
  /// number a driver glances at moves under their eye.
  static const numeric = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.15,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// 48/w800, tabular -- a large figure inside a sheet: a settled total, a
  /// confirmed fare.
  ///
  /// `letterSpacing` is deliberately absent, not merely unset. The bundled
  /// NotoSans is a variable font, and along its `wght` axis the glyphs gain
  /// ink far faster than they gain advance width -- at w800 a tightening of
  /// even -1 was enough to slide `₮` into the digit before it, because that
  /// glyph carries ink right up to its left edge. Negative tracking on this
  /// face is a collision waiting for the right pair of characters; tabular
  /// figures already give the alignment it was reaching for.
  static const numericDisplay = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w800,
    height: 1.05,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// 76/w800, tabular -- the running taximeter, and nothing else.
  ///
  /// Sized for the one reading taken at arm's length, in daylight, by someone
  /// who must look back at the road: this figure is the entire purpose of that
  /// screen, so it gets the room the map was taking. Every caller wraps it in
  /// a `FittedBox(scaleDown)`, which is what keeps a six-figure fare inside
  /// the sheet instead of clipping it.
  static const meterHeadline = TextStyle(
    fontSize: 76,
    fontWeight: FontWeight.w800,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Resolves a [TakhiType] token for use as a `ButtonStyle.textStyle`.
///
/// The tokens deliberately carry no `fontFamily`: it is set once on
/// [ThemeData], so one line governs the whole app. Every [Text] widget merges
/// its style onto the inherited one, so that works everywhere -- except in
/// `ButtonStyle.textStyle`, which *replaces* the inherited style rather than
/// merging onto it. A bare token passed to `TextButton.styleFrom` therefore
/// drops the family, and the label falls back to whatever the platform hands
/// back.
///
/// On a phone that fallback has Cyrillic and the bug is invisible. Under
/// `flutter_test` it does not, so the label renders as a row of empty boxes --
/// which is exactly how this was found: «Түр зогсоох» came out as ▯▯▯ ▯▯▯▯▯▯▯
/// on a screenshot of the running meter, beside correctly-drawn text that had
/// reached the screen through a plain [Text].
TextStyle takhiButtonTextStyle(BuildContext context, TextStyle token) =>
    (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).merge(token);

/// The surface ladder, resolved per brightness.
///
/// The structural language is a full-bleed map with a raised sheet floating
/// on it and sunken fields inside that sheet -- three planes that only work
/// if each is visibly its own. The two brightnesses are *not* inversions of
/// each other, and that is the whole reason this is a class with two
/// hand-built instances rather than a set of `dark ? a : b` expressions:
///
/// * light: `canvas` (warm paper) -> `sheet` (lighter) -> `field` (darker
///   than the sheet, so an input reads as a well cut into it);
/// * dark: `canvas` (deep ink) -> `sheet` (lighter) -> `field` (lighter
///   still). Inverting the light ladder would make a dark field *darker*
///   than the canvas showing around the sheet, and the input would look
///   like a hole punched through to the map.
///
/// The same asymmetry governs depth: light separates planes with a soft
/// shadow, dark separates them with a hairline, because a shadow cast on a
/// near-black canvas is not visible at any opacity worth using.
@immutable
class TakhiSurfaces {
  /// The screen's ground -- what the map, or a plain page, is painted on.
  /// Matches `ThemeData.scaffoldBackgroundColor` in both brightnesses.
  final Color canvas;

  /// The raised plane: bottom sheets, cards, floating circular buttons.
  final Color sheet;

  /// The recessed plane inside a sheet: pill input fills, tappable row
  /// backgrounds.
  final Color field;

  /// Primary text and icons on [sheet], [field] and [canvas] alike -- all
  /// three clear WCAG AA against it, asserted in `theme_tokens_test.dart`.
  final Color onSheet;

  /// Supporting text: the small label above a value, a field's placeholder,
  /// the grey second line of a heading. Still AA on all three surfaces --
  /// "secondary" is a hierarchy decision, never a legibility discount.
  final Color muted;

  /// The 1px boundary drawn around raised surfaces. Semi-transparent, so it
  /// composites over whatever it lands on; in dark it is doing the work
  /// [sheetShadow] does in light and is correspondingly stronger.
  final Color hairline;

  /// Shadow cast by a sheet or a card. Empty in dark.
  final List<BoxShadow> sheetShadow;

  /// Shadow cast by a small floating control over the map. Tighter and
  /// softer than [sheetShadow] -- a 40dp circle with a sheet-sized shadow
  /// looks like it is hovering a foot above the screen.
  final List<BoxShadow> floatShadow;

  const TakhiSurfaces._({
    required this.canvas,
    required this.sheet,
    required this.field,
    required this.onSheet,
    required this.muted,
    required this.hairline,
    required this.sheetShadow,
    required this.floatShadow,
  });

  /// Warm paper ground, near-white sheet, sand-grey wells.
  static const light = TakhiSurfaces._(
    canvas: TakhiColors.paper,
    sheet: Color(0xFFFCFAF5),
    field: Color(0xFFEAE5DA),
    onSheet: TakhiColors.ink,
    // 6.33:1 on the sheet, 5.26:1 on a field fill.
    muted: Color(0xFF635C51),
    hairline: Color(0x141C1A16), // ink @ 8%
    sheetShadow: [
      BoxShadow(
        color: Color(0x1A1C1A16),
        blurRadius: 24,
        offset: Offset(0, -2),
      ),
      BoxShadow(color: Color(0x0F1C1A16), blurRadius: 4, offset: Offset(0, -1)),
    ],
    floatShadow: [
      BoxShadow(color: Color(0x1F1C1A16), blurRadius: 12, offset: Offset(0, 2)),
    ],
  );

  /// Deep ink ground, each plane above it a step lighter.
  static const dark = TakhiSurfaces._(
    canvas: Color(0xFF211E19),
    // The same value the dialog sheet already uses, so a bottom sheet and a
    // dialog sit on one plane instead of two that are nearly but not quite
    // the same colour.
    sheet: TakhiColors.dialogInk,
    field: Color(0xFF37322A),
    onSheet: TakhiColors.paper,
    // 6.46:1 on the sheet, 5.53:1 on a field fill.
    muted: Color(0xFFB3AA9B),
    // Stronger than the light hairline because it replaces the shadow
    // outright: paper @ 22%.
    hairline: Color(0x38F4F1E9),
    sheetShadow: [],
    floatShadow: [],
  );

  /// The ladder for [brightness].
  static TakhiSurfaces forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The ladder for the theme in scope. The normal way a widget reads these.
  static TakhiSurfaces of(BuildContext context) =>
      forBrightness(Theme.of(context).brightness);
}

/// The colour families a category tile, an info chip or a leading dot can
/// take.
///
/// Semantic, not decorative: an accent says what kind of thing this is, so
/// the same service keeps the same colour on every screen it appears on.
/// Screens pick a member; the hex pair behind it is [takhiAccentColors]'
/// business and moves with brightness.
enum TakhiAccent {
  /// Brand. The default action, the primary service, the user's own things.
  gold,

  /// Live, confirmed, in progress, on its way. The steppe green's family.
  steppe,

  /// Informational and navigational -- scheduled, intercity, a saved place.
  sky,

  /// Attention without alarm: delivery, cargo, something with a caveat.
  /// Alarm proper is `ColorScheme.error`, not this.
  clay,

  /// No colour opinion. A metadata chip, a disabled tile, an avatar
  /// fallback.
  neutral,
}

/// The soft ground and the deep foreground [accent] paints with under
/// [brightness].
///
/// The pair always ships together because that is the only way the ratio
/// between them can be guaranteed -- every combination is asserted at >= 4.5:1
/// in `theme_tokens_test.dart`, in both brightnesses.
///
/// This is also how the brand gold survives contact with an icon: flat
/// `TakhiColors.gold` on a light surface is 2.28:1 and may never carry a
/// glyph, so the gold accent darkens the foreground and lightens the ground
/// until the pair clears AA, rather than dropping gold from the icon set.
({Color tint, Color onTint}) takhiAccentColors(
  TakhiAccent accent,
  Brightness brightness,
) {
  final dark = brightness == Brightness.dark;
  return switch (accent) {
    TakhiAccent.gold =>
      dark
          ? (tint: const Color(0xFF463618), onTint: const Color(0xFFEFC978))
          : (tint: const Color(0xFFF7E7C2), onTint: const Color(0xFF6E5211)),
    TakhiAccent.steppe =>
      dark
          ? (tint: const Color(0xFF1E3B34), onTint: const Color(0xFF7FCBB6))
          : (tint: const Color(0xFFD5E8E1), onTint: const Color(0xFF1D4C40)),
    TakhiAccent.sky =>
      dark
          ? (tint: const Color(0xFF1D3247), onTint: const Color(0xFF8FBCE4))
          : (tint: const Color(0xFFD9E5F4), onTint: const Color(0xFF1D4468)),
    TakhiAccent.clay =>
      dark
          ? (tint: const Color(0xFF472822), onTint: const Color(0xFFEFA79A))
          : (tint: const Color(0xFFF7DED8), onTint: const Color(0xFF7A3226)),
    TakhiAccent.neutral =>
      dark
          ? (tint: Color(0xFF37322A), onTint: const Color(0xFFDCD5C8))
          : (tint: Color(0xFFEAE5DA), onTint: const Color(0xFF3A342C)),
  };
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
