// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative luminance of an sRGB color (spec section 1.4.3).
double relativeLuminance(Color c) {
  double channel(double c) {
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(c.r);
  final g = channel(c.g);
  final b = channel(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG 2.1 contrast ratio between two colors (spec section 1.4.3),
/// always >= 1.0 regardless of argument order.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
