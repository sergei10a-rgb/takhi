// SPDX-License-Identifier: AGPL-3.0-or-later

/// Thousands separator for төгрөг amounts.
///
/// A no-break space rather than a plain one: an amount is a single token, and
/// a plain space lets a line break fall inside it -- "12" at the end of one
/// line and "443₮" at the start of the next is a different number to anyone
/// scanning quickly.
const _groupSeparator = ' ';

/// Groups a төгрөг amount for display: `12443` -> `12 443`.
///
/// Written out rather than delegated to `intl`'s `NumberFormat`, because the
/// separator here is a fixed property of the *currency* and not of the UI
/// language: a driver reading the English build still reads төгрөг, and must
/// see the same digits grouped the same way as on the Mongolian build. A
/// locale-driven formatter would quietly switch to a comma for one of them.
///
/// Callers pass the result into the localised label that carries the ₮ sign
/// (`meterFareLabel` and friends), so the symbol's position stays a
/// translation concern and only the grouping lives here.
String groupedMnt(int mnt) {
  final digits = mnt.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    // A separator goes before every digit that starts a group of three
    // counted from the right -- never before the first digit, so 1234 is
    // "1 234" and not " 1 234".
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(_groupSeparator);
    buffer.write(digits[i]);
  }
  return mnt < 0 ? '-$buffer' : '$buffer';
}
