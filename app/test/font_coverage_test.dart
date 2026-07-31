// SPDX-License-Identifier: AGPL-3.0-or-later

/// The mechanical half of the ▯ rule.
///
/// Two of the three bugs this project has ever found by *looking at a
/// picture* were missing glyphs: «Түр зогсоох» drawn as `▯▯▯ ▯▯▯▯▯▯▯`
/// (565 tests green at the time), and the fare estimate drawn as
/// `▯ 9 322 ₮`. Both got in the same way. `find.text('Түр зогсоох')` matches
/// a row of empty boxes exactly as happily as it matches the words, so no
/// widget test can see the difference; and on a real phone the platform's
/// own font fallback quietly supplies whatever the bundled face is missing,
/// so nobody notices there either -- until the app runs somewhere without
/// that fallback, which is every screenshot this repo takes.
///
/// The screenshot rule (docs/design/SCREENSHOT_RULE.md) catches this by
/// asking a human to look. That works and it is worth keeping, but it is a
/// human remembering to look, and the second occurrence proves what that is
/// worth. This is the same check done by machine: every character the app
/// can put on screen, against the cmap of the font the app actually ships.
///
/// **Scope, and why it stops there.** The `.arb` files are where the app's
/// user-visible text lives -- `l10n_completeness_test.dart` already enforces
/// that every one of those keys is wired to the UI, and the audit forbids
/// user-visible literals elsewhere. A Dart-source scan was considered and
/// dropped: the only non-`.arb` matches in this repo are inside comments and
/// doc strings (`→`, `≤`, `③`), which is exactly the false-positive class
/// that makes a guard get switched off.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The face `pubspec.yaml` bundles and `takhiTheme` sets on every widget.
const _fontPath = 'assets/fonts/NotoSans-Regular.ttf';

/// The translation sources. Not the generated `app_localizations*.dart`,
/// which are these files re-emitted as Dart.
const _arbPaths = ['lib/l10n/app_mn.arb', 'lib/l10n/app_en.arb'];

/// Characters the text shaper resolves itself instead of asking the font
/// for a glyph: ordinary and non-breaking spaces, tabs, newlines, the
/// zero-width space and the line/paragraph separators. A font may legally
/// have no cmap entry for any of them and still lay text out correctly, so
/// flagging them would be a false positive -- and one guaranteed to fire,
/// since money in this app is written with a non-breaking space in it.
const _shapedWhitespace = <int>{
  0x09,
  0x0A,
  0x0D,
  0x20,
  0xA0,
  0x200B,
  0x2028,
  0x2029,
  0x202F,
  0xFEFF,
};

/// Resolves a codepoint to a glyph id in [fontBytes], or 0 for "this font
/// cannot draw that character".
///
/// A deliberately small TrueType reader: the table directory, the `cmap`
/// table, and the two subtable formats a modern font actually uses --
/// format 4 (the BMP one every font has) and format 12 (the full-Unicode
/// one). Nothing else in a font file is needed to answer the only question
/// asked here.
typedef _GlyphLookup = int Function(int codepoint);

_GlyphLookup _cmapLookup(Uint8List fontBytes) {
  final data = ByteData.sublistView(fontBytes);

  // Table directory: sfntVersion (4 bytes), numTables, then 16-byte records
  // of tag / checksum / offset / length.
  final numTables = data.getUint16(4);
  var cmapOffset = -1;
  for (var i = 0; i < numTables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(fontBytes.sublist(record, record + 4));
    if (tag == 'cmap') cmapOffset = data.getUint32(record + 8);
  }
  if (cmapOffset < 0) {
    throw StateError('$_fontPath has no cmap table');
  }

  // Encoding records, best Unicode subtable wins: a full-Unicode format 12
  // over a BMP-only format 4, and a Unicode platform over a Windows one.
  final subtableCount = data.getUint16(cmapOffset + 2);
  var chosen = -1;
  var chosenFormat = -1;
  var chosenScore = -1;
  for (var i = 0; i < subtableCount; i++) {
    final record = cmapOffset + 4 + i * 8;
    final platform = data.getUint16(record);
    final encoding = data.getUint16(record + 2);
    final subtable = cmapOffset + data.getUint32(record + 4);
    final format = data.getUint16(subtable);
    if (format != 4 && format != 12) continue;
    final score = switch ((platform, encoding)) {
      (3, 10) => 4, // Windows, UCS-4
      (0, 4) || (0, 6) => 4, // Unicode, full repertoire
      (3, 1) => 3, // Windows, BMP
      (0, _) => 2, // Unicode, anything else
      _ => 0,
    };
    if (score > chosenScore) {
      chosenScore = score;
      chosen = subtable;
      chosenFormat = format;
    }
  }
  if (chosen < 0) {
    throw StateError('$_fontPath has no format 4 or 12 Unicode cmap subtable');
  }

  return chosenFormat == 12
      ? (codepoint) => _glyphFormat12(data, chosen, codepoint)
      : (codepoint) => _glyphFormat4(data, chosen, codepoint);
}

/// Segment-mapped BMP lookup (cmap format 4).
int _glyphFormat4(ByteData data, int subtable, int codepoint) {
  if (codepoint > 0xFFFF) return 0;
  final segCountX2 = data.getUint16(subtable + 6);
  final segCount = segCountX2 ~/ 2;
  final endBase = subtable + 14;
  // +2 for the reservedPad word between the end and start arrays.
  final startBase = endBase + segCountX2 + 2;
  final deltaBase = startBase + segCountX2;
  final rangeOffsetBase = deltaBase + segCountX2;

  for (var i = 0; i < segCount; i++) {
    if (codepoint > data.getUint16(endBase + 2 * i)) continue;
    final start = data.getUint16(startBase + 2 * i);
    if (codepoint < start) return 0; // segments are sorted; past it already
    final delta = data.getInt16(deltaBase + 2 * i);
    final rangeOffset = data.getUint16(rangeOffsetBase + 2 * i);
    if (rangeOffset == 0) return (codepoint + delta) & 0xFFFF;
    // The glyph id array is addressed *relative to the idRangeOffset slot
    // itself* -- the one genuinely odd corner of this format.
    final index =
        rangeOffsetBase + 2 * i + rangeOffset + 2 * (codepoint - start);
    if (index + 1 >= data.lengthInBytes) return 0;
    final glyph = data.getUint16(index);
    return glyph == 0 ? 0 : (glyph + delta) & 0xFFFF;
  }
  return 0;
}

/// Segmented coverage lookup (cmap format 12).
int _glyphFormat12(ByteData data, int subtable, int codepoint) {
  final groupCount = data.getUint32(subtable + 12);
  for (var i = 0; i < groupCount; i++) {
    final group = subtable + 16 + i * 12;
    final start = data.getUint32(group);
    if (codepoint < start) return 0; // groups are sorted
    if (codepoint <= data.getUint32(group + 4)) {
      return data.getUint32(group + 8) + (codepoint - start);
    }
  }
  return 0;
}

String _describe(int codepoint) =>
    'U+${codepoint.toRadixString(16).toUpperCase().padLeft(4, '0')} '
    '"${String.fromCharCode(codepoint)}"';

void main() {
  late _GlyphLookup glyph;

  setUpAll(() {
    glyph = _cmapLookup(File(_fontPath).readAsBytesSync());
  });

  // Without this the whole file is worthless in the one way that matters:
  // a reader that returned a non-zero glyph for everything would pass the
  // real check silently and for ever. So it is asked one question it must
  // answer yes to, one it must answer no to, and both answers are facts
  // about this exact file.
  test('the cmap reader can tell a present character from an absent one', () {
    // Ө and ₮ -- Cyrillic and the төгрөг mark, both all over the app.
    expect(glyph(0x04E8), isNonZero, reason: 'Ө must be in the bundled font');
    expect(glyph(0x20AE), isNonZero, reason: '₮ must be in the bundled font');
    // ≈ is the character that shipped as ▯ on the taximeter's estimate chip.
    // If this ever starts passing, the font gained a glyph -- delete the
    // expectation, do not weaken the check above it.
    expect(
      glyph(0x2248),
      isZero,
      reason:
          'This subset genuinely lacks ≈ (U+2248). A reader that claims '
          'otherwise is not reading the cmap.',
    );
  });

  test('every character in every translation exists in the bundled font -- '
      'no string can reach a screen as ▯', () {
    final missing = <String>[];
    for (final path in _arbPaths) {
      final entries =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      for (final entry in entries.entries) {
        // `@@locale` and per-key `@key` blocks are ARB tooling metadata --
        // descriptions for translators, never drawn.
        if (entry.key.startsWith('@')) continue;
        final value = entry.value;
        if (value is! String) continue;
        for (final codepoint in value.runes) {
          if (_shapedWhitespace.contains(codepoint)) continue;
          if (glyph(codepoint) != 0) continue;
          missing.add('$path :: ${entry.key} :: ${_describe(codepoint)}');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'These characters have no glyph in $_fontPath, so they render as '
          'an empty box wherever the platform has no fallback font -- which '
          'is every design screenshot, and any device with a thin font set. '
          'Rewrite the string with characters the face carries (a word '
          'usually beats a sign), or extend the bundled subset:\n'
          '${missing.join('\n')}',
    );
  });
}
