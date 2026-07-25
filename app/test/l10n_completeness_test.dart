// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app_mn.arb and app_en.arb declare exactly the same translation '
      'keys', () {
    final mn =
        jsonDecode(File('lib/l10n/app_mn.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;

    // '@@locale' and per-key '@key' metadata blocks are ARB tooling
    // scaffolding, not translation strings -- excluded from the
    // key-parity check (a metadata block existing only in one file is
    // not a missing translation).
    bool isTranslationKey(String k) => !k.startsWith('@');

    final mnKeys = mn.keys.where(isTranslationKey).toSet();
    final enKeys = en.keys.where(isTranslationKey).toSet();

    final missingFromEn = mnKeys.difference(enKeys);
    final missingFromMn = enKeys.difference(mnKeys);

    expect(
      missingFromEn,
      isEmpty,
      reason:
          'Keys in app_mn.arb with no app_en.arb translation: '
          '$missingFromEn',
    );
    expect(
      missingFromMn,
      isEmpty,
      reason: 'Keys in app_en.arb with no app_mn.arb source: $missingFromMn',
    );
  });

  test('every non-empty string value in app_en.arb differs from its '
      'app_mn.arb counterpart (catches a forgotten/copy-pasted '
      'translation)', () {
    final mn =
        jsonDecode(File('lib/l10n/app_mn.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;

    final suspicious = <String>[];
    for (final key in mn.keys) {
      if (key.startsWith('@')) continue;
      final mnValue = mn[key];
      final enValue = en[key];
      if (mnValue is! String || enValue is! String) continue;
      // A handful of keys are legitimately identical across languages
      // (a bare number placeholder string, a brand name, "SOS", '102').
      // `estimatedFareLabel`/`meterFareLabel` are a currency symbol plus a
      // number placeholder with no actual words to translate ("≈ {mnt}₮" /
      // "{mnt}₮") -- identical in both files by construction, not a
      // forgotten translation.
      const allowedIdentical = {
        'appName',
        'sosAction',
        'estimatedFareLabel',
        'meterFareLabel',
      };
      if (mnValue == enValue &&
          mnValue.isNotEmpty &&
          !allowedIdentical.contains(key)) {
        suspicious.add(key);
      }
    }
    expect(
      suspicious,
      isEmpty,
      reason:
          'Keys whose en value is identical to mn (likely untranslated): '
          '$suspicious',
    );
  });

  // The two checks above compare the .arb files against *each other*, so a
  // key that exists in both -- fully translated, perfect parity -- but is
  // wired to nothing passes them both. That is exactly what parallel
  // implementation waves leave behind: one agent adds the string another
  // agent's approach ended up not needing. The strings are dead weight at
  // best, and at worst (as with `meteredOfferNoTariffHint`) they are the
  // only surviving evidence that a piece of UI was designed and then never
  // built.
  test('every app_mn.arb key is referenced somewhere in lib/ (catches '
      'strings left behind by an abandoned implementation)', () {
    final mn =
        jsonDecode(File('lib/l10n/app_mn.arb').readAsStringSync())
            as Map<String, dynamic>;

    // lib/l10n/ is generated *from* the .arb files and so declares a getter
    // for every key by construction -- including it would make this check
    // pass unconditionally.
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/l10n/'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final unused = <String>[];
    for (final key in mn.keys) {
      if (key.startsWith('@')) continue;
      if (!RegExp('\\b$key\\b').hasMatch(sources)) unused.add(key);
    }

    expect(
      unused,
      isEmpty,
      reason:
          'Translation keys no Dart file under lib/ uses: $unused. '
          'Either wire the string to the UI it was written for, or delete '
          'it from both app_mn.arb and app_en.arb.',
    );
  });
}
