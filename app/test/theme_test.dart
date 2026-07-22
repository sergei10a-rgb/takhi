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
}
