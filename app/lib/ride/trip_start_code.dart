// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math';

/// How many digits a pickup confirmation code has.
///
/// Four, not more: it is read aloud from one phone and typed into another at
/// a kerb, often in the dark, so every extra digit is another chance to
/// misread one and reject a passenger who is genuinely there. Four digits is
/// one-in-ten-thousand — ample against an *accidental* wrong-car pickup,
/// which is the whole job. It is not a password and is not defended against
/// a determined guesser: the code only unlocks starting a meter the driver
/// could start anyway, so its worth is catching the honest mistake, not the
/// attacker.
const int kStartCodeDigits = 4;

final RegExp _startCodePattern = RegExp('^\\d{$kStartCodeDigits}\$');

/// Whether [code] is exactly [kStartCodeDigits] ASCII digits — the shape a
/// code has to be to travel on the wire or be checked. Leading zeros are
/// valid, which is why codes are strings and never ints.
bool isWellFormedStartCode(String code) => _startCodePattern.hasMatch(code);

/// A fresh random confirmation code, zero-padded to [kStartCodeDigits]
/// (`0000`–`9999`).
///
/// Generated on the passenger's device when they hand off their pickup, and
/// only there — the driver never generates one, they confirm the one the
/// passenger shows. [random] is injectable so the generation is testable;
/// the app passes nothing and gets [Random.secure], because a predictable
/// code is no code at all.
String generateStartCode([Random? random]) {
  final rng = random ?? Random.secure();
  return rng.nextInt(10000).toString().padLeft(kStartCodeDigits, '0');
}

/// Whether the code the driver typed matches the one the passenger's handoff
/// carried. Trims the entry — a trailing space from a phone keyboard is not
/// a wrong code — and requires the expected code to be well-formed, so a
/// blank or malformed expected value never matches a blank entry by
/// accident.
bool startCodeMatches(String expected, String entered) =>
    isWellFormedStartCode(expected) && expected == entered.trim();
