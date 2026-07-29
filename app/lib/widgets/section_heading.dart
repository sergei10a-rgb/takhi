// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// The two-tier title that opens a block of content.
///
/// A heavy dark line, and under it a lighter grey one that qualifies it.
/// This is the app's main instrument of hierarchy: the direction has almost
/// no rules, dividers or boxes in it, so what tells one block from the next
/// is the size and weight jump at the top of each.
///
/// The [subtitle] is optional but is not filler. The pattern it serves is a
/// question and its context -- "Хаашаа явах вэ?" over "Одоогийн байршлаас" --
/// which is how a screen states what it wants without a paragraph of body
/// text. If there is nothing to qualify, leave it out; a subtitle that
/// merely restates the title is worse than none.
///
/// Use [compact] for a heading inside an already-titled sheet, where the
/// full display size would compete with the sheet's own headline.
class SectionHeading extends StatelessWidget {
  /// The heavy line. User-visible: pass a localised string.
  final String title;

  /// The muted line beneath. User-visible: pass a localised string.
  final String? subtitle;

  /// Optional widget at the right edge, vertically centred against the
  /// title -- an "all" link, a count, a small control.
  final Widget? trailing;

  /// Drops the title from [TakhiType.display] to [TakhiType.heading], for a
  /// subordinate heading inside a block that already has one.
  final bool compact;

  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final titleStyle = compact ? TakhiType.heading : TakhiType.display;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle.copyWith(color: surfaces.onSheet)),
              if (subtitle != null) ...[
                const SizedBox(height: TakhiSpace.xxs),
                Text(
                  subtitle!,
                  style: TakhiType.support.copyWith(color: surfaces.muted),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: TakhiSpace.sm),
          // Aligned to the title's own line rather than to the whole block,
          // so a trailing control does not drift downward when a subtitle
          // is present.
          Padding(
            padding: const EdgeInsets.only(top: TakhiSpace.xxs),
            child: trailing,
          ),
        ],
      ],
    );
  }
}
