// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';

import 'support/contrast.dart';

/// WCAG AA minimum contrast ratio for normal-size body text. The same
/// threshold `theme_test.dart` holds the dialog palette to -- the design
/// system's surfaces, chips and category tiles are held to it too, so that
/// "it looked fine on my screen" never becomes the standard.
const _kMinAaContrast = 4.5;

/// WCAG AA minimum for large text (>=18.66px bold or >=24px regular) and
/// for non-text UI boundaries. Only used where the token is explicitly a
/// hairline or a decorative separator, never for a label.
const _kMinLargeContrast = 3.0;

void main() {
  group('surface ladder is a real ladder in both brightnesses', () {
    // The direction is UBCab-shaped: a map fills the screen, a raised sheet
    // floats on it, and sunken pill fields sit inside the sheet. That only
    // reads if the three surfaces are actually distinguishable -- and the
    // dark ladder is NOT the light one inverted. In light, the field is
    // *darker* than the sheet it sits in; in dark, "sunken" still has to
    // read as lighter, because a darker-than-near-black field would
    // disappear into the canvas behind the sheet.
    test('light: canvas < sheet in lightness, field is the sunken one', () {
      const s = TakhiSurfaces.light;
      expect(
        relativeLuminance(s.sheet),
        greaterThan(relativeLuminance(s.canvas)),
        reason: 'the sheet must read as raised off the canvas',
      );
      expect(
        relativeLuminance(s.field),
        lessThan(relativeLuminance(s.sheet)),
        reason: 'an input well must read as sunken into the sheet',
      );
    });

    test('dark: sheet and field both climb, they do not mirror light', () {
      const s = TakhiSurfaces.dark;
      expect(
        relativeLuminance(s.sheet),
        greaterThan(relativeLuminance(s.canvas)),
      );
      expect(
        relativeLuminance(s.field),
        greaterThan(relativeLuminance(s.sheet)),
        reason:
            'in a dark room "raised" and "recessed" both read as lighter; '
            'inverting the light ladder would sink the field into the canvas',
      );
    });

    for (final brightness in Brightness.values) {
      test('${brightness.name}: every step of the ladder is visible', () {
        final s = TakhiSurfaces.forBrightness(brightness);
        for (final (name, a, b) in <(String, Color, Color)>[
          ('canvas -> sheet', s.canvas, s.sheet),
          ('sheet -> field', s.sheet, s.field),
        ]) {
          final ratio = contrastRatio(a, b);
          expect(
            ratio,
            greaterThan(1.05),
            reason:
                '$name is only ${ratio.toStringAsFixed(3)}:1 apart in the '
                '${brightness.name} theme -- the step is invisible',
          );
        }
      });
    }
  });

  group('text on every surface meets WCAG AA', () {
    for (final brightness in Brightness.values) {
      final s = TakhiSurfaces.forBrightness(brightness);
      for (final (name, fg, bg) in <(String, Color, Color)>[
        ('primary text on sheet', s.onSheet, s.sheet),
        ('primary text on field', s.onSheet, s.field),
        ('primary text on canvas', s.onSheet, s.canvas),
        ('supporting text on sheet', s.muted, s.sheet),
        // The placeholder inside a PillField and the small grey label of an
        // AddressRow both land here -- the pairing most likely to be waved
        // through as "it's only secondary text".
        ('supporting text on field', s.muted, s.field),
      ]) {
        test('${brightness.name}: $name', () {
          final ratio = contrastRatio(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(_kMinAaContrast),
            reason:
                '$name clears only ${ratio.toStringAsFixed(2)}:1 in the '
                '${brightness.name} theme -- below WCAG AA (4.5:1)',
          );
        });
      }

      test('${brightness.name}: hairline is visible against the sheet', () {
        // A border is not text, so it is held to the 3:1 non-text minimum --
        // but it still has to be *there*: the dark theme leans on hairlines
        // exactly where the light theme leans on shadow.
        final ratio = contrastRatio(
          Color.alphaBlend(s.hairline, s.sheet),
          s.sheet,
        );
        expect(
          ratio,
          greaterThan(1.05),
          reason:
              'the hairline composites to ${ratio.toStringAsFixed(3)}:1 over '
              'the sheet in the ${brightness.name} theme -- invisible',
        );
      });
    }
  });

  group('accent tint/onTint pairs meet WCAG AA on their own tint', () {
    // Category tiles and info chips paint a deep icon on a soft tint of the
    // same hue. Both halves move per brightness, so a pair that is legible
    // in light says nothing about the same pair in dark -- assert the
    // number for all of them.
    for (final brightness in Brightness.values) {
      for (final accent in TakhiAccent.values) {
        test('${brightness.name}: ${accent.name}', () {
          final c = takhiAccentColors(accent, brightness);
          final ratio = contrastRatio(c.onTint, c.tint);
          expect(
            ratio,
            greaterThanOrEqualTo(_kMinAaContrast),
            reason:
                '${accent.name} icon/label clears only '
                '${ratio.toStringAsFixed(2)}:1 on its own tint in the '
                '${brightness.name} theme',
          );
        });

        test('${brightness.name}: ${accent.name} tint separates from the '
            'sheet it sits on', () {
          final c = takhiAccentColors(accent, brightness);
          final s = TakhiSurfaces.forBrightness(brightness);
          expect(
            contrastRatio(c.tint, s.sheet),
            greaterThan(1.05),
            reason:
                'a ${accent.name} tile is indistinguishable from the sheet '
                'in the ${brightness.name} theme',
          );
        });
      }
    }

    test('accents are distinct hues, not five names for one colour', () {
      const brightness = Brightness.light;
      final tints = {
        for (final a in TakhiAccent.values)
          takhiAccentColors(a, brightness).tint,
      };
      expect(tints.length, TakhiAccent.values.length);
    });
  });

  group('brand rules the palette still has to obey', () {
    test('gold is never a text colour on a light surface -- it is a fill', () {
      // Documents the 2.28:1 defect rather than merely avoiding it, the same
      // way theme_test.dart does for dialog actions.
      const s = TakhiSurfaces.light;
      expect(
        contrastRatio(TakhiColors.gold, s.sheet),
        lessThan(_kMinAaContrast),
      );
      expect(
        contrastRatio(TakhiColors.ink, TakhiColors.gold),
        greaterThanOrEqualTo(_kMinAaContrast),
        reason: 'ink on a gold fill is the pairing gold is allowed to have',
      );
    });

    test('the gold accent tile is legible where flat gold would not be', () {
      // The gold *accent* exists precisely because flat gold fails as a
      // foreground: the tile darkens the ink and lightens the ground until
      // the pair clears AA, instead of dropping gold from the icon set.
      final c = takhiAccentColors(TakhiAccent.gold, Brightness.light);
      expect(
        contrastRatio(c.onTint, c.tint),
        greaterThanOrEqualTo(_kMinAaContrast),
      );
    });
  });

  group('scales are ordered and quantised', () {
    test('spacing is a strictly increasing multiple-of-4 scale', () {
      const scale = [
        TakhiSpace.xxs,
        TakhiSpace.xs,
        TakhiSpace.sm,
        TakhiSpace.md,
        TakhiSpace.lg,
        TakhiSpace.xl,
        TakhiSpace.xxl,
      ];
      for (var i = 0; i < scale.length; i++) {
        expect(scale[i] % 4, 0, reason: '${scale[i]} is off the 4dp grid');
        if (i > 0) expect(scale[i], greaterThan(scale[i - 1]));
      }
    });

    test('radii are ordered smallest shape to largest, pill last', () {
      expect(TakhiRadius.chip, lessThan(TakhiRadius.tile));
      expect(TakhiRadius.tile, lessThan(TakhiRadius.card));
      expect(TakhiRadius.card, lessThan(TakhiRadius.sheet));
      expect(TakhiRadius.sheet, lessThan(TakhiRadius.pill));
    });

    test('the touch floor is at least the 44dp accessibility minimum', () {
      expect(TakhiTouch.minTarget, greaterThanOrEqualTo(44.0));
    });

    test('micro-interaction durations stay inside the 150-300ms window', () {
      for (final d in [
        TakhiMotion.fast,
        TakhiMotion.normal,
        TakhiMotion.slow,
      ]) {
        expect(d.inMilliseconds, greaterThanOrEqualTo(150));
        expect(d.inMilliseconds, lessThanOrEqualTo(300));
      }
      expect(TakhiMotion.fast, lessThan(TakhiMotion.normal));
      expect(TakhiMotion.normal, lessThan(TakhiMotion.slow));
    });

    test('the type scale descends by role without ties', () {
      const sizes = [
        TakhiType.display,
        TakhiType.heading,
        TakhiType.title,
        TakhiType.body,
        TakhiType.support,
        TakhiType.label,
        TakhiType.micro,
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(
          sizes[i].fontSize,
          lessThan(sizes[i - 1].fontSize!),
          reason: 'two roles share a size -- the hierarchy is decorative',
        );
      }
    });

    test('headings are heavy and numerals are tabular', () {
      // "МАШ БҮДҮҮН хар гарчиг" is a load-bearing part of the direction, and
      // a taximeter that reflows as the digits change is a driver-safety
      // problem, not a styling one.
      expect(TakhiType.display.fontWeight, FontWeight.w800);
      expect(TakhiType.heading.fontWeight, FontWeight.w700);
      for (final style in [TakhiType.numeric, TakhiType.numericDisplay]) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });
  });

  group('elevation is brightness-aware', () {
    test('light leans on shadow, dark does not', () {
      expect(TakhiSurfaces.light.sheetShadow, isNotEmpty);
      expect(
        TakhiSurfaces.dark.sheetShadow,
        isEmpty,
        reason:
            'a shadow on a near-black canvas is invisible -- dark separates '
            'surfaces with a hairline instead',
      );
    });

    test('the dark hairline is the stronger of the two, since it is doing '
        "the light theme's shadow work", () {
      final darkRatio = contrastRatio(
        Color.alphaBlend(TakhiSurfaces.dark.hairline, TakhiSurfaces.dark.sheet),
        TakhiSurfaces.dark.sheet,
      );
      expect(darkRatio, greaterThan(1.1));
    });

    test('floating controls carry a softer shadow than the sheet', () {
      final sheetBlur = TakhiSurfaces.light.sheetShadow
          .map((s) => s.blurRadius)
          .reduce((a, b) => a > b ? a : b);
      final floatBlur = TakhiSurfaces.light.floatShadow
          .map((s) => s.blurRadius)
          .reduce((a, b) => a > b ? a : b);
      expect(floatBlur, lessThan(sheetBlur));
    });
  });

  group('TakhiSurfaces resolves from a BuildContext', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} theme', (t) async {
        late TakhiSurfaces resolved;
        await t.pumpWidget(
          MaterialApp(
            theme: takhiTheme(brightness),
            home: Builder(
              builder: (context) {
                resolved = TakhiSurfaces.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(resolved, same(TakhiSurfaces.forBrightness(brightness)));
      });
    }

    test('the light canvas matches the scaffold the theme already paints', () {
      // Otherwise a full-bleed TakhiSheet would sit on a canvas colour that
      // no screen actually has behind it.
      expect(
        TakhiSurfaces.light.canvas,
        takhiTheme(Brightness.light).scaffoldBackgroundColor,
      );
      expect(
        TakhiSurfaces.dark.canvas,
        takhiTheme(Brightness.dark).scaffoldBackgroundColor,
      );
    });

    test('non-text separators clear the 3:1 non-text minimum where they '
        'carry meaning', () {
      // The selected ring on a CategoryTile is the one border that means
      // something rather than merely bounding a shape.
      for (final brightness in Brightness.values) {
        final c = takhiAccentColors(TakhiAccent.gold, brightness);
        final s = TakhiSurfaces.forBrightness(brightness);
        expect(
          contrastRatio(c.onTint, s.sheet),
          greaterThanOrEqualTo(_kMinLargeContrast),
          reason:
              'the ${brightness.name} selected ring is invisible against '
              'the sheet',
        );
      }
    });
  });
}
