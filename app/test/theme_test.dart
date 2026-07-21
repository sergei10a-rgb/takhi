// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';

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
}
