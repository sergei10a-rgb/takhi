// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `AlertDialog(...)` expression in [source], sliced out by matching
/// parentheses from the constructor name. Parenthesis counting is enough
/// here because no dialog in this app puts an unbalanced `(` inside a
/// string literal -- if one ever does, this test is where it will show up.
Iterable<String> _alertDialogBodies(String source) sync* {
  const marker = 'AlertDialog(';
  var from = 0;
  while (true) {
    final start = source.indexOf(marker, from);
    if (start < 0) return;
    var depth = 0;
    var i = start + marker.length - 1;
    for (; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') depth--;
      if (depth == 0) break;
    }
    yield source.substring(start, i.clamp(start, source.length));
    from = i + 1;
  }
}

void main() {
  // The dialog-button audit found brand gold on paper at 2.28:1 across
  // seven dialogs at once, because each one had hand-rolled its own action
  // buttons and inherited Material's defaults. Centralising them in
  // `DialogActionBar` fixed all seven; this check is what stops the eighth
  // dialog from starting the cycle again. A raw button inside an
  // `AlertDialog` is the exact shape of that regression.
  test('every AlertDialog builds its actions with DialogActionBar, never '
      'bare Material buttons', () {
    const bareButtons = [
      'TextButton(',
      'FilledButton(',
      'ElevatedButton(',
      'OutlinedButton(',
      'PrimaryButton(',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final body in _alertDialogBodies(entity.readAsStringSync())) {
        if (!body.contains('DialogActionBar(')) {
          offenders.add('${entity.path}: dialog has no DialogActionBar');
        }
        for (final button in bareButtons) {
          if (body.contains(button)) {
            offenders.add('${entity.path}: dialog builds a bare $button)');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Dialog actions must go through widgets/dialog_action_bar.dart, '
          'which owns the readable-on-the-sheet colours and the '
          'row-or-stack fitting rule for long Cyrillic labels:\n'
          '${offenders.join('\n')}',
    );
  });

  test('no widget file hardcodes a raw Color(0x... outside the theme file', () {
    final libDir = Directory('lib');
    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path
          .replaceAll('\\', '/')
          .endsWith('theme/takhi_theme.dart')) {
        continue; // the one file allowed to define raw palette values
      }
      final content = entity.readAsStringSync();
      if (RegExp(r'Color\(0x').hasMatch(content)) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Hardcoded Color(0x...) outside theme/takhi_theme.dart -- use '
          'TakhiColors.* or Theme.of(context).colorScheme instead:\n'
          '${offenders.join('\n')}',
    );
  });

  // `ButtonStyle.textStyle` replaces the inherited text style instead of
  // merging onto it, so a bare family-less token there loses the app font.
  // It is invisible on a phone, where the platform fallback also has
  // Cyrillic; it took a rendered screenshot -- «Түр зогсоох» drawn as
  // ▯▯▯ ▯▯▯▯▯▯▯ next to correct text -- to catch the two call sites that had
  // it. A grep is the only guard that scales: nothing about the expression
  // looks wrong at the call site.
  test('no button style passes a bare TakhiType token as its textStyle', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'textStyle:\s*(const\s+)?TakhiType\.').hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A ButtonStyle textStyle must go through '
          'takhiButtonTextStyle(context, TakhiType.x) so it keeps the app '
          'font family:\n${offenders.join('\n')}',
    );
  });

  // Sixty-three hand-typed sizes had accumulated across fifteen files before
  // this check existed -- gaps of 18 where the scale says 16 or 20, a font at
  // 15 beside the role that is already 15, four radii for the same kind of
  // box. None of it was visible on its own; together it was why no two
  // screens quite matched, and why "make every gap a little wider" would have
  // meant hunting sixty-three call sites and missing some.
  //
  // A number is allowed in exactly two places: theme/takhi_theme.dart, which
  // defines the scale, and a named file-level constant, which is how a
  // genuinely one-off measurement (a safety gap between "answer" and
  // "decline", the width of a route line on a map) says so out loud.
  test('no widget file hardcodes a raw size -- spacing, radius, font and '
      'stroke all come from tokens', () {
    // `0` is not a magic number: it means "none", it has no alternative
    // value, and a token named zero would add indirection without preventing
    // any drift. Everything else has to justify itself.
    const zero = r'0(\.0)?';
    final banned = <String, RegExp>{
      'SizedBox spacing': RegExp(
        r'SizedBox\((height|width): (?!'
        '$zero'
        r'\b)\d',
      ),
      'EdgeInsets.all': RegExp(
        r'EdgeInsets\.all\((?!'
        '$zero'
        r'\))\d',
      ),
      'EdgeInsets edge': RegExp(
        r'\b(horizontal|vertical|left|right|top|bottom): (?!'
        '$zero'
        r'\b)\d',
      ),
      'fontSize': RegExp(r'fontSize: \d'),
      'radius': RegExp(
        r'(BorderRadius|Radius)\.circular\((?!'
        '$zero'
        r'\))\d',
      ),
      'strokeWidth': RegExp(
        r'strokeWidth: (?!'
        '$zero'
        r'\b)\d',
      ),
      'spacing/dimension': RegExp(
        r'\b(spacing|dimension): (?!'
        '$zero'
        r'\b)\d',
      ),
    };

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final posix = entity.path.replaceAll('\\', '/');
      // The scale itself, and generated localisations nobody edits by hand.
      if (posix.endsWith('theme/takhi_theme.dart')) continue;
      if (posix.contains('/l10n/')) continue;
      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // A named constant is the sanctioned escape hatch, so its own
        // declaration is not an offence -- only using a bare number where a
        // token belongs is.
        //
        // The right-hand side must be a *number* and nothing else. Exempting
        // every `const x = ...` line, as the first version of this did, let
        // `const _probe = SizedBox(height: 13);` through -- which is not a
        // named measurement, it is a raw literal wearing a name. That version
        // passed its own mutation probe, i.e. it was a hollow guard.
        if (RegExp(
          r'^\s*(static )?const \w+ = -?\d+(\.\d+)?;',
        ).hasMatch(line)) {
          continue;
        }
        for (final entry in banned.entries) {
          if (entry.value.hasMatch(line)) {
            offenders.add(
              '${entity.path}:${i + 1} (${entry.key}): '
              '${line.trim()}',
            );
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Raw sizes outside theme/takhi_theme.dart. Use TakhiSpace / '
          'TakhiRadius / TakhiType / TakhiStroke -- or, for a genuinely '
          'one-off measurement, a named file-level constant that says why. '
          'See docs/design/TOKENS.md:\n${offenders.join('\n')}',
    );
  });
}
