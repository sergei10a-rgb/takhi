// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/meter/money_format.dart';

/// The separator `groupedMnt` is specified to use, written as an escape rather
/// than pasted in as a character.
///
/// A no-break space and an ordinary space are indistinguishable on screen and
/// in a diff, so a test that spelled it literally could not tell the two apart
/// -- which is exactly the test that would let the wrong one ship. Every
/// expectation below is built from this constant, and the last case in the
/// group pins it from the other side by rejecting a plain space outright.
const _nbsp = '\u00A0';

/// An ordinary space, likewise spelled out: what the separator must never be.
const _plainSpace = '\u0020';

void main() {
  group('groupedMnt', () {
    test('leaves a single digit as it stands', () {
      // Arrange
      const mnt = 5;

      // Act
      final grouped = groupedMnt(mnt);

      // Assert
      expect(grouped, '5');
    });

    test('renders zero as a bare zero, not an empty string', () {
      // Arrange
      const mnt = 0;

      // Act
      final grouped = groupedMnt(mnt);

      // Assert
      expect(grouped, '0');
    });

    test('leaves a three-digit amount ungrouped', () {
      // Arrange -- the largest amount with nothing to separate.
      const mnt = 999;

      // Act
      final grouped = groupedMnt(mnt);

      // Assert
      expect(grouped, '999');
    });

    test('separates at four digits without a leading separator', () {
      // Arrange -- the smallest amount that needs a separator, and the case an
      // off-by-one in the grouping would render as " 1 000".
      const mnt = 1000;

      // Act
      final grouped = groupedMnt(mnt);

      // Assert
      expect(grouped, '1${_nbsp}000');
    });

    test('groups the five-figure fare a taximeter actually shows', () {
      // Arrange -- 8.3 км at 1500₮/км, the reading that used to run together
      // as "12443₮".
      const mnt = 12443;

      // Act
      final grouped = groupedMnt(mnt);

      // Assert
      expect(grouped, '12${_nbsp}443');
    });

    test('groups every three digits in a seven-digit amount', () {
      // Arrange
      const mnt = 1234567;

      // Act
      final grouped = groupedMnt(mnt);

      // Assert
      expect(grouped, '1${_nbsp}234${_nbsp}567');
    });

    test('keeps the minus sign ahead of a negative amount and groups the '
        'digits behind it', () {
      // Arrange -- refunds and corrections are the only way this arises, but a
      // stray "-" dropped in among the digits would be a wrong number rather
      // than an ugly one.
      const mnt = -12443;

      // Act
      final grouped = groupedMnt(mnt);

      // Assert
      expect(grouped, '-12${_nbsp}443');
    });

    test('separates groups with a no-break space, never a plain one', () {
      // Arrange -- the property every other case here depends on. A plain
      // space lets a line break fall inside the amount, so "12" ends one line
      // and "443₮" starts the next: a different number to anyone scanning.
      const mnt = 1234567;

      // Act
      final grouped = groupedMnt(mnt);

      // Assert
      expect(grouped.contains(_plainSpace), isFalse);
      expect(grouped.split(_nbsp), ['1', '234', '567']);
    });
  });
}
