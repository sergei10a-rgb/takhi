// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// Width and thickness of the drag handle. Small enough to read as an
/// affordance rather than a divider, wide enough to look grabbable.
const _kHandleWidth = 40.0;
const _kHandleHeight = 4.0;

/// The panel that floats over a full-bleed map.
///
/// This is the app's primary layout surface: the map fills the screen and
/// everything the user actually operates lives on a sheet drawn over it,
/// anchored to the bottom edge. It is a *painted* sheet, not a modal route --
/// it does not push, animate in, or take over the back gesture, so a screen
/// can keep it permanently on screen alongside a live map without touching
/// navigation at all.
///
/// Three things it guarantees so call sites do not have to:
///
/// 1. it hugs its content ([Column] with `MainAxisSize.min`), so a sheet with
///    two rows in it is short and a sheet with a list in it is tall, with no
///    fixed heights or fractions anywhere;
/// 2. it keeps its content clear of the system gesture inset at the bottom,
///    which is where a primary button would otherwise land;
/// 3. it separates itself from the map correctly in both brightnesses -- a
///    soft shadow in light, a hairline in dark, because a shadow cast onto a
///    near-black map is not visible at any opacity worth using.
///
/// For a scrolling body, pass a bounded scrollable as [child] (a
/// `ConstrainedBox` around a `ListView`, or a `SingleChildScrollView` with
/// `shrinkWrap`-like bounds); the sheet itself never scrolls.
class TakhiSheet extends StatelessWidget {
  /// The sheet's contents. Laid out at full width; the sheet supplies the
  /// horizontal padding via [padding].
  final Widget child;

  /// Whether to draw the drag handle across the top.
  ///
  /// The handle is a *signal*, not a control -- this widget never moves. Set
  /// it to false for a sheet that genuinely cannot be dismissed or resized,
  /// so the app never shows a grab bar for something ungrabbable.
  final bool showHandle;

  /// Padding around [child], inside the sheet's own rounded edge. Defaults
  /// to the standard gutter on all four sides; the bottom gets the system
  /// inset added to it on top of whatever is passed here.
  final EdgeInsetsGeometry padding;

  const TakhiSheet({
    super.key,
    required this.child,
    this.showHandle = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: TakhiSpace.md,
      vertical: TakhiSpace.lg,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    // Only the bottom inset: the sheet is anchored to the bottom edge, and
    // padding the top would open a gap between the handle and the corner.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.sheet,
        borderRadius: TakhiRadius.sheetTop,
        border: Border.all(color: surfaces.hairline),
        boxShadow: surfaces.sheetShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHandle)
            Padding(
              padding: const EdgeInsets.only(top: TakhiSpace.sm),
              child: Center(
                child: Container(
                  width: _kHandleWidth,
                  height: _kHandleHeight,
                  decoration: BoxDecoration(
                    // Derived from `muted` rather than named separately: the
                    // handle is a quiet mark on the sheet, and one that
                    // tracks the supporting-text colour stays quiet in both
                    // brightnesses without a token of its own.
                    color: surfaces.muted.withValues(alpha: 0.35),
                    borderRadius: TakhiRadius.pillAll,
                  ),
                ),
              ),
            ),
          Padding(
            padding: padding.add(EdgeInsets.only(bottom: bottomInset)),
            child: child,
          ),
        ],
      ),
    );
  }
}
