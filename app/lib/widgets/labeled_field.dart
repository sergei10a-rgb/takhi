// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';
import 'pill_field.dart';

/// The most lines an input may take while still being drawn as a capsule.
/// Past this it is a paragraph, and a paragraph gets the card-cornered well.
const _kMaxCapsuleLines = 2;

/// One input, with everything the user needs in order to answer it.
///
/// A standing label, the capsule, an optional line saying what the value is
/// *for*, and an optional verdict when the last save attempt refused it.
///
/// The label stands **above** the capsule rather than floating inside
/// Material's border. A floating label slides out of the way the moment the
/// field has a value, which is exactly when it is needed: a driver looking
/// at `1500` has to be able to tell whether that is the per-kilometre rate
/// or the per-minute one without clearing the box to find out. Every form in
/// this app had been built out of bare `TextField`s with
/// `OutlineInputBorder` and a `labelText`, and every one of them lost its
/// labels the instant it was filled in.
///
/// [hint] is the other half of the same idea. A form that only names its
/// fields tells the user what to type but never why -- "Км-тариф" does not
/// say that the number decides what a metered trip charges. Where that is
/// not obvious from the label, say it here in one line.
///
/// The capsule itself is [PillField], so an input on a form and an input on
/// a sheet are visibly the same object.
class LabeledField extends StatelessWidget {
  /// The small standing label above the capsule. User-visible: pass a
  /// localised string.
  final String label;

  /// The glyph in the capsule's leading disc.
  final IconData icon;

  /// Colour family of that disc.
  final TakhiAccent accent;

  final TextEditingController controller;
  final TextInputType? keyboardType;

  /// Placeholder inside the capsule while it is empty. Optional: the
  /// standing [label] already names the field, so this is for an example
  /// value rather than for a repeat of the label.
  final String? placeholder;

  /// Called on every keystroke -- forms use it to re-evaluate whether the
  /// save button can be enabled.
  final ValueChanged<String>? onChanged;

  /// The quiet line under the capsule: what the value is for, or what
  /// leaving it blank means. `null` where the label says everything.
  final String? hint;

  /// Why the last attempt refused this field, in the error colour. `null`
  /// while nothing is wrong.
  final String? errorText;

  /// Number of visible lines, and with it which shape the input takes.
  ///
  /// One or two keep the [PillField] capsule: two is not a multi-line input,
  /// it is one value long enough to need a second line ("Цагаан Toyota
  /// Prius 30, 1234УБА" is a single answer that does not fit 390dp). Left at
  /// one, a `TextField` deals with that by scrolling horizontally to the
  /// caret, which silently eats the front of the value with no ellipsis to
  /// say so.
  ///
  /// Three or more is a genuine paragraph field, and there the capsule stops
  /// being right: a tall box with fully round ends wastes both corners of
  /// every line but the first, so it becomes a card-cornered well and drops
  /// the leading disc (a marker pinned to the first line of a three-line box
  /// reads as a bullet rather than as part of the field).
  final int maxLines;

  /// Takes focus as soon as it is shown.
  final bool autofocus;

  const LabeledField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.accent = TakhiAccent.gold,
    this.keyboardType,
    this.placeholder,
    this.onChanged,
    this.hint,
    this.errorText,
    this.maxLines = 1,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final scheme = Theme.of(context).colorScheme;
    final explanation = hint;
    final error = errorText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TakhiType.micro.copyWith(color: surfaces.muted)),
        const SizedBox(height: TakhiSpace.xs),
        if (maxLines <= _kMaxCapsuleLines)
          PillField(
            icon: icon,
            accent: accent,
            controller: controller,
            keyboardType: keyboardType,
            placeholder: placeholder,
            onChanged: onChanged,
            autofocus: autofocus,
            maxLines: maxLines,
          )
        else
          _MultilineWell(
            controller: controller,
            keyboardType: keyboardType,
            placeholder: placeholder,
            onChanged: onChanged,
            maxLines: maxLines,
            autofocus: autofocus,
          ),
        // Verdict first, explanation second: an error belongs against the
        // box it refused, and pushing it below a standing hint moves it a
        // line further from that box on some fields and not on others.
        if (error != null) ...[
          const SizedBox(height: TakhiSpace.xs),
          Text(error, style: TakhiType.support.copyWith(color: scheme.error)),
        ],
        if (explanation != null) ...[
          const SizedBox(height: TakhiSpace.xs),
          Text(
            explanation,
            style: TakhiType.support.copyWith(color: surfaces.muted),
          ),
        ],
      ],
    );
  }
}

/// The multi-line variant of [PillField]'s well.
///
/// Same fill, same hairline, same text role -- only the corner changes, from
/// a capsule to the card radius, and the leading disc is dropped: a marker
/// pinned to the first line of a three-line box reads as a bullet rather
/// than as part of the field.
class _MultilineWell extends StatelessWidget {
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool autofocus;

  const _MultilineWell({
    required this.controller,
    required this.keyboardType,
    required this.placeholder,
    required this.onChanged,
    required this.maxLines,
    required this.autofocus,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.field,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TakhiSpace.md,
          vertical: TakhiSpace.sm,
        ),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          maxLines: maxLines,
          autofocus: autofocus,
          style: TakhiType.title.copyWith(color: surfaces.onSheet),
          cursorColor: surfaces.onSheet,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TakhiType.title.copyWith(color: surfaces.muted),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
