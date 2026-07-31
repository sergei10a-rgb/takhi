// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  group('normalizeDriverNamePart', () {
    test('trims the ends', () {
      expect(normalizeDriverNamePart('  Батбаяр  '), 'Батбаяр');
    });

    test('collapses an internal run of whitespace into one space', () {
      expect(normalizeDriverNamePart('Ван   Дер\tБерг'), 'Ван Дер Берг');
    });

    test('leaves an already-clean name untouched', () {
      expect(normalizeDriverNamePart('Мөнх-Эрдэнэ'), 'Мөнх-Эрдэнэ');
    });

    test('a string of only whitespace normalizes to empty', () {
      expect(normalizeDriverNamePart('   \t \n '), '');
    });

    // A name pasted out of a notes app arrives with a line break in it. The
    // break is a paste artefact, not a statement about the name, so it is
    // repaired rather than refused -- but it must not survive into storage,
    // because every row this name is drawn in is a single line.
    test('a pasted line break becomes a space instead of being rejected', () {
      expect(normalizeDriverNamePart('Бат\nБаяр'), 'Бат Баяр');
      expect(driverNamePartProblem('Бат\nБаяр'), isNull);
    });

    // Escapes rather than the characters themselves. A vertical tab, a
    // no-break space and a line separator typed literally into a source
    // file are invisible in every editor and diff that will ever show
    // this line, and U+2028 in particular is a line terminator to enough
    // tooling that one reformat or one `.gitattributes` rule could
    // silently turn this into a test of something else. What is being
    // asserted has to be readable in the assertion.
    test('no whitespace character survives normalization except one space', () {
      for (final ws in ['\n', '\r', '\t', '\u000b', '\u00a0', '\u2028']) {
        // Cyrillic cannot continue a Dart identifier, so the analyzer is
        // right that the braces below are redundant. Written out anyway:
        // the unbraced form is one ASCII letter away from silently meaning
        // something else, in a test whose whole subject is characters
        // nobody can see.
        // ignore: unnecessary_brace_in_string_interps
        final normalized = normalizeDriverNamePart('Бат${ws}Баяр');
        expect(
          normalized,
          'Бат Баяр',
          reason: 'U+${ws.codeUnitAt(0).toRadixString(16)} survived',
        );
      }
    });
  });

  group('driverNamePartProblem accepts', () {
    // Each of these is a shape a real Mongolian driver will type. A rule
    // that rejects any of them would send a legitimate driver away with no
    // way to comply, which is worse than the sloppiness it prevents.
    const accepted = <String>[
      'Батбаяр',
      'Мөнх-Эрдэнэ', // hyphenated, and carries Ө/Ү
      'Б.', // the family name as an initial -- how it is normally written
      'Ван Дер Берг', // multi-word family name
      "O'Brien", // apostrophe, Latin
      'Ganbold', // Latin transliteration
      'Цэрэн  Дорж', // extra space, normalized away before the check
      '  Сараа ', // untrimmed, likewise
    ];

    for (final name in accepted) {
      test('«$name»', () => expect(driverNamePartProblem(name), isNull));
    }
  });

  group('driverNamePartProblem rejects', () {
    test('an empty string', () {
      expect(driverNamePartProblem(''), DriverNameProblem.empty);
    });

    test('whitespace only -- not a name, however it looks in a text box', () {
      expect(driverNamePartProblem('   '), DriverNameProblem.empty);
    });

    test('a name longer than the limit', () {
      final tooLong = 'а' * (kMaxDriverNamePartLength + 1);
      expect(driverNamePartProblem(tooLong), DriverNameProblem.tooLong);
    });

    test('a name exactly at the limit is still accepted', () {
      final atLimit = 'а' * kMaxDriverNamePartLength;
      expect(driverNamePartProblem(atLimit), isNull);
    });

    test('the limit counts runes, not UTF-16 code units', () {
      // Cyrillic is one code unit per rune, so it cannot catch a length rule
      // that measures `String.length`. An astral-plane rune can: 32 of these
      // are 64 code units.
      final astral = '𝒜' * kMaxDriverNamePartLength;
      expect(astral.length, kMaxDriverNamePartLength * 2);
      // Still rejected -- but for carrying a disallowed character, not for
      // length. What matters here is that the *length* rule did not fire on
      // a 32-rune string.
      expect(driverNamePartProblem(astral), isNot(DriverNameProblem.tooLong));
    });

    test('digits -- a plate number is not a name', () {
      expect(
        driverNamePartProblem('Бат1'),
        DriverNameProblem.disallowedCharacter,
      );
    });

    test('an emoji', () {
      expect(
        driverNamePartProblem('Бат🚕'),
        DriverNameProblem.disallowedCharacter,
      );
    });

    test('markup', () {
      expect(
        driverNamePartProblem('<b>Бат</b>'),
        DriverNameProblem.disallowedCharacter,
      );
    });

    test('a name that starts with a separator', () {
      expect(
        driverNamePartProblem('-Бат'),
        DriverNameProblem.disallowedCharacter,
      );
      expect(
        driverNamePartProblem('.Бат'),
        DriverNameProblem.disallowedCharacter,
      );
    });

    test('punctuation with no letter at all', () {
      expect(
          driverNamePartProblem('...'), DriverNameProblem.disallowedCharacter);
    });

    test('an invisible zero-width joiner smuggled between letters', () {
      expect(
        driverNamePartProblem('Бат‍баяр'),
        DriverNameProblem.disallowedCharacter,
      );
    });
  });
}
