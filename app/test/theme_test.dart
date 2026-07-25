// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';

import 'support/contrast.dart';

/// WCAG AA minimum contrast ratio for normal-size body text.
const _kMinAaContrast = 4.5;

void main() {
  test('light + dark themes expose brand gold as primary', () {
    expect(
      takhiTheme(Brightness.light).colorScheme.primary,
      const Color(0xFFC99A3C),
    );
    expect(
      takhiTheme(Brightness.dark).colorScheme.primary,
      const Color(0xFFC99A3C),
    );
    expect(TakhiColors.ink, const Color(0xFF1C1A16));
  });

  group('ColorScheme.error meets WCAG AA against its own surface', () {
    // Regression coverage for the design-system-audit fix: a single fixed
    // error red cannot be well-tuned for both a near-black dark surface and
    // a near-white light surface at once, so each brightness must resolve
    // to its own error color rather than sharing one hex value.
    test('light theme', () {
      final scheme = takhiTheme(Brightness.light).colorScheme;
      final ratio = contrastRatio(scheme.error, scheme.surface);
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinAaContrast),
        reason:
            'light ColorScheme.error only clears ${ratio.toStringAsFixed(2)}:1 '
            'against the light surface -- below WCAG AA (4.5:1)',
      );
    });

    test('dark theme', () {
      final scheme = takhiTheme(Brightness.dark).colorScheme;
      final ratio = contrastRatio(scheme.error, scheme.surface);
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinAaContrast),
        reason:
            'dark ColorScheme.error only clears ${ratio.toStringAsFixed(2)}:1 '
            'against the dark surface -- below WCAG AA (4.5:1)',
      );
    });

    test('light and dark error colors differ -- one hex cannot serve both '
        'surfaces', () {
      expect(TakhiColors.error, isNot(TakhiColors.errorDark));
    });
  });

  group('dialogTheme is configured rather than left to Material 3', () {
    // The app's ColorScheme is hand-built, so every surface role it does
    // not name -- `surfaceContainerHigh` among them -- falls back to
    // `surface`. Material 3 paints a dialog on `surfaceContainerHigh`, so
    // with no `dialogTheme` the sheet landed on the page's own paper and
    // every dialog button inherited `TextButton`'s default foreground,
    // `colorScheme.primary`: brand gold on paper, 2.28:1.
    for (final brightness in Brightness.values) {
      test('${brightness.name} theme names its own dialog surface', () {
        final theme = takhiTheme(brightness);
        expect(theme.dialogTheme.backgroundColor, isNotNull);
        expect(
          theme.dialogTheme.backgroundColor,
          isNot(theme.colorScheme.surface),
          reason:
              'the dialog sheet is painted on the same colour as the page '
              'behind it -- nothing but a shadow separates them',
        );
      });

      test('${brightness.name} theme suppresses the M3 elevation tint', () {
        // An elevation tint blends `primary` into the sheet by an amount
        // that depends on elevation, which would silently move every
        // contrast ratio asserted below away from the value measured here.
        expect(
          takhiTheme(brightness).dialogTheme.surfaceTintColor,
          Colors.transparent,
        );
      });
    }
  });

  group('dialog action colours meet WCAG AA against what they sit on', () {
    // Same shape as the ColorScheme.error group above: assert the ratio
    // numerically for both brightnesses rather than trusting that a colour
    // named "error" or "onSurface" happens to be readable where it lands.
    // Text tones are measured against the dialog sheet; filled tones
    // against their own fill.
    for (final brightness in Brightness.values) {
      for (final tone in DialogActionTone.values) {
        test('${brightness.name} theme, ${tone.name} tone', () {
          final theme = takhiTheme(brightness);
          final colors = dialogActionColors(tone, theme.colorScheme);
          final behind =
              colors.background ?? theme.dialogTheme.backgroundColor!;
          final ratio = contrastRatio(colors.foreground, behind);
          expect(
            ratio,
            greaterThanOrEqualTo(_kMinAaContrast),
            reason:
                '${tone.name} dialog action only clears '
                '${ratio.toStringAsFixed(2)}:1 in the ${brightness.name} '
                'theme -- below WCAG AA (4.5:1)',
          );
        });
      }
    }

    test('no dialog action falls back to the brand gold as *text* -- that is '
        'the 2.28:1 regression this group exists for', () {
      final theme = takhiTheme(Brightness.light);
      final sheet = theme.dialogTheme.backgroundColor!;
      // Documents the defect rather than merely avoiding it: gold is a
      // fill colour on this sheet, never a label colour.
      expect(
        contrastRatio(theme.colorScheme.primary, sheet),
        lessThan(_kMinAaContrast),
      );
      for (final tone in DialogActionTone.values) {
        final colors = dialogActionColors(tone, theme.colorScheme);
        expect(
          colors.background == null && colors.foreground == TakhiColors.gold,
          isFalse,
          reason: '${tone.name} paints gold text straight onto the sheet',
        );
      }
    });
  });

  group('ColorScheme.onError meets WCAG AA against its own error fill', () {
    // Regression coverage for the filled-destructive dialog action: a
    // single fixed `onError` cannot serve both a dark red (light theme)
    // and a light red (dark theme). White cleared 7.10:1 on
    // TakhiColors.error but only 2.68:1 on TakhiColors.errorDark, so the
    // dark theme's "delete my private key" button was unreadable.
    for (final brightness in Brightness.values) {
      test('${brightness.name} theme', () {
        final scheme = takhiTheme(brightness).colorScheme;
        final ratio = contrastRatio(scheme.onError, scheme.error);
        expect(
          ratio,
          greaterThanOrEqualTo(_kMinAaContrast),
          reason:
              '${brightness.name} ColorScheme.onError only clears '
              '${ratio.toStringAsFixed(2)}:1 on its own error fill',
        );
      });
    }
  });
}
