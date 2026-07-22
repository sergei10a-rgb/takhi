// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app_mn.arb and app_en.arb declare exactly the same translation '
      'keys', () {
    final mn = jsonDecode(
      File('lib/l10n/app_mn.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final en = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

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
      reason: 'Keys in app_mn.arb with no app_en.arb translation: '
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
    final mn = jsonDecode(
      File('lib/l10n/app_mn.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final en = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

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
      reason: 'Keys whose en value is identical to mn (likely untranslated): '
          '$suspicious',
    );
  });
}
