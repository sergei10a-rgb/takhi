// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/menu_row.dart';

Widget _harness(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: takhiTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('a tappable row shows a chevron and answers a tap', (t) async {
    var taps = 0;
    await t.pumpWidget(
      _harness(
        MenuRow(
          icon: Icons.badge,
          label: 'Жолоочийн профайл',
          subtitle: 'Нэр, машин, тариф',
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.text('Жолоочийн профайл'), findsOneWidget);
    expect(find.text('Нэр, машин, тариф'), findsOneWidget);
    // The affordance, not decoration: a row that navigates has to say so
    // before it is tapped.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await t.tap(find.byType(MenuRow));
    expect(taps, 1);
  });

  testWidgets('a row with no handler is a statement -- no chevron, and the '
      'tap goes nowhere', (t) async {
    await t.pumpWidget(
      _harness(const MenuRow(icon: Icons.gavel, label: 'Хууль зүйн сануулга')),
    );

    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a supplied trailing widget replaces the chevron rather than '
      'stacking beside it', (t) async {
    await t.pumpWidget(
      _harness(
        MenuRow(
          icon: Icons.ios_share,
          label: 'Дугаараа илгээх',
          onTap: () {},
          trailing: IgnorePointer(
            child: Switch(value: true, onChanged: (_) {}),
          ),
        ),
      ),
    );

    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('the row never presents a target below the touch floor, '
      'however short its content', (t) async {
    await t.pumpWidget(
      _harness(MenuRow(icon: Icons.phone, label: 'A', onTap: () {})),
    );

    final size = t.getSize(find.byType(MenuRow));
    expect(size.height, greaterThanOrEqualTo(TakhiTouch.minTarget));
  });

  test('the neutral accent is refused outright -- its tint is the very '
      'colour the row fills itself with, so the mark would vanish and the '
      'row would be the only one in a list without one', () {
    expect(
      () => MenuRow(
        icon: Icons.gavel,
        label: 'Хууль зүйн сануулга',
        accent: TakhiAccent.neutral,
        onTap: () {},
      ),
      throwsAssertionError,
    );
  });

  testWidgets('an empty subtitle renders no second line rather than a blank '
      'one, so a mixed list keeps one rhythm', (t) async {
    await t.pumpWidget(
      _harness(
        MenuRow(
          icon: Icons.phone,
          label: 'Утасны дугаар',
          subtitle: '',
          onTap: () {},
        ),
      ),
    );

    // One Text in the row: the label. A blank second line would make this
    // row taller than its neighbours for no reason the user can see.
    expect(
      find.descendant(of: find.byType(MenuRow), matching: find.byType(Text)),
      findsOneWidget,
    );
  });
}
