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
}
