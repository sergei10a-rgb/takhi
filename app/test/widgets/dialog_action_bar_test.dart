// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/dialog_action_bar.dart';

/// Real Mongolian dialog labels, not lorem ipsum: the whole reason this
/// widget exists is that Cyrillic action labels run roughly twice as long
/// as their English counterparts ("Тийм, үргэлжлүүл" for "Yes, continue"),
/// and the pair stops fitting side by side on a narrow phone.
const _dismiss = 'Цуцлах';
const _proceed = 'Тийм, үргэлжлүүл';

/// Longer than the whole action row on any phone -- the case where even a
/// single label cannot fit on one line and has to wrap.
const _veryLongProceed = 'Тийм, би нөөц үгсээ найдвартай газарт хадгалсан';

/// A phone narrow enough that the two labels cannot sit side by side.
const _narrow = Size(320, 800);

/// Wide enough that they comfortably can.
const _wide = Size(800, 800);

Future<void> _pumpBar(
  WidgetTester t, {
  required Size screen,
  String dismissLabel = _dismiss,
  String proceedLabel = _proceed,
  DialogActionTone dismissTone = DialogActionTone.neutral,
  DialogActionTone proceedTone = DialogActionTone.primary,
  bool proceedBusy = false,
  VoidCallback? onDismiss,
  VoidCallback? onProceed,
  Brightness brightness = Brightness.light,
}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = screen;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  await t.pumpWidget(
    MaterialApp(
      theme: takhiTheme(brightness),
      home: Scaffold(
        body: AlertDialog(
          title: const Text('Гарчиг'),
          content: const Text('Тайлбар.'),
          actions: [
            DialogActionBar(
              dismiss: DialogAction(
                label: dismissLabel,
                tone: dismissTone,
                onPressed: onDismiss ?? () {},
              ),
              proceed: DialogAction(
                label: proceedLabel,
                tone: proceedTone,
                busy: proceedBusy,
                onPressed: onProceed ?? () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  // `pump`, not `pumpAndSettle`: a busy action spins an indeterminate
  // `CircularProgressIndicator`, which never settles.
  await t.pump();
}

/// The button widget wrapping [label] -- `find.ancestor` returns ancestors
/// closest-first, so `.first` is the button itself rather than the dialog
/// around it.
Finder _button(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    )
    .first;

void main() {
  group('three-tier fitting rule', () {
    testWidgets('wide screen: the pair stays on one row, dismiss on the '
        'left, with a 24px gap', (t) async {
      await _pumpBar(t, screen: _wide);

      final dismiss = t.getRect(_button(_dismiss));
      final proceed = t.getRect(_button(_proceed));

      expect(dismiss.center.dy, moreOrLessEquals(proceed.center.dy));
      expect(
        dismiss.right,
        lessThanOrEqualTo(proceed.left),
        reason: 'the safe answer must sit to the left of the dangerous one',
      );
      expect(proceed.left - dismiss.right, moreOrLessEquals(24));
    });

    testWidgets('narrow screen: the pair stacks, dangerous on top and safe '
        'at the bottom under the thumb, both full width, 8px apart', (t) async {
      await _pumpBar(t, screen: _narrow);

      final dismiss = t.getRect(_button(_dismiss));
      final proceed = t.getRect(_button(_proceed));

      expect(
        proceed.bottom,
        lessThanOrEqualTo(dismiss.top),
        reason:
            'the dialog was opened by a downward back gesture -- the safe '
            'answer belongs at the bottom, where that motion ends',
      );
      expect(dismiss.top - proceed.bottom, moreOrLessEquals(8));
      expect(dismiss.width, moreOrLessEquals(proceed.width));
      expect(dismiss.left, moreOrLessEquals(proceed.left));
      expect(
        dismiss.width,
        moreOrLessEquals(t.getSize(find.byType(DialogActionBar)).width),
      );
    });

    testWidgets('a label too long for even a full-width button wraps and the '
        'button grows with it', (t) async {
      await _pumpBar(t, screen: _narrow, proceedLabel: _veryLongProceed);

      final paragraph = t.renderObject<RenderParagraph>(
        find.text(_veryLongProceed),
      );
      final button = t.getSize(_button(_veryLongProceed));

      expect(
        paragraph.size.width,
        lessThanOrEqualTo(button.width),
        reason: 'the wrapped label must stay inside its button',
      );
      expect(
        paragraph.size.height,
        greaterThan(paragraph.preferredLineHeight * 1.5),
        reason: 'the label should have wrapped onto a second line',
      );
      expect(button.height, greaterThan(48));
      expect(t.takeException(), isNull);
    });

    testWidgets('short labels still get a 48dp minimum tap height', (t) async {
      await _pumpBar(t, screen: _narrow);
      expect(t.getSize(_button(_dismiss)).height, greaterThanOrEqualTo(48));
      expect(t.getSize(_button(_proceed)).height, greaterThanOrEqualTo(48));
    });
  });

  group('labels are never truncated to make them fit', () {
    testWidgets('no ellipsis, no shrink-to-fit, on either layout', (t) async {
      for (final screen in [_narrow, _wide]) {
        await _pumpBar(t, screen: screen, proceedLabel: _veryLongProceed);

        for (final label in [_dismiss, _veryLongProceed]) {
          final text = t.widget<Text>(find.text(label));
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(text.softWrap, isNot(false));
          expect(text.maxLines, isNull);
        }
        expect(
          find.descendant(
            of: find.byType(DialogActionBar),
            matching: find.byType(FittedBox),
          ),
          findsNothing,
          reason: 'shrinking the font to fit is not an accepted answer',
        );
      }
    });
  });

  group('tones paint what the theme says they paint', () {
    testWidgets('primary is a filled brand button, never gold text', (t) async {
      await _pumpBar(t, screen: _wide);
      final style = t.widget<ButtonStyleButton>(_button(_proceed)).style!;
      expect(style.backgroundColor?.resolve({}), TakhiColors.gold);
      expect(style.foregroundColor?.resolve({}), TakhiColors.ink);
    });

    testWidgets('neutral is plain text in the on-surface colour', (t) async {
      await _pumpBar(t, screen: _wide, brightness: Brightness.dark);
      final theme = takhiTheme(Brightness.dark);
      final style = t.widget<ButtonStyleButton>(_button(_dismiss)).style!;
      expect(style.backgroundColor?.resolve({}), isNull);
      expect(style.foregroundColor?.resolve({}), theme.colorScheme.onSurface);
    });

    testWidgets('caution is warning-coloured text, quieter than the safe '
        'answer beside it', (t) async {
      await _pumpBar(
        t,
        screen: _wide,
        dismissTone: DialogActionTone.primary,
        proceedTone: DialogActionTone.caution,
      );
      final theme = takhiTheme(Brightness.light);
      final proceed = t.widget<ButtonStyleButton>(_button(_proceed)).style!;
      final dismiss = t.widget<ButtonStyleButton>(_button(_dismiss)).style!;
      expect(proceed.backgroundColor?.resolve({}), isNull);
      expect(proceed.foregroundColor?.resolve({}), theme.colorScheme.error);
      expect(dismiss.backgroundColor?.resolve({}), TakhiColors.gold);
    });

    testWidgets('destructive is a filled error button', (t) async {
      await _pumpBar(
        t,
        screen: _wide,
        proceedTone: DialogActionTone.destructive,
      );
      final theme = takhiTheme(Brightness.light);
      final style = t.widget<ButtonStyleButton>(_button(_proceed)).style!;
      expect(style.backgroundColor?.resolve({}), theme.colorScheme.error);
      expect(style.foregroundColor?.resolve({}), theme.colorScheme.onError);
    });
  });

  group('behaviour', () {
    testWidgets('each action reports its own taps', (t) async {
      var dismissed = 0;
      var proceeded = 0;
      await _pumpBar(
        t,
        screen: _narrow,
        onDismiss: () => dismissed++,
        onProceed: () => proceeded++,
      );

      await t.tap(_button(_dismiss));
      await t.tap(_button(_proceed));
      await t.pump();

      expect(dismissed, 1);
      expect(proceeded, 1);
    });

    testWidgets('a busy proceed action shows a spinner, refuses taps, and '
        'keeps the row from reflowing', (t) async {
      await _pumpBar(t, screen: _wide);
      final settledWidth = t.getSize(_button(_proceed)).width;

      var proceeded = 0;
      await _pumpBar(
        t,
        screen: _wide,
        proceedBusy: true,
        onProceed: () => proceeded++,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        t.getSize(_button(_proceed)).width,
        moreOrLessEquals(settledWidth),
      );

      await t.tap(_button(_proceed), warnIfMissed: false);
      await t.pump();
      expect(proceeded, 0);
    });

    testWidgets('a null onPressed disables that action without hiding it', (
      t,
    ) async {
      await _pumpBar(t, screen: _wide, onProceed: null);
      await t.pumpWidget(
        MaterialApp(
          theme: takhiTheme(Brightness.light),
          home: const Scaffold(
            body: AlertDialog(
              actions: [
                DialogActionBar(
                  dismiss: DialogAction(
                    label: _dismiss,
                    tone: DialogActionTone.neutral,
                    onPressed: null,
                  ),
                  proceed: DialogAction(
                    label: _proceed,
                    tone: DialogActionTone.primary,
                    onPressed: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text(_proceed), findsOneWidget);
      expect(t.widget<ButtonStyleButton>(_button(_proceed)).enabled, isFalse);
    });
  });
}
