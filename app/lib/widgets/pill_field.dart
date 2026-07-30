// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';
import 'accent_dot.dart';

/// Diameter of the leading accent disc.
const _kDotSize = 22.0;

/// Minimum height of the capsule. Above [TakhiTouch.minTarget] because a
/// pill this wide looks starved at exactly 48 -- but the floor is what makes
/// the tappable variant safe, so it is expressed as a minimum and never as a
/// fixed height. A field whose text wraps grows instead of clipping.
const _kMinHeight = 52.0;

/// The capsule that starts every input in the app.
///
/// One shape covers both halves of a taxi app's most common interaction:
/// tapping a "where to?" row that opens a picker, and typing into a search
/// box. They look identical on purpose -- a rider should not have to learn
/// that one rounded bar accepts text and the visually identical one beside
/// it does not.
///
/// Which one you get is decided by what you pass, not by a mode flag:
///
/// * a [controller] (or an [onChanged]) makes it a real [TextField], with
///   [placeholder] as the hint and [text] ignored;
/// * otherwise it is a static row showing [text], falling back to
///   [placeholder] in the muted colour when [text] is null or empty, and
///   tappable when [onTap] is given.
///
/// Both variants clear [TakhiTouch.minTarget]. The tappable variant puts the
/// whole capsule -- dot, text and [trailing] alike -- inside one gesture
/// target, so there is no small hot zone to aim at.
class PillField extends StatelessWidget {
  /// The glyph in the leading disc: a pin for a destination, a magnifier for
  /// a search, a clock for a time.
  final IconData icon;

  /// Colour family of the leading disc. The rest of the capsule stays
  /// neutral -- the accent is a marker, not a background.
  final TakhiAccent accent;

  /// The value to display in the read-only variant. Ignored when the field
  /// is editable; use [controller] for that.
  final String? text;

  /// Shown in the muted colour when there is no value yet -- the hint of the
  /// editable variant and the empty state of the tappable one.
  ///
  /// User-visible: pass a localised string.
  final String? placeholder;

  /// Supplying this (or [onChanged]) turns the capsule into a [TextField].
  final TextEditingController? controller;

  /// Called on every keystroke of the editable variant. Supplying this alone
  /// is enough to make the field editable, for a caller that keeps the value
  /// in its own state rather than in a controller.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits from the keyboard. Editable variant only.
  final ValueChanged<String>? onSubmitted;

  /// Keyboard type for the editable variant.
  final TextInputType? keyboardType;

  /// Whether the editable variant takes focus as soon as it is shown.
  final bool autofocus;

  /// How many lines the editable variant may grow to before it starts
  /// scrolling. One by default, which is a capsule with one value in it.
  ///
  /// Raise it for a field whose *single* value is simply long -- "Цагаан
  /// Toyota Prius 30, 1234УБА" is one answer and does not fit one line of a
  /// 390dp phone. A one-line `TextField` handles that by scrolling
  /// horizontally to the caret, so the driver checking their own offer
  /// before sending it sees «ан Toyota Prius 30, 1234УБА» with no ellipsis
  /// and no way to tell whether the app or their typing lost the first
  /// word. Wrapping keeps the whole value on screen; the capsule grows,
  /// because [_kMinHeight] is a floor and not a height.
  ///
  /// This is not the multi-line *input* case. A field that expects a
  /// paragraph is `LabeledField` with three lines or more, which draws a
  /// card-cornered well instead of a capsule.
  final int maxLines;

  /// Makes the read-only variant tappable. Ignored by the editable variant,
  /// where the tap belongs to the text cursor.
  final VoidCallback? onTap;

  /// Optional widget pinned to the right edge -- a chevron, a clear button,
  /// a short unit. Kept inside the capsule's own gesture target, so it is
  /// decoration unless it handles its own taps.
  final Widget? trailing;

  /// Announced instead of the visible text, for the tappable variant where
  /// the label alone ("Хаана очих вэ?") does not say that tapping it opens a
  /// picker.
  ///
  /// User-visible: pass a localised string.
  final String? semanticsLabel;

  const PillField({
    super.key,
    required this.icon,
    this.accent = TakhiAccent.gold,
    this.text,
    this.placeholder,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.autofocus = false,
    this.maxLines = 1,
    this.onTap,
    this.trailing,
    this.semanticsLabel,
  });

  /// True when this instance was configured as a text input rather than as a
  /// tappable row.
  bool get _isEditable => controller != null || onChanged != null;

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final decoration = BoxDecoration(
      color: surfaces.field,
      borderRadius: TakhiRadius.pillAll,
      border: Border.all(color: surfaces.hairline),
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TakhiSpace.md,
        vertical: TakhiSpace.sm,
      ),
      child: Row(
        children: [
          AccentDot(icon: icon, accent: accent, size: _kDotSize),
          const SizedBox(width: TakhiSpace.sm),
          Expanded(child: _body(surfaces)),
          if (trailing != null) ...[
            const SizedBox(width: TakhiSpace.xs),
            trailing!,
          ],
        ],
      ),
    );

    final capsule = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _kMinHeight),
      child: DecoratedBox(decoration: decoration, child: content),
    );

    if (_isEditable || onTap == null) return capsule;

    // Material, not GestureDetector: the ripple is clipped to the capsule so
    // the feedback matches the shape the user pressed.
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: TakhiRadius.pillAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: TakhiRadius.pillAll,
          child: capsule,
        ),
      ),
    );
  }

  Widget _body(TakhiSurfaces surfaces) {
    if (_isEditable) {
      return TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        keyboardType: keyboardType,
        autofocus: autofocus,
        maxLines: maxLines,
        style: TakhiType.title.copyWith(color: surfaces.onSheet),
        cursorColor: surfaces.onSheet,
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TakhiType.title.copyWith(color: surfaces.muted),
          // The capsule already draws the fill, the border and the padding;
          // anything Material would add here shows up as a second box
          // inside the first one.
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      );
    }

    final value = text;
    final hasValue = value != null && value.isNotEmpty;
    return Text(
      hasValue ? value : (placeholder ?? ''),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TakhiType.title.copyWith(
        color: hasValue ? surfaces.onSheet : surfaces.muted,
      ),
    );
  }
}
