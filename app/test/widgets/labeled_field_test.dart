// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/labeled_field.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: takhiTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('the label stays on screen after the field is filled in', (
    t,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await t.pumpWidget(
      _harness(
        LabeledField(
          label: 'Км-тариф (₮/км)',
          icon: Icons.payments,
          controller: controller,
        ),
      ),
    );

    expect(find.text('Км-тариф (₮/км)'), findsOneWidget);

    await t.enterText(find.byType(TextField), '1500');
    await t.pump();

    // The whole point of a standing label over Material's floating one: a
    // driver looking at `1500` must be able to tell which rate it is
    // without clearing the box to bring the label back.
    expect(find.text('Км-тариф (₮/км)'), findsOneWidget);
    expect(find.text('1500'), findsOneWidget);
  });

  testWidgets('the hint is shown under the field, and only when given', (
    t,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await t.pumpWidget(
      _harness(
        LabeledField(
          label: 'Хүлээлгийн тариф',
          icon: Icons.hourglass_bottom,
          controller: controller,
        ),
      ),
    );
    expect(find.text('Түгжрэлд зогсох минут тутамд.'), findsNothing);

    await t.pumpWidget(
      _harness(
        LabeledField(
          label: 'Хүлээлгийн тариф',
          icon: Icons.hourglass_bottom,
          controller: controller,
          hint: 'Түгжрэлд зогсох минут тутамд.',
        ),
      ),
    );
    expect(find.text('Түгжрэлд зогсох минут тутамд.'), findsOneWidget);
  });

  testWidgets('an error is rendered in the theme error colour, not in the '
      'supporting grey', (t) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await t.pumpWidget(
      _harness(
        LabeledField(
          label: 'Нөөц үг',
          icon: Icons.key,
          controller: controller,
          errorText: 'Нөөц үг буруу байна.',
        ),
      ),
    );

    final error = t.widget<Text>(find.text('Нөөц үг буруу байна.'));
    expect(error.style?.color, takhiTheme(Brightness.light).colorScheme.error);
  });

  testWidgets('maxLines above one gives a multi-line well that still holds '
      'exactly one text field, so a whole phrase can be pasted at once', (
    t,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await t.pumpWidget(
      _harness(
        LabeledField(
          label: '12 нөөц үг',
          icon: Icons.key,
          controller: controller,
          maxLines: 3,
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField)).maxLines, 3);

    await t.enterText(find.byType(TextField), 'abandon abandon about');
    expect(controller.text, 'abandon abandon about');
  });

  testWidgets('onChanged fires on every keystroke, which is what lets a form '
      're-evaluate whether it can be saved', (t) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final seen = <String>[];

    await t.pumpWidget(
      _harness(
        LabeledField(
          label: 'Нэр',
          icon: Icons.person,
          controller: controller,
          onChanged: seen.add,
        ),
      ),
    );

    await t.enterText(find.byType(TextField), 'Бат');
    expect(seen, ['Бат']);
  });
}
