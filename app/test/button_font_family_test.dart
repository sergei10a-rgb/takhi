// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The only expression allowed on the right of a `textStyle:`.
const _kSanctioned = 'takhiButtonTextStyle(';

/// Where the app's own Dart lives.
const _kLibDir = 'lib';

/// Generated localisations: nobody edits them by hand and they carry no
/// button styles, so scanning them would only add noise.
const _kGeneratedDir = '/l10n/';

/// `ButtonStyle.textStyle` **replaces** the inherited text style instead of
/// merging onto it, so any style handed to it that carries no `fontFamily`
/// silently drops the bundled Cyrillic face and the label falls back to
/// whatever the platform hands back.
///
/// On a phone that fallback has Cyrillic and the bug is invisible. Under
/// `flutter_test` it does not, so the label renders as a row of empty boxes.
/// That is how it has been found twice now, both times only from a picture
/// and never from a passing/failing widget test:
///
/// * «Түр зогсоох» on the running meter, drawn as ▯▯▯ ▯▯▯▯▯▯▯ beside
///   correct text, with 565 tests green;
/// * the passenger/driver segmented control on onboarding, drawn as
///   ▯▯▯▯▯▯▯ ▯▯▯▯▯▯ in *both* brightnesses, for as long as that control
///   existed.
///
/// `design_system_audit_test.dart` already forbids a bare `TakhiType.x`
/// token here, which is what caught the first one. It did not catch the
/// second, because the offending expression was an inline
/// `const TextStyle(fontWeight: FontWeight.w600)` -- family-less in exactly
/// the same way, and not a token at all. This check is the general form:
/// whatever the expression is, it has to come out of
/// [takhiButtonTextStyle], which merges onto the theme's own
/// `titleMedium` and so cannot lose the family.
///
/// Nothing about the wrong expression looks wrong at the call site, which
/// is why this has to be mechanical rather than a review habit.
void main() {
  test('every textStyle: in a button style goes through '
      'takhiButtonTextStyle, so it keeps the bundled Cyrillic family', () {
    final offenders = <String>[];
    for (final entity in Directory(_kLibDir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.replaceAll(r'\', '/').contains(_kGeneratedDir)) continue;
      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Prose about the rule is not a breach of it.
        if (line.trimLeft().startsWith('//')) continue;
        if (!line.contains('textStyle:')) continue;
        if (line.contains(_kSanctioned)) continue;
        offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A ButtonStyle textStyle must be built with '
          'takhiButtonTextStyle(context, TakhiType.x). A bare TextStyle or '
          'a bare token there drops fontFamily and renders every Cyrillic '
          'glyph as an empty box:\n${offenders.join('\n')}',
    );
  });
}
