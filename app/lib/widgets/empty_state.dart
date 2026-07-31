// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';
import 'accent_dot.dart';

/// Diameter of the mark that stands for the whole state.
///
/// Large enough to be the thing the eye lands on. Below roughly this size an
/// empty screen reads as a heading floating over blank paper -- which is the
/// shape a screen that *failed to load* has, not the shape of one that is
/// working and simply has nothing to list yet.
const _kMarkSize = 72.0;

/// What a list says while it is legitimately empty.
///
/// A tinted mark, a heading, and one sentence saying why nothing is here and
/// what will fill it. It exists because "no rows yet" and "this screen is
/// broken" look identical when the answer is an empty rectangle, and this
/// app has three places that are legitimately empty for minutes at a time:
/// the offers list while a request is out, the driver's own trip journal
/// before their first run, and any list that is waiting on other people.
///
/// Deliberately still -- no spinner, no repeating animation. A spinner
/// promises something is being *fetched*, which is usually a lie here (the
/// request is already out; the app is waiting on other people), and a
/// permanently-animating widget makes `pumpAndSettle` hang in every test
/// that passes through the screen.
///
/// [message] is a full sentence, not a second title: it has to answer "so
/// what happens now?". If there is nothing to say beyond the heading, the
/// screen probably wants a [SectionHeading] rather than this.
class EmptyState extends StatelessWidget {
  /// The glyph inside the mark.
  final IconData icon;

  /// The heading. User-visible: pass a localised string.
  final String title;

  /// The sentence under it, saying what will put rows here. User-visible:
  /// pass a localised string.
  final String message;

  /// Colour family of the mark. Gold -- the user's own things -- is the
  /// right default; reach for another only when the emptiness means
  /// something ([TakhiAccent.clay] for a state that is a caveat rather than
  /// a normal beginning).
  final TakhiAccent accent;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent = TakhiAccent.gold,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AccentDot(icon: icon, accent: accent, size: _kMarkSize),
          const SizedBox(height: TakhiSpace.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TakhiType.heading.copyWith(color: surfaces.onSheet),
          ),
          const SizedBox(height: TakhiSpace.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TakhiType.body.copyWith(color: surfaces.muted),
          ),
        ],
      ),
    );
  }
}
