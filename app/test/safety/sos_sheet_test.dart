// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/safety/emergency_contact_store.dart';
import 'package:takhi/safety/safety_providers.dart';
import 'package:takhi/safety/sos_button.dart';
import 'package:takhi/theme/takhi_theme.dart';
import 'package:takhi/widgets/menu_row.dart';

/// A Mongolian mobile number in shape and nobody's in fact -- the sheet
/// never prints it, it only decides which of the two shapes is shown.
const _kContactPhone = '99112233';

/// Copy the sheet is asserted against, read here rather than looked up so a
/// silent rewording of `app_mn.arb` shows up as a failing test rather than
/// as a screen that quietly stopped saying what it used to.
const _kPolice = '102 — цагдаа';
const _kAmbulance = '103 — түргэн тусламж';
const _kSms = 'Яаралтай холбоо барих хүнд SMS';
const _kAddContact = 'Дугаар нэмэх';
const _kDismiss = 'Болих';

/// Opens the sheet from a button, the way both real call sites do.
Widget _harness({String? contactPhone, List<GoRoute> extraRoutes = const []}) {
  final contacts = InMemoryEmergencyContactStore();
  if (contactPhone != null) contacts.savePhone(contactPhone);
  return ProviderScope(
    overrides: [emergencyContactStoreProvider.overrideWithValue(contacts)],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('mn'),
      routerConfig: GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => Scaffold(
              body: Center(
                child: Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () => showSosActions(context, ref),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
          ...extraRoutes,
        ],
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the sheet names itself and says who actually presses send -- '
      'Тахь hands a tel:/sms: URI to the OS and never dials', (t) async {
    await t.pumpWidget(_harness(contactPhone: _kContactPhone));
    await _openSheet(t);

    expect(find.text('Яаралтай тусламж'), findsOneWidget);
    expect(
      find.textContaining('илгээх товчийг та өөрөө дарна'),
      findsOneWidget,
    );
  });

  testWidgets('with a contact saved it offers three actions, each saying '
      'what a tap opens', (t) async {
    await t.pumpWidget(_harness(contactPhone: _kContactPhone));
    await _openSheet(t);

    expect(find.text(_kPolice), findsOneWidget);
    expect(find.text(_kAmbulance), findsOneWidget);
    expect(find.text(_kSms), findsOneWidget);
    expect(find.text(_kAddContact), findsNothing);

    // Every row explains itself: somebody tapping "102" mid-emergency and
    // then finding a dialler rather than a ringing line has lost the second
    // this screen exists to save.
    for (final row in t.widgetList<MenuRow>(find.byType(MenuRow))) {
      expect(row.subtitle, isNotNull, reason: '"${row.label}" has no hint');
      expect(row.subtitle, isNotEmpty);
    }
  });

  testWidgets('there is a way out -- a sheet of irreversible-looking rows '
      'with no dismiss invites a panicked back-swipe', (t) async {
    await t.pumpWidget(_harness(contactPhone: _kContactPhone));
    await _openSheet(t);

    expect(find.text(_kDismiss), findsOneWidget);

    await t.tap(find.text(_kDismiss));
    await t.pumpAndSettle();

    expect(find.text(_kPolice), findsNothing);
    // Dismissing costs nothing: the page underneath is exactly as it was.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('with no contact saved the SMS row is replaced by a route into '
      'settings, and the two emergency numbers stay put', (t) async {
    final pushed = <String>[];
    await t.pumpWidget(
      _harness(
        extraRoutes: [
          GoRoute(
            path: '/settings/emergency-contact',
            builder: (context, state) {
              pushed.add('/settings/emergency-contact');
              return const Scaffold(body: Text('contact-stub'));
            },
          ),
        ],
      ),
    );
    await _openSheet(t);

    expect(find.text(_kPolice), findsOneWidget);
    expect(find.text(_kAmbulance), findsOneWidget);
    expect(find.text(_kSms), findsNothing);
    expect(find.text(_kAddContact), findsOneWidget);

    await t.tap(find.text(_kAddContact));
    await t.pumpAndSettle();

    expect(pushed, ['/settings/emergency-contact']);
  });

  testWidgets('the settings detour is not coloured like a third way to call '
      'for help', (t) async {
    await t.pumpWidget(_harness());
    await _openSheet(t);

    final rows = t.widgetList<MenuRow>(find.byType(MenuRow)).toList();
    final emergencyRows = rows.where((r) => r.label != _kAddContact);
    expect(emergencyRows, hasLength(2));
    for (final row in emergencyRows) {
      expect(row.accent, TakhiAccent.clay);
    }
    final detour = rows.firstWhere((r) => r.label == _kAddContact);
    expect(detour.accent, TakhiAccent.sky);
    // Never neutral: that family's tint is the same value the row paints
    // itself with, so the disc would disappear and this row alone would
    // show a bare glyph.
    expect(detour.accent, isNot(TakhiAccent.neutral));
  });
}
