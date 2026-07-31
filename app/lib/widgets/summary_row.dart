// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// One line of an itemised money column: what it is on the left, what it
/// came to on the right, and -- where the figure is arithmetic rather than a
/// bare fact -- the sum it was arrived at by, underneath.
///
/// It exists because a fare a passenger cannot take apart is a fare they can
/// only accept or argue with. Every place in the app that states a total
/// states the rows it is made of in this exact shape: the finished
/// taximeter's summary, and -- next -- the driver's own trip journal, which
/// adds up the same numbers over a day or a week. Having it as one component
/// is what keeps the column aligned across those screens rather than
/// re-typed slightly differently on each.
///
/// The value is always set in [TakhiType.numeric], which is the tabular
/// face: a column of amounts whose digits do not line up is a column nobody
/// can add up by eye.
class SummaryRow extends StatelessWidget {
  /// What this row is. User-visible: pass a localised string.
  final String label;

  /// The amount, already formatted (`groupedMnt` plus the localised label
  /// that carries the ₮ sign). User-visible: pass a localised string.
  final String value;

  /// The arithmetic behind [value] -- "7.2 км × 2000 ₮/км". `null` on a row
  /// whose figure is not derived from anything the reader can check.
  final String? detail;

  /// Sets the row in the heavier faces: the total, which is the number the
  /// reader is actually being asked for.
  final bool emphasised;

  const SummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final explanation = detail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: (emphasised ? TakhiType.title : TakhiType.body).copyWith(
                  color: emphasised ? surfaces.onSheet : surfaces.muted,
                ),
              ),
            ),
            const SizedBox(width: TakhiSpace.sm),
            Text(
              value,
              style: TakhiType.numeric.copyWith(color: surfaces.onSheet),
            ),
          ],
        ),
        if (explanation != null) ...[
          const SizedBox(height: TakhiSpace.xxs),
          Text(
            explanation,
            style: TakhiType.support.copyWith(color: surfaces.muted),
          ),
        ],
      ],
    );
  }
}
