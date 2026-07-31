// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// One answer inside a [SegmentedChoice].
class SegmentedOption<T> {
  /// The value this segment selects.
  final T value;

  /// What it is called. User-visible: pass a localised string, and keep it
  /// to one or two words -- three of these share the width of a phone.
  final String label;

  /// Optional glyph before the label. Dropped automatically when the
  /// segment is too narrow to carry both (see [SegmentedChoice]).
  final IconData? icon;

  const SegmentedOption({required this.value, required this.label, this.icon});
}

/// Glyph size inside a segment. Matched to [TakhiType.label]'s cap height so
/// the icon and the word sit on one optical line -- the same relationship
/// `InfoChip` uses, because these two components are read side by side.
const _kGlyphSize = 13.0;

/// Below this much width per segment the glyphs are dropped and the labels
/// stand alone.
///
/// A measured threshold rather than a spacing token: it is the width at which
/// «Хамгийн итгэмжтэй»-length Mongolian labels start eliding on a 360dp
/// handset once an icon has taken its share of the segment. The words are the
/// part that carries meaning, so the glyph is what gives way.
const _kIconlessSegmentWidth = 96.0;

/// A row of mutually exclusive answers, as one connected control.
///
/// The distinction from [InfoChip] is deliberate and load-bearing: a chip is
/// a *label* and takes no tap handler, while this is a *control* and honours
/// [TakhiTouch.minTarget]. Conflating them is how 28dp-tall buttons ship.
///
/// Shaped as a single sunken track with the chosen segment raised out of it,
/// rather than as three separate outlined pills. Three pills read as three
/// independent toggles -- any number of which might be on -- whereas the job
/// here is to say "exactly one of these, and it is this one".
class SegmentedChoice<T> extends StatelessWidget {
  final List<SegmentedOption<T>> options;

  /// The currently selected value. A value not present in [options] simply
  /// leaves every segment unselected rather than asserting.
  final T value;

  final ValueChanged<T> onChanged;

  /// What the whole control is for, read out before the options themselves.
  /// User-visible: pass a localised string.
  final String semanticsLabel;

  const SegmentedChoice({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);

    return Semantics(
      label: semanticsLabel,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaces.field,
          borderRadius: TakhiRadius.pillAll,
          border: Border.all(color: surfaces.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TakhiSpace.xxs),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showIcons =
                  constraints.maxWidth / options.length >=
                  _kIconlessSegmentWidth;
              return Row(
                children: [
                  for (final option in options)
                    Expanded(
                      child: _Segment(
                        option: option,
                        selected: option.value == value,
                        showIcon: showIcons,
                        onTap: () => onChanged(option.value),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  final SegmentedOption<T> option;
  final bool selected;
  final bool showIcon;
  final VoidCallback onTap;

  const _Segment({
    required this.option,
    required this.selected,
    required this.showIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final colors = takhiAccentColors(
      TakhiAccent.gold,
      Theme.of(context).brightness,
    );
    final foreground = selected ? colors.onTint : surfaces.muted;
    final icon = option.icon;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.tint : Colors.transparent,
        borderRadius: TakhiRadius.pillAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: TakhiRadius.pillAll,
          child: ConstrainedBox(
            // The *segment* carries the floor, not the track around it: what
            // a thumb has to hit is one answer, and a control that meets 48
            // only when its own padding is counted has three 40dp targets in
            // it. See [TakhiTouch.minTarget].
            constraints: const BoxConstraints(
              minHeight: TakhiTouch.minTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TakhiSpace.xs,
                vertical: TakhiSpace.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null && showIcon) ...[
                    Icon(icon, size: _kGlyphSize, color: foreground),
                    const SizedBox(width: TakhiSpace.xxs),
                  ],
                  Flexible(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TakhiType.label.copyWith(
                        color: foreground,
                        // The chosen one is heavier as well as filled:
                        // colour alone is not a distinction everybody can
                        // see, and this control has no other affordance.
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
