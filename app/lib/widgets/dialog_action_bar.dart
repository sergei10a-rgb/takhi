// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/takhi_theme.dart';

// The tone lives with the palette it resolves against (theme/takhi_theme.dart
// is the one file allowed to know hex values), but it is part of this
// widget's API -- re-exported so a call site needs one import, not two.
export '../theme/takhi_theme.dart' show DialogActionTone;

/// Gap between the two actions while they sit side by side. Wide enough
/// that a thumb aiming for one cannot clip the other.
const _kRowSpacing = 24.0;

/// Gap between the two actions once they have stacked. Deliberately much
/// tighter than [_kRowSpacing]: stacked buttons are full width, so there is
/// no mis-tap to guard against, and a big gap would push the safe answer
/// off a short screen.
const _kStackSpacing = 8.0;

/// Smallest comfortable tap target. A *minimum*, never a fixed height --
/// a label that wraps has to be allowed to make its button taller.
const _kMinActionHeight = 48.0;

/// One of the two answers a confirmation dialog offers.
@immutable
class DialogAction {
  /// The full, untruncated label. Nothing in [DialogActionBar] will
  /// shorten, ellipsise or shrink it, so this is exactly what the user
  /// reads.
  final String label;

  /// How loud this answer is allowed to be -- see [DialogActionTone] for
  /// the rule that decides.
  final DialogActionTone tone;

  /// `null` disables the action without hiding it, so a dialog can show
  /// why an answer is unavailable rather than removing the button and
  /// leaving a gap where it was.
  final VoidCallback? onPressed;

  /// Swaps the label for a spinner *without* changing the button's width,
  /// for an answer whose work outlives the tap (publishing an offer to the
  /// relays). Taps are refused while it is true.
  final bool busy;

  const DialogAction({
    required this.label,
    required this.tone,
    required this.onPressed,
    this.busy = false,
  });
}

/// The action row shared by every confirmation dialog in Тахь.
///
/// It exists because Mongolian action labels run roughly twice as long as
/// the English ones Material's defaults were sized for -- "Тийм,
/// үргэлжлүүл" for "Yes, continue" -- and the stock [OverflowBar] answers
/// that badly in three ways at once: it keeps stacked buttons at their
/// natural width instead of filling the sheet, it stacks them in reading
/// order (leaving the dangerous answer at the bottom, under the thumb that
/// just swiped back), and it gives them no room to grow when a single
/// label needs two lines.
///
/// The rule this widget implements instead:
///
/// 1. both labels fit on one line, side by side -> a row, [dismiss] on the
///    left, [_kRowSpacing] apart;
/// 2. they do not -> a full-width stack, [_kStackSpacing] apart, in
///    *reverse* order: [proceed] on top and [dismiss] at the bottom.
///    The dialog was opened by a downward back gesture and that motion
///    carries on downward, so the answer waiting under the thumb has to be
///    the safe one;
/// 3. a single label is still too wide for a full-width button -> it wraps
///    onto another line and the button grows ([_kMinActionHeight] is a
///    floor, not a fixed height).
///
/// Truncation is never one of the outcomes: no ellipsis, no [FittedBox],
/// no shrink-to-fit, no abbreviating the label at the call site. A rider
/// deciding whether to give a stranger their exact pickup coordinates has
/// to be able to read both answers in full.
///
/// Pass it as the single entry of `AlertDialog.actions`; it sizes itself
/// to the action area and needs no [OverflowBar] behaviour of its own.
class DialogActionBar extends StatelessWidget {
  /// The answer that changes nothing -- "Цуцлах", "Үлдэх". Always the
  /// left-hand button in a row and the bottom one in a stack.
  final DialogAction dismiss;

  /// The answer that acts -- "Гарах", "Тийм, үргэлжлүүл".
  final DialogAction proceed;

  const DialogActionBar({
    super.key,
    required this.dismiss,
    required this.proceed,
  });

  @override
  Widget build(BuildContext context) => _AdaptiveActionLayout(
    // Reading order, not visual order: the render object below flips the
    // pair itself when it stacks them.
    children: [_button(context, dismiss), _button(context, proceed)],
  );

  Widget _button(BuildContext context, DialogAction action) {
    final colors = dialogActionColors(
      action.tone,
      Theme.of(context).colorScheme,
    );
    final label = Text(
      action.label,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    // The label stays in the tree at zero opacity rather than being
    // replaced, so that starting the work cannot change the button's
    // width -- and so cannot flip a fitting row into a stack mid-tap.
    final child = action.busy
        ? Stack(
            alignment: Alignment.center,
            children: [
              Opacity(opacity: 0, child: label),
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: colors.foreground,
                ),
              ),
            ],
          )
        : label;
    final onPressed = action.busy ? null : action.onPressed;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    const minimumSize = Size(64, _kMinActionHeight);

    final background = colors.background;
    if (background == null) {
      return TextButton(
        style: TextButton.styleFrom(
          foregroundColor: colors.foreground,
          disabledForegroundColor: colors.foreground.withValues(alpha: 0.45),
          minimumSize: minimumSize,
          padding: padding,
          shape: shape,
        ),
        onPressed: onPressed,
        child: child,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        foregroundColor: colors.foreground,
        backgroundColor: background,
        disabledForegroundColor: colors.foreground.withValues(alpha: 0.45),
        disabledBackgroundColor: background.withValues(alpha: 0.45),
        minimumSize: minimumSize,
        padding: padding,
        shape: shape,
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

/// Exactly two children, laid out per [DialogActionBar]'s three-tier rule.
///
/// Written as a render object rather than a `LayoutBuilder` because
/// `AlertDialog` wraps its whole column in an [IntrinsicWidth], and a
/// `LayoutBuilder` asserts when asked for an intrinsic dimension. Doing
/// the measuring here means the dialog can still size itself to the row it
/// would prefer, and only then find out it did not get that much room.
class _AdaptiveActionLayout extends MultiChildRenderObjectWidget {
  const _AdaptiveActionLayout({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAdaptiveActionLayout();
}

class _ActionParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAdaptiveActionLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ActionParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ActionParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ActionParentData) {
      child.parentData = _ActionParentData();
    }
  }

  /// `(dismiss, proceed)` -- the order they were handed to us, which is
  /// also the order they read in a row.
  (RenderBox, RenderBox) get _pair {
    assert(
      childCount == 2,
      'DialogActionBar lays out exactly two actions, got $childCount',
    );
    final dismiss = firstChild!;
    return (dismiss, childAfter(dismiss)!);
  }

  /// Width the pair would take on one line each, unwrapped. Measured from
  /// intrinsics rather than from a trial layout: laying a child out
  /// against the available width would let a too-long label wrap and
  /// report a width that *does* fit, and we would keep it in a row with
  /// one button silently twice as tall as the other.
  double get _naturalRowWidth {
    final (dismiss, proceed) = _pair;
    return dismiss.getMaxIntrinsicWidth(double.infinity) +
        _kRowSpacing +
        proceed.getMaxIntrinsicWidth(double.infinity);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final (dismiss, proceed) = _pair;
    // Stacked: each button still needs its own minimum on its own line.
    return math.max(
      dismiss.getMinIntrinsicWidth(height),
      proceed.getMinIntrinsicWidth(height),
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) => _naturalRowWidth;

  @override
  double computeMinIntrinsicHeight(double width) => _heightFor(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightFor(width);

  double _heightFor(double width) {
    final (dismiss, proceed) = _pair;
    if (width.isInfinite || _naturalRowWidth <= width) {
      return math.max(
        dismiss.getMaxIntrinsicHeight(double.infinity),
        proceed.getMaxIntrinsicHeight(double.infinity),
      );
    }
    return dismiss.getMaxIntrinsicHeight(width) +
        _kStackSpacing +
        proceed.getMaxIntrinsicHeight(width);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  void performLayout() {
    size = _layout(constraints, dry: false);
  }

  /// Shared by [performLayout] and [computeDryLayout] so the two can never
  /// disagree about which tier applies.
  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final (dismiss, proceed) = _pair;
    final maxWidth = constraints.maxWidth;

    Size measure(RenderBox child, BoxConstraints childConstraints) {
      if (dry) return child.getDryLayout(childConstraints);
      child.layout(childConstraints, parentUsesSize: true);
      return child.size;
    }

    void place(RenderBox child, Offset offset) {
      if (!dry) (child.parentData! as _ActionParentData).offset = offset;
    }

    if (_naturalRowWidth <= maxWidth) {
      // Tier 1: side by side, each at its natural width.
      final loose = BoxConstraints(maxWidth: maxWidth);
      final dismissSize = measure(dismiss, loose);
      final proceedSize = measure(proceed, loose);
      final height = math.max(dismissSize.height, proceedSize.height);
      place(dismiss, Offset(0, (height - dismissSize.height) / 2));
      place(
        proceed,
        Offset(
          dismissSize.width + _kRowSpacing,
          (height - proceedSize.height) / 2,
        ),
      );
      return constraints.constrain(
        Size(dismissSize.width + _kRowSpacing + proceedSize.width, height),
      );
    }

    // Tiers 2 and 3: full-width stack, dangerous answer on top. Tier 3 --
    // a label that needs two lines -- needs no branch of its own: a tight
    // width is all it takes for the label to wrap and the button to grow
    // with it.
    final full = BoxConstraints.tightFor(width: maxWidth);
    final proceedSize = measure(proceed, full);
    final dismissSize = measure(dismiss, full);
    place(proceed, Offset.zero);
    place(dismiss, Offset(0, proceedSize.height + _kStackSpacing));
    return constraints.constrain(
      Size(maxWidth, proceedSize.height + _kStackSpacing + dismissSize.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
