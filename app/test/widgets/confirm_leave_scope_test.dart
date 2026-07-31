// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/widgets/confirm_leave_scope.dart';

const _title = 'Аялалаас гарах уу?';
const _message = 'Идэвхтэй аялал тасарна.';

/// Pushes a [ConfirmLeaveScope]-wrapped page on top of a plain first
/// route, so the pushed page gets the `AppBar`'s automatic back button --
/// the same `Navigator.maybePop` path Android's hardware back takes, and
/// the one `PopScope` intercepts.
Future<void> _pumpGuardedPage(
  WidgetTester t, {
  required bool enabled,
  VoidCallback? onConfirmedLeave,
}) async {
  await t.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('mn'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConfirmLeaveScope(
                    enabled: enabled,
                    title: _title,
                    message: _message,
                    onConfirmedLeave: onConfirmedLeave,
                    child: Scaffold(
                      appBar: AppBar(title: const Text('guarded')),
                      body: const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  expect(find.text('guarded'), findsOneWidget);
}

/// Delivers the platform's `popRoute` message -- what Android's hardware
/// back button and iOS' back gesture actually send.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
}

void main() {
  testWidgets('enabled: false lets the pop through untouched -- no dialog, '
      'the page is gone, and onConfirmedLeave is never called', (t) async {
    var left = false;
    await _pumpGuardedPage(
      t,
      enabled: false,
      onConfirmedLeave: () => left = true,
    );

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_title), findsNothing);
    expect(find.text('guarded'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(left, isFalse);
  });

  testWidgets('enabled: true intercepts the pop and shows the confirm '
      'dialog instead of leaving', (t) async {
    await _pumpGuardedPage(t, enabled: true);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(find.text(_title), findsOneWidget);
    expect(find.text(_message), findsOneWidget);
    expect(find.text('Үлдэх'), findsOneWidget);
    expect(find.text('Гарах'), findsOneWidget);
    expect(find.text('guarded'), findsOneWidget); // still here
  });

  testWidgets('choosing "Үлдэх" dismisses the dialog and keeps the page, '
      'without calling onConfirmedLeave', (t) async {
    var left = false;
    await _pumpGuardedPage(
      t,
      enabled: true,
      onConfirmedLeave: () => left = true,
    );

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('Үлдэх'));
    await t.pumpAndSettle();

    expect(find.text(_title), findsNothing);
    expect(find.text('guarded'), findsOneWidget);
    expect(left, isFalse);
  });

  testWidgets('choosing "Гарах" calls onConfirmedLeave and then pops the '
      'page', (t) async {
    var left = false;
    await _pumpGuardedPage(
      t,
      enabled: true,
      onConfirmedLeave: () => left = true,
    );

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('Гарах'));
    await t.pumpAndSettle();

    expect(left, isTrue);
    expect(find.text('guarded'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the platform back gesture is intercepted too, not just the '
      "AppBar's arrow", (t) async {
    await _pumpGuardedPage(t, enabled: true);

    await _systemBack(t);
    await t.pumpAndSettle();

    expect(find.text(_title), findsOneWidget);
    expect(find.text('guarded'), findsOneWidget);
  });

  testWidgets('a disabled scope stays inert even when a nested PopScope '
      'refuses the pop -- the navigator notifies every entry, including '
      'the ones that were happy to let it through', (t) async {
    var innerHandled = false;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConfirmLeaveScope(
                      enabled: false,
                      title: _title,
                      message: _message,
                      // `PassengerRidePage._guardBack`'s exact shape: an
                      // always-present outer guard over an inner "one step
                      // back" `PopScope`, so neither comes and goes (and
                      // remounts the subtree) as the page's step changes.
                      child: PopScope(
                        canPop: false,
                        onPopInvokedWithResult: (didPop, result) {
                          if (didPop) return;
                          innerHandled = true;
                        },
                        child: Scaffold(
                          appBar: AppBar(title: const Text('guarded')),
                          body: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    expect(innerHandled, isTrue);
    expect(find.text(_title), findsNothing); // no dialog from the inert guard
    expect(find.text('guarded'), findsOneWidget);
  });
}
