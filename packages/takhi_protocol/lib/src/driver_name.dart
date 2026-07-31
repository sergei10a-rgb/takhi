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

  /// Spelled in some other alphabet -- in practice, Latin.
  ///
  /// Kept apart from [disallowedCharacter] because it is the one problem
  /// here that an honest, careful person hits: `Batbayar` is a real name,
  /// correctly spelled, typed by someone whose keyboard was in the wrong
  /// mode. Telling them their name "contains a disallowed character" would
  /// be both baffling and slightly insulting; what they need to be told is
  /// to switch to Cyrillic.
  notCyrillic,
}

/// Every rune a name part may contain *after* the first: Cyrillic letters
/// and their combining marks, plus the three separators Mongolian names
/// use.
///
/// This used to be `\p{L}`, which accepts every script at once, on the
/// reasoning that an app has no business deciding which alphabets are real.
/// That reasoning is sound in general and wrong for this field. These two
/// names are shown to a passenger deciding whether to get into a stranger's
/// car, beside a plate number they are reading off the kerb in Ulaanbaatar,
/// and a name spelled `Batbayar` on screen against `Батбаяр` on a licence
/// is a mismatch the passenger has to resolve under time pressure at night.
/// One alphabet, so the two can simply be compared. Requested directly by
/// the app's author, 2026-08-01.
///
/// `\p{Script=Cyrillic}` rather than a hand-written `[а-яА-ЯөүӨҮ]`: the
/// Mongolian alphabet is the Russian one plus Ө and Ү, and spelling the set
/// out by hand is how a real name containing a letter nobody remembered
/// (`Ё`, or a rarely-used borrowing) gets rejected with no way for the
/// driver to argue.
///
/// The three separators, and why each is here:
///  * space -- a two-word given name
///  * `-` -- `Мөнх-Эрдэнэ`, extremely common
///  * `.` -- `Б.`, which is how a Mongolian family name is normally written
///
/// `'` is gone with the Latin script it existed for (`O'Brien`).
///
/// The first rune must be a letter, so `-Бат` and `...` are both out: a
/// leading separator is either a typo or an attempt to make a name sort or
/// render oddly, never a name.
final RegExp _acceptableNamePart = RegExp(
  r'^\p{Script=Cyrillic}[\p{Script=Cyrillic}\p{M} \-.]*$',
  unicode: true,
);

/// Whether [value] contains a letter from some script other than Cyrillic.
///
/// Asked separately from [_acceptableNamePart] purely so the two failures
/// can be told apart in the message: "switch your keyboard to Cyrillic" and
/// "names do not contain digits" are different problems with different
/// fixes, and a single "invalid name" would leave a driver guessing which.
/// Written as a rune scan rather than one regular expression because Dart
/// has no character-class intersection: `[\p{L}&&[^\p{Script=Cyrillic}]]`
/// is Java/ICU syntax and Dart throws `FormatException: Lone quantifier
/// brackets` on it at construction time.
bool _containsNonCyrillicLetter(String value) {
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (_anyLetter.hasMatch(character) && !_cyrillic.hasMatch(character)) {
      return true;
    }
  }
  return false;
}

/// Anything that is not a letter, a combining mark, or one of the three
/// separators -- a digit, an emoji, markup, punctuation, an invisible
/// formatting character.
final RegExp _hasForbiddenCharacter = RegExp(
  r'[^\p{L}\p{M} \-.]',
  unicode: true,
);

final RegExp _anyLetter = RegExp(r'\p{L}', unicode: true);
final RegExp _cyrillic = RegExp(r'\p{Script=Cyrillic}', unicode: true);

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
    // Order matters, and it is stray characters first.
    //
    // `<b>Бат</b>` is wrong for two reasons at once -- it carries angle
    // brackets AND Latin letters -- and answering "please use Cyrillic"
    // would be technically true and useless, because switching keyboard
    // will not remove the tags. Anything carrying a character no name has
    // is reported as that; only a string made entirely of letters and
    // separators, whose letters are simply the wrong alphabet, is the
    // keyboard-mode problem.
    if (_hasForbiddenCharacter.hasMatch(value)) {
      return DriverNameProblem.disallowedCharacter;
    }
    return _containsNonCyrillicLetter(value)
        ? DriverNameProblem.notCyrillic
        // Everything left is a name-shaped string that still fails the
        // pattern -- in practice one starting with a separator, `-Бат`.
        : DriverNameProblem.disallowedCharacter;
  }
  return null;
}

/// Whether [raw] is usable as a name part -- the boolean shorthand for
/// `driverNamePartProblem(raw) == null`, for the call sites that only need
/// to gate and have no message to show.
bool isValidDriverNamePart(String raw) => driverNamePartProblem(raw) == null;
