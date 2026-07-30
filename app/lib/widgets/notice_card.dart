// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// One sentence the screen needs the user to read, given a plane of its own.
///
/// A tinted panel, a glyph in the accent's deep foreground, and the sentence
/// beside it. This is what a screen says when the answer is not a heading
/// and not a row -- "your fare was not confirmed, so no receipt exists",
/// "location is off, so nothing can be tracked". Every such statement in the
/// app had otherwise been a bare line of grey text floating on the page,
/// which is the shape a *missing* screen has.
///
/// The pair of colours comes from [takhiAccentColors], so the glyph and the
/// words clear WCAG AA on the tint in both brightnesses without the call
/// site choosing anything but a meaning: [TakhiAccent.clay] for a caveat,
/// [TakhiAccent.steppe] for a confirmation, [TakhiAccent.sky] for a plain
/// fact.
class NoticeCard extends StatelessWidget {
  /// The glyph in the accent's foreground colour.
  final IconData icon;

  /// The sentence. User-visible: pass a localised string.
  final String text;

  /// Which colour family carries it. Deliberately required -- a notice with
  /// no opinion about what kind of news it is has not been thought about.
  final TakhiAccent accent;

  const NoticeCard({
    super.key,
    required this.icon,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = takhiAccentColors(accent, Theme.of(context).brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tint,
        borderRadius: TakhiRadius.cardAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.onTint),
            const SizedBox(width: TakhiSpace.sm),
            Expanded(
              child: Text(
                text,
                style: TakhiType.body.copyWith(color: colors.onTint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
