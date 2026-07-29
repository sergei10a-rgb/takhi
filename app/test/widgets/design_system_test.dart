// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/accent_dot.dart';
import 'package:takhi/widgets/address_row.dart';
import 'package:takhi/widgets/category_tile.dart';
import 'package:takhi/widgets/circle_icon_button.dart';
import 'package:takhi/widgets/info_chip.dart';
import 'package:takhi/widgets/person_row.dart';
import 'package:takhi/widgets/pill_field.dart';
import 'package:takhi/widgets/primary_button.dart';
import 'package:takhi/widgets/section_heading.dart';
import 'package:takhi/widgets/takhi_sheet.dart';

/// The accessibility floor every tappable component is measured against.
/// Deliberately the *guideline* minimum rather than [TakhiTouch.minTarget]:
/// if the token is ever lowered, these tests must still fail.
const _kMinTapTarget = 44.0;

/// Pumps [child] under the real app theme for [brightness].
///
/// Left-aligned in a `Row` rather than centred, so a component that sizes
/// itself horizontally reports its own intrinsic width instead of being
/// stretched to the screen by the test harness -- which is what makes the
/// touch-target assertions below mean anything.
Future<void> _pump(
  WidgetTester t,
  Widget child, {
  Brightness brightness = Brightness.light,
}) => t.pumpWidget(
  MaterialApp(
    theme: takhiTheme(brightness),
    home: Scaffold(
      body: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [child]),
      ),
    ),
  ),
);

/// Runs [body] once per brightness, naming the case after it, and fails if
/// either pass threw while building or painting.
///
/// Every component in the library has to survive both brightnesses, and the
/// dark surfaces are not the light ones inverted -- a widget that reads a
/// token that only exists in one of them renders fine in review and blows up
/// on a driver's phone at night. So "it rendered" is asserted twice, always.
void forBothBrightnesses(
  String description,
  Future<void> Function(WidgetTester t, Brightness brightness) body,
) {
  for (final brightness in Brightness.values) {
    testWidgets('$description (${brightness.name})', (t) async {
      await body(t, brightness);
      expect(t.takeException(), isNull);
    });
  }
}

void main() {
  group('TakhiSheet', () {
    forBothBrightnesses('renders its child and hugs it', (t, brightness) async {
      await _pump(
        t,
        const SizedBox(width: 300, child: TakhiSheet(child: Text('агуулга'))),
        brightness: brightness,
      );
      expect(find.text('агуулга'), findsOneWidget);
    });

    testWidgets('height follows content -- a taller child makes a taller '
        'sheet, with no fixed or fractional height anywhere', (t) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: TakhiSheet(child: SizedBox(height: 40)),
        ),
      );
      final short = t.getSize(find.byType(TakhiSheet)).height;

      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: TakhiSheet(child: SizedBox(height: 200)),
        ),
      );
      final tall = t.getSize(find.byType(TakhiSheet)).height;

      expect(tall - short, moreOrLessEquals(160, epsilon: 1));
    });

    testWidgets('the drag handle can be turned off for a sheet that cannot '
        'actually be dragged', (t) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: TakhiSheet(showHandle: false, child: Text('x')),
        ),
      );
      final withoutHandle = t.getSize(find.byType(TakhiSheet)).height;

      await _pump(
        t,
        const SizedBox(width: 300, child: TakhiSheet(child: Text('x'))),
      );
      expect(
        t.getSize(find.byType(TakhiSheet)).height,
        greaterThan(withoutHandle),
      );
    });

    testWidgets('keeps content clear of the system gesture inset', (t) async {
      const inset = 34.0;
      await t.pumpWidget(
        MaterialApp(
          theme: takhiTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              viewPadding: EdgeInsets.only(bottom: inset),
            ),
            child: const Scaffold(
              body: SizedBox(width: 300, child: TakhiSheet(child: Text('x'))),
            ),
          ),
        ),
      );
      final withInset = t.getSize(find.byType(TakhiSheet)).height;

      await _pump(
        t,
        const SizedBox(width: 300, child: TakhiSheet(child: Text('x'))),
      );
      expect(
        withInset - t.getSize(find.byType(TakhiSheet)).height,
        moreOrLessEquals(inset, epsilon: 1),
      );
    });
  });

  group('PillField', () {
    forBothBrightnesses('renders a value', (t, brightness) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: PillField(icon: Icons.place, text: 'Сүхбаатарын талбай'),
        ),
        brightness: brightness,
      );
      expect(find.text('Сүхбаатарын талбай'), findsOneWidget);
    });

    testWidgets('falls back to the placeholder, in the muted colour, when '
        'there is no value yet', (t) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: PillField(icon: Icons.search, placeholder: 'Хаашаа?'),
        ),
      );
      final style = t.widget<Text>(find.text('Хаашаа?')).style;
      expect(style?.color, TakhiSurfaces.light.muted);
    });

    testWidgets('shows the value in the primary colour, not the muted one, '
        'once there is one', (t) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: PillField(
            icon: Icons.search,
            placeholder: 'Хаашаа?',
            text: 'Гандан',
          ),
        ),
      );
      expect(
        t.widget<Text>(find.text('Гандан')).style?.color,
        TakhiSurfaces.light.onSheet,
      );
    });

    testWidgets('the tappable variant fires onTap and clears the touch '
        'floor', (t) async {
      var taps = 0;
      await _pump(
        t,
        SizedBox(
          width: 300,
          child: PillField(
            icon: Icons.place,
            placeholder: 'Хаашаа?',
            onTap: () => taps++,
          ),
        ),
      );
      expect(
        t.getSize(find.byType(PillField)).height,
        greaterThanOrEqualTo(_kMinTapTarget),
      );
      await t.tap(find.byType(PillField));
      expect(taps, 1);
    });

    testWidgets('a controller turns it into a real text input, and no tap '
        'target wraps the cursor', (t) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var taps = 0;
      await _pump(
        t,
        SizedBox(
          width: 300,
          child: PillField(
            icon: Icons.search,
            controller: controller,
            onTap: () => taps++,
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Гандан');
      expect(controller.text, 'Гандан');
      // `onTap` belongs to the read-only variant; wiring it to an editable
      // field would swallow taps meant to place the cursor.
      await t.tap(find.byType(TextField));
      expect(taps, 0);
    });

    testWidgets('without onTap and without a controller it is inert -- a '
        'static row, not a button', (t) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: PillField(icon: Icons.place, text: 'Гандан'),
        ),
      );
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('AddressRow', () {
    forBothBrightnesses('renders both tiers', (t, brightness) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: AddressRow(
            icon: Icons.my_location,
            label: 'Суух хаяг',
            value: 'Одоогийн байршил',
          ),
        ),
        brightness: brightness,
      );
      expect(find.text('Суух хаяг'), findsOneWidget);
      expect(find.text('Одоогийн байршил'), findsOneWidget);
    });

    testWidgets('the label is muted and the value is not -- the hierarchy is '
        'colour as well as size', (t) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: AddressRow(
            icon: Icons.my_location,
            label: 'Суух хаяг',
            value: 'Одоогийн байршил',
          ),
        ),
      );
      final label = t.widget<Text>(find.text('Суух хаяг'));
      final value = t.widget<Text>(find.text('Одоогийн байршил'));
      expect(label.style?.color, TakhiSurfaces.light.muted);
      expect(value.style?.color, TakhiSurfaces.light.onSheet);
      expect(value.style!.fontSize!, greaterThan(label.style!.fontSize!));
    });

    testWidgets('fires onTap and clears the touch floor', (t) async {
      var taps = 0;
      await _pump(
        t,
        SizedBox(
          width: 300,
          child: AddressRow(
            icon: Icons.place,
            label: 'Буух хаяг',
            value: 'Гандан',
            onTap: () => taps++,
          ),
        ),
      );
      expect(
        t.getSize(find.byType(AddressRow)).height,
        greaterThanOrEqualTo(_kMinTapTarget),
      );
      await t.tap(find.byType(AddressRow));
      expect(taps, 1);
    });

    testWidgets('a static row keeps the same height as a tappable one, so a '
        'mixed list holds one rhythm', (t) async {
      await _pump(
        t,
        const SizedBox(
          width: 300,
          child: AddressRow(
            icon: Icons.place,
            label: 'Буух хаяг',
            value: 'Гандан',
          ),
        ),
      );
      expect(
        t.getSize(find.byType(AddressRow)).height,
        greaterThanOrEqualTo(_kMinTapTarget),
      );
    });
  });

  group('CategoryTile', () {
    forBothBrightnesses('renders its caption', (t, brightness) async {
      await _pump(
        t,
        CategoryTile(icon: Icons.local_taxi, label: 'Такси', onTap: () {}),
        brightness: brightness,
      );
      expect(find.text('Такси'), findsOneWidget);
    });

    testWidgets('fires onTap and clears the touch floor in both axes -- the '
        'painted square is smaller than the target', (t) async {
      var taps = 0;
      await _pump(
        t,
        CategoryTile(
          icon: Icons.local_taxi,
          label: 'Такси',
          onTap: () => taps++,
        ),
      );
      final size = t.getSize(find.byType(CategoryTile));
      expect(size.width, greaterThanOrEqualTo(_kMinTapTarget));
      expect(size.height, greaterThanOrEqualTo(_kMinTapTarget));
      await t.tap(find.byType(CategoryTile));
      expect(taps, 1);
    });

    testWidgets('a null onTap leaves it visible but inert', (t) async {
      await _pump(
        t,
        const CategoryTile(icon: Icons.local_shipping, label: 'Ачаа'),
      );
      expect(find.text('Ачаа'), findsOneWidget);
      await t.tap(find.byType(CategoryTile));
      // Nothing to assert but the absence of a throw: the point is that an
      // unavailable service stays on screen instead of the row reflowing.
      expect(t.takeException(), isNull);
    });

    testWidgets('every accent gives a distinct tile colour, in both '
        'brightnesses', (t) async {
      for (final brightness in Brightness.values) {
        final fills = <Color>{};
        for (final accent in TakhiAccent.values) {
          await _pump(
            t,
            CategoryTile(
              icon: Icons.local_taxi,
              label: accent.name,
              accent: accent,
              onTap: () {},
            ),
            brightness: brightness,
          );
          final container = t.widget<Container>(
            find
                .descendant(
                  of: find.byType(CategoryTile),
                  matching: find.byType(Container),
                )
                .first,
          );
          fills.add((container.decoration! as BoxDecoration).color!);
        }
        expect(
          fills.length,
          TakhiAccent.values.length,
          reason:
              'two accents paint the same ${brightness.name} tile -- the row '
              'stops being scannable by colour',
        );
      }
    });

    testWidgets('the selected state is drawn, not merely tracked', (t) async {
      await _pump(
        t,
        CategoryTile(
          icon: Icons.local_taxi,
          label: 'Такси',
          selected: true,
          onTap: () {},
        ),
      );
      final container = t.widget<Container>(
        find
            .descendant(
              of: find.byType(CategoryTile),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((container.decoration! as BoxDecoration).border, isNotNull);
    });
  });

  group('CircleIconButton', () {
    forBothBrightnesses('renders its glyph', (t, brightness) async {
      await _pump(
        t,
        CircleIconButton(
          icon: Icons.my_location,
          semanticLabel: 'Байршил',
          onPressed: () {},
        ),
        brightness: brightness,
      );
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('fires onPressed', (t) async {
      var taps = 0;
      await _pump(
        t,
        CircleIconButton(
          icon: Icons.call,
          semanticLabel: 'Залгах',
          onPressed: () => taps++,
        ),
      );
      await t.tap(find.byType(CircleIconButton));
      expect(taps, 1);
    });

    testWidgets('a visual smaller than the floor still presents a target at '
        'the floor -- this is the whole reason the widget exists', (t) async {
      await _pump(
        t,
        CircleIconButton(
          icon: Icons.chat_bubble,
          semanticLabel: 'Чат',
          size: 28,
          onPressed: () {},
        ),
      );
      final size = t.getSize(find.byType(CircleIconButton));
      expect(size.width, greaterThanOrEqualTo(_kMinTapTarget));
      expect(size.height, greaterThanOrEqualTo(_kMinTapTarget));
    });

    testWidgets('a visual larger than the floor is not shrunk to it', (
      t,
    ) async {
      await _pump(
        t,
        CircleIconButton(
          icon: Icons.chat_bubble,
          semanticLabel: 'Чат',
          size: 64,
          onPressed: () {},
        ),
      );
      expect(t.getSize(find.byType(CircleIconButton)), const Size(64, 64));
    });

    testWidgets('null onPressed refuses taps but keeps the control in '
        'place', (t) async {
      await _pump(
        t,
        const CircleIconButton(
          icon: Icons.call,
          semanticLabel: 'Залгах',
          onPressed: null,
        ),
      );
      expect(find.byIcon(Icons.call), findsOneWidget);
      await t.tap(find.byType(CircleIconButton));
      expect(t.takeException(), isNull);
    });

    testWidgets('announces its label as a button', (t) async {
      final handle = t.ensureSemantics();
      await _pump(
        t,
        CircleIconButton(
          icon: Icons.call,
          semanticLabel: 'Жолоочид залгах',
          onPressed: () {},
        ),
      );
      expect(
        find.bySemanticsLabel('Жолоочид залгах'),
        findsOneWidget,
        reason: 'an icon-only control with no label is unusable without sight',
      );
      handle.dispose();
    });
  });

  group('InfoChip', () {
    forBothBrightnesses('renders label and optional icon', (t, b) async {
      await _pump(
        t,
        const InfoChip(label: '3кг · Жижиг', icon: Icons.inventory_2),
        brightness: b,
      );
      expect(find.text('3кг · Жижиг'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2), findsOneWidget);
    });

    testWidgets('the tinted variant fills, the outlined variant does not', (
      t,
    ) async {
      await _pump(t, const InfoChip(label: 'Бэлнээр'));
      final tinted =
          t.widget<Container>(find.byType(Container)).decoration!
              as BoxDecoration;
      expect(tinted.color, isNotNull);
      expect(tinted.border, isNull);

      await _pump(t, const InfoChip(label: 'Бэлнээр', tinted: false));
      final outlined =
          t.widget<Container>(find.byType(Container)).decoration!
              as BoxDecoration;
      expect(outlined.color, isNull);
      expect(outlined.border, isNotNull);
    });

    testWidgets('is a label, not a control -- it takes no tap target', (
      t,
    ) async {
      await _pump(t, const InfoChip(label: '12 мин'));
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('PersonRow', () {
    forBothBrightnesses('renders name, rating and subtitle', (t, b) async {
      await _pump(
        t,
        const SizedBox(
          width: 320,
          child: PersonRow(
            name: 'Батбаяр',
            rating: 4.9,
            subtitle: '1234 УБА · Prius 30',
          ),
        ),
        brightness: b,
      );
      expect(find.text('Батбаяр'), findsOneWidget);
      // Always one decimal: a rating that renders as "4.9" on one row and
      // "4.90000001" on the next is a floating-point leak, not a rating.
      expect(find.text('4.9'), findsOneWidget);
      expect(find.text('1234 УБА · Prius 30'), findsOneWidget);
    });

    testWidgets('no rating means no star -- "unrated" and "zero" must not '
        'render the same', (t) async {
      await _pump(
        t,
        const SizedBox(width: 320, child: PersonRow(name: 'Батбаяр')),
      );
      expect(find.byIcon(Icons.star_rounded), findsNothing);

      await _pump(
        t,
        const SizedBox(
          width: 320,
          child: PersonRow(name: 'Батбаяр', rating: 0),
        ),
      );
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.text('0.0'), findsOneWidget);
    });

    testWidgets('falls back to initials, then to the first letter of the '
        'name', (t) async {
      await _pump(
        t,
        const SizedBox(
          width: 320,
          child: PersonRow(name: 'Батбаяр', initials: 'БД'),
        ),
      );
      expect(find.text('БД'), findsOneWidget);

      await _pump(
        t,
        const SizedBox(width: 320, child: PersonRow(name: 'батбаяр')),
      );
      expect(find.text('Б'), findsOneWidget);
    });

    testWidgets('an empty name still produces a mark instead of asserting '
        'in front of a waiting rider', (t) async {
      await _pump(t, const SizedBox(width: 320, child: PersonRow(name: '  ')));
      expect(t.takeException(), isNull);
      expect(find.byType(AccentDot), findsOneWidget);
    });

    testWidgets('fires onTap and clears the touch floor', (t) async {
      var taps = 0;
      await _pump(
        t,
        SizedBox(
          width: 320,
          child: PersonRow(name: 'Батбаяр', onTap: () => taps++),
        ),
      );
      expect(
        t.getSize(find.byType(PersonRow)).height,
        greaterThanOrEqualTo(_kMinTapTarget),
      );
      await t.tap(find.byType(PersonRow));
      expect(taps, 1);
    });

    testWidgets('a trailing control keeps its own gestures', (t) async {
      var rowTaps = 0;
      var callTaps = 0;
      await _pump(
        t,
        SizedBox(
          width: 320,
          child: PersonRow(
            name: 'Батбаяр',
            onTap: () => rowTaps++,
            trailing: CircleIconButton(
              icon: Icons.call,
              semanticLabel: 'Залгах',
              onPressed: () => callTaps++,
            ),
          ),
        ),
      );
      await t.tap(find.byType(CircleIconButton));
      expect(callTaps, 1);
      expect(rowTaps, 0);
    });
  });

  group('SectionHeading', () {
    forBothBrightnesses('renders both tiers', (t, brightness) async {
      await _pump(
        t,
        const SizedBox(
          width: 320,
          child: SectionHeading(
            title: 'Хаашаа явах вэ?',
            subtitle: 'Одоогийн байршлаас',
          ),
        ),
        brightness: brightness,
      );
      expect(find.text('Хаашаа явах вэ?'), findsOneWidget);
      expect(find.text('Одоогийн байршлаас'), findsOneWidget);
    });

    testWidgets('the title outweighs the subtitle in both size and colour', (
      t,
    ) async {
      await _pump(
        t,
        const SizedBox(
          width: 320,
          child: SectionHeading(title: 'Гарчиг', subtitle: 'Туслах'),
        ),
      );
      final title = t.widget<Text>(find.text('Гарчиг')).style!;
      final subtitle = t.widget<Text>(find.text('Туслах')).style!;
      expect(title.fontSize!, greaterThan(subtitle.fontSize!));
      expect(title.fontWeight!.value, greaterThan(subtitle.fontWeight!.value));
      expect(title.color, TakhiSurfaces.light.onSheet);
      expect(subtitle.color, TakhiSurfaces.light.muted);
    });

    testWidgets('compact drops the title one step down the type scale', (
      t,
    ) async {
      await _pump(
        t,
        const SizedBox(width: 320, child: SectionHeading(title: 'Гарчиг')),
      );
      final full = t.widget<Text>(find.text('Гарчиг')).style!.fontSize!;

      await _pump(
        t,
        const SizedBox(
          width: 320,
          child: SectionHeading(title: 'Гарчиг', compact: true),
        ),
      );
      expect(
        t.widget<Text>(find.text('Гарчиг')).style!.fontSize!,
        lessThan(full),
      );
    });
  });

  group('PrimaryButton stays inside the system it was folded into', () {
    forBothBrightnesses('renders and fires', (t, brightness) async {
      var taps = 0;
      await _pump(
        t,
        SizedBox(
          width: 320,
          child: PrimaryButton(label: 'Үргэлжлүүлэх', onPressed: () => taps++),
        ),
        brightness: brightness,
      );
      await t.tap(find.byType(PrimaryButton));
      expect(taps, 1);
    });

    testWidgets('is a capsule, and taller than the touch floor', (t) async {
      await _pump(
        t,
        SizedBox(
          width: 320,
          child: PrimaryButton(label: 'Үргэлжлүүлэх', onPressed: () {}),
        ),
      );
      expect(
        t.getSize(find.byType(PrimaryButton)).height,
        greaterThanOrEqualTo(_kMinTapTarget),
      );
      final shape =
          t
                  .widget<FilledButton>(find.byType(FilledButton))
                  .style!
                  .shape!
                  .resolve({})!
              as RoundedRectangleBorder;
      expect(shape.borderRadius, TakhiRadius.pillAll);
    });

    testWidgets('loading disables the button without changing its API', (
      t,
    ) async {
      var taps = 0;
      await _pump(
        t,
        SizedBox(
          width: 320,
          child: PrimaryButton(
            label: 'Үргэлжлүүлэх',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.byType(PrimaryButton));
      expect(taps, 0);
    });
  });

  group('AccentDot', () {
    forBothBrightnesses('renders an icon or a label', (t, brightness) async {
      await _pump(
        t,
        const AccentDot(icon: Icons.place),
        brightness: brightness,
      );
      expect(find.byIcon(Icons.place), findsOneWidget);

      await _pump(t, const AccentDot(label: 'Б'), brightness: brightness);
      expect(find.text('Б'), findsOneWidget);
    });

    testWidgets('is decoration -- hidden from semantics, since the row that '
        'contains it already says what it is', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t, const AccentDot(label: 'Б'));
      expect(find.bySemanticsLabel('Б'), findsNothing);
      handle.dispose();
    });
  });
}
