// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/segmented_choice.dart';

enum _Answer { first, second, third }

/// Pumps the control at a stated width, since two of its behaviours -- the
/// glyphs dropping, the labels staying whole -- are decisions it makes from
/// the width it is handed rather than from its arguments.
Future<void> _pump(
  WidgetTester t, {
  _Answer value = _Answer.first,
  double width = 360,
  ValueChanged<_Answer>? onChanged,
}) => t.pumpWidget(
  MaterialApp(
    theme: takhiTheme(Brightness.light),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SegmentedChoice<_Answer>(
            semanticsLabel: 'эрэмбэ',
            value: value,
            onChanged: onChanged ?? (_) {},
            options: const [
              SegmentedOption(
                value: _Answer.first,
                label: 'Нэр хүнд',
                icon: Icons.verified_outlined,
              ),
              SegmentedOption(
                value: _Answer.second,
                label: 'Хямд',
                icon: Icons.payments_outlined,
              ),
              SegmentedOption(
                value: _Answer.third,
                label: 'Хурдан',
                icon: Icons.schedule_outlined,
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('reports the option that was tapped', (t) async {
    _Answer? picked;
    await _pump(t, onChanged: (answer) => picked = answer);

    await t.tap(find.text('Хямд'));
    await t.pumpAndSettle();

    expect(picked, _Answer.second);
  });

  testWidgets('tapping the segment that is already chosen still reports it, '
      'rather than silently doing nothing', (t) async {
    _Answer? picked;
    await _pump(
      t,
      value: _Answer.third,
      onChanged: (answer) => picked = answer,
    );

    await t.tap(find.text('Хурдан'));
    await t.pumpAndSettle();

    expect(picked, _Answer.third);
  });

  // The contract that separates this from `InfoChip`, which is a label and
  // refuses tap handlers precisely so it never has to meet this floor.
  testWidgets('every segment is at least a full touch target tall', (t) async {
    await _pump(t);

    for (final label in ['Нэр хүнд', 'Хямд', 'Хурдан']) {
      final box = t.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(
        box.height,
        greaterThanOrEqualTo(TakhiTouch.minTarget),
        reason: '"$label" is only ${box.height} tall',
      );
    }
  });

  // Colour alone is not a distinction every rider can see, and this control
  // has no other affordance -- no checkmark, no radio.
  testWidgets('the chosen segment is set in a heavier weight than the '
      'others, not merely a different colour', (t) async {
    await _pump(t, value: _Answer.second);

    TextStyle styleOf(String label) => t.widget<Text>(find.text(label)).style!;

    expect(
      styleOf('Хямд').fontWeight!.value,
      greaterThan(styleOf('Нэр хүнд').fontWeight!.value),
    );
  });

  // Whether the words then *fit* is a question only a picture can answer,
  // and deliberately not asked here: a widget test renders in the test
  // renderer's fallback face, where every glyph is a full em square, so
  // `didExceedMaxLines` measures a font the app does not ship. The real
  // answer is `test/golden/images/passenger_offers_list_light.png`, taken
  // with the bundled NotoSans loaded -- see docs/design/SCREENSHOT_RULE.md.
  testWidgets('drops the glyphs rather than the words when three segments '
      'have to share a narrow phone', (t) async {
    await _pump(t, width: 270);

    expect(find.byIcon(Icons.verified_outlined), findsNothing);
    expect(find.byIcon(Icons.payments_outlined), findsNothing);
    expect(find.text('Нэр хүнд'), findsOneWidget);
    expect(find.text('Хямд'), findsOneWidget);
  });

  testWidgets('keeps the glyphs when there is room for them', (t) async {
    await _pump(t, width: 420);

    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
  });
}
