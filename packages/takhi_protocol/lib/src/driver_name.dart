// SPDX-License-Identifier: AGPL-3.0-or-later

/// The longest a single name part -- a family name or a given name -- may
/// be, counted in **runes**, not UTF-16 code units.
///
/// The number is a display budget rather than a legal one: these two parts
/// are drawn side by side on one line of an offer row next to a car, a
/// price and an ETA, and a name that does not fit there is a name a
/// passenger reads as "…". 32 runes comfortably holds the longest real
/// Mongolian name (`Мөнх-Эрдэнэ` is 11) while stopping a paragraph from
/// being pasted into the box.
const int kMaxDriverNamePartLength = 32;

/// Why a name part cannot be used. Deliberately an enum and not a message:
/// this layer has no localizations, and each case has to become a *different*
/// sentence in the UI -- "you left it blank" and "you typed a digit" are not
/// fixed the same way, and one shared "invalid name" would tell a driver
/// nothing about which.
enum DriverNameProblem {
  /// Nothing but whitespace, or nothing at all.
  empty,

  /// More than [kMaxDriverNamePartLength] runes.
  tooLong,

  /// Carries something no name carries: a digit, an emoji, markup, a
  /// newline, an invisible formatting character -- or it starts with a
  /// separator, or has no letter in it at all.
  disallowedCharacter,
}

/// Every rune a name part may contain *after* the first: letters and their
/// combining marks, plus the four separators real names use.
///
/// `\p{L}` covers Cyrillic, Latin, and every other script at once, which is
/// the point -- an allow-list written as `[а-яА-ЯөүӨҮ]` would quietly reject
/// a driver whose name is written in a script nobody thought of, and this
/// app has no business deciding which alphabets are real.
///
/// The four separators, and why each is here:
///  * space -- `Ван Дер Берг`
///  * `-` -- `Мөнх-Эрдэнэ`, extremely common
///  * `'` -- `O'Brien`
///  * `.` -- `Б.`, which is how a Mongolian family name is normally written
///
/// The first rune must be a letter, so `-Бат` and `...` are both out: a
/// leading separator is either a typo or an attempt to make a name sort or
/// render oddly, never a name.
final RegExp _acceptableNamePart = RegExp(
  r"^\p{L}[\p{L}\p{M} \-'.]*$",
  unicode: true,
);

/// Any run of whitespace -- including the tab and newline that arrive when
/// text is pasted rather than typed.
final RegExp _whitespaceRun = RegExp(r'\s+');

/// Trims [raw] and collapses every internal run of whitespace into a single
/// space.
///
/// This runs *before* validation rather than instead of it. Whitespace
/// damage is a paste artefact, not a statement about the name -- `«Цэрэн
/// Дорж»` with two spaces, or with a line break in the middle, is one
/// person's name typed carelessly, so it is repaired and accepted rather
/// than refused. What must not happen is the break surviving into storage:
/// every row this name is later drawn in is a single line, and a newline
/// there would push the car, the price and the ETA out of the row. Collapse
/// first, then judge what is left.
///
/// Store what [normalizeDriverNamePart] returns, never the raw text, or two
/// drivers who typed the same name differently end up with different names.
String normalizeDriverNamePart(String raw) =>
    raw.replaceAll(_whitespaceRun, ' ').trim();

/// `null` when [raw] is usable as a name part, otherwise the first thing
/// wrong with it. Normalizes internally, so callers may pass raw text
/// straight from a text field.
DriverNameProblem? driverNamePartProblem(String raw) {
  final value = normalizeDriverNamePart(raw);
  if (value.isEmpty) return DriverNameProblem.empty;
  // Runes, not `String.length`: an emoji or an astral-plane letter is two
  // UTF-16 code units, and a length rule that counted those would reject a
  // shorter name than it advertises.
  if (value.runes.length > kMaxDriverNamePartLength) {
    return DriverNameProblem.tooLong;
  }
  if (!_acceptableNamePart.hasMatch(value)) {
    return DriverNameProblem.disallowedCharacter;
  }
  return null;
}

/// Whether [raw] is usable as a name part -- the boolean shorthand for
/// `driverNamePartProblem(raw) == null`, for the call sites that only need
/// to gate and have no message to show.
bool isValidDriverNamePart(String raw) => driverNamePartProblem(raw) == null;
