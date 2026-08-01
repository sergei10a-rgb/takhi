// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/meter/journal_page.dart';
import 'package:takhi/meter/meter_journal.dart';
import 'package:takhi/meter/meter_providers.dart';
import 'package:takhi/widgets/empty_state.dart';
import 'package:takhi/widgets/summary_row.dart';

/// 2026-07-31 is a Friday: the week it belongs to opens on Monday
/// 2026-07-27 and the month on 2026-07-01. Every case measures against this
/// instant, so the screen's three period rows are decidable instead of
/// depending on the day the suite happens to run.
final _now = DateTime(2026, 7, 31, 21, 30);

int _epochSeconds(DateTime at) =>
    at.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

MeterTripEntry _trip(
  DateTime at, {
  int fareMnt = 12400,
  int minutes = 14,
  int distanceMeters = 8300,
  int waitingFareMnt = 0,
  int waitingSeconds = 0,
  int durationFareMnt = 0,
}) => MeterTripEntry(
  startedAt: _epochSeconds(at),
  endedAt: _epochSeconds(at.add(Duration(minutes: minutes))),
  distanceMeters: distanceMeters,
  fareMnt: fareMnt,
  waitingFareMnt: waitingFareMnt,
  waitingSeconds: waitingSeconds,
  durationFareMnt: durationFareMnt,
);

Future<InMemoryMeterJournalStore> _storeWith(
  List<MeterTripEntry> entries,
) async {
  final store = InMemoryMeterJournalStore();
  for (final entry in entries) {
    await store.append(entry);
  }
  return store;
}

/// An amount as the app actually writes it: `_mnt('20 000')` is what
/// `meterFareLabel(groupedMnt(20000))` produces.
///
/// Both spaces in `20 000 ₮` are non-breaking -- `groupedMnt` groups
/// thousands with one and the label sets another before the ₮ -- so that a
/// line break can never fall inside a number. Spelled by code point rather
/// than pasted in, because an invisible U+00A0 sitting in a string literal
/// is a character nobody reviewing this file can see.
final _nbsp = String.fromCharCode(0xA0);

String _mnt(String grouped) => '${grouped.replaceAll(' ', _nbsp)}$_nbsp₮';

Future<void> _pump(WidgetTester t, MeterJournalStore store) async {
  // A tall surface, because a `ListView` builds only what is on screen: at
  // the binding's 800x600 default the third trip row is never constructed,
  // and a finder cannot see an order that was never built.
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);

  await t.pumpWidget(
    ProviderScope(
      overrides: [meterJournalStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: MeterJournalPage(now: () => _now),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a driver who has never run the meter is told what will put '
      'rows here, not shown an empty rectangle', (t) async {
    await _pump(t, await _storeWith([]));

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Аялал хараахан алга'), findsOneWidget);
    // No totals block: three zero rows would read as a bad week rather than
    // as a book nobody has written in yet.
    expect(find.byType(SummaryRow), findsNothing);
  });

  testWidgets('every recorded run is on screen, newest first', (t) async {
    await _pump(
      t,
      await _storeWith([
        _trip(DateTime(2026, 7, 14, 7, 55)),
        _trip(DateTime(2026, 7, 31, 9, 12)),
        _trip(DateTime(2026, 7, 28, 18, 40)),
      ]),
    );

    expect(find.byType(EmptyState), findsNothing);
    final dates = t
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .where((line) => line.contains('сарын'))
        .toList();
    expect(dates, [
      '7-р сарын 31, 09:12',
      '7-р сарын 28, 18:40',
      '7-р сарын 14, 07:55',
    ]);
  });

  testWidgets('the day, the week and the month are each counted and added '
      'up', (t) async {
    await _pump(
      t,
      await _storeWith([
        _trip(DateTime(2026, 7, 31, 9, 12), fareMnt: 12400),
        _trip(DateTime(2026, 7, 31, 14, 5), fareMnt: 7600),
        _trip(DateTime(2026, 7, 28, 18, 40), fareMnt: 9000),
        _trip(DateTime(2026, 7, 14, 7, 55), fareMnt: 5000),
        // June: outside all three periods.
        _trip(DateTime(2026, 6, 30, 22, 0), fareMnt: 4000),
      ]),
    );

    final rows = t.widgetList<SummaryRow>(find.byType(SummaryRow)).toList();
    expect(rows.length, 3);
    expect(rows[0].label, 'Өнөөдөр');
    expect(rows[0].value, _mnt('20 000'));
    expect(rows[0].detail, 'Аялал: 2');
    expect(rows[1].label, 'Энэ 7 хоног');
    expect(rows[1].value, _mnt('29 000'));
    expect(rows[1].detail, 'Аялал: 3');
    expect(rows[2].label, 'Энэ сар');
    expect(rows[2].value, _mnt('34 000'));
    expect(rows[2].detail, 'Аялал: 4');
  });

  testWidgets('a row states its distance, its duration and its total', (
    t,
  ) async {
    await _pump(
      t,
      await _storeWith([
        _trip(
          DateTime(2026, 7, 31, 9, 12),
          fareMnt: 12400,
          minutes: 14,
          distanceMeters: 8317,
        ),
      ]),
    );

    expect(find.text('8.3 км'), findsOneWidget);
    expect(find.text('14 мин'), findsOneWidget);
    // Once in the row, and once in each of the three period totals -- which
    // all hold this single trip.
    expect(find.text(_mnt('12 400')), findsNWidgets(4));
  });

  testWidgets('a run that waited says so, in төгрөг when it was charged for '
      'and in minutes when the driver waited for free', (t) async {
    await _pump(
      t,
      await _storeWith([
        _trip(
          DateTime(2026, 7, 31, 14, 5),
          fareMnt: 9600,
          waitingFareMnt: 900,
          waitingSeconds: 180,
        ),
        _trip(
          DateTime(2026, 7, 31, 9, 12),
          fareMnt: 12400,
          waitingSeconds: 240,
        ),
      ]),
    );

    expect(find.text('Зогсолт ${_mnt('900')}'), findsOneWidget);
    expect(find.text('4 мин зогссон'), findsOneWidget);
  });

  testWidgets('a run that never stopped carries no waiting chip at all', (
    t,
  ) async {
    await _pump(t, await _storeWith([_trip(DateTime(2026, 7, 31, 9, 12))]));

    expect(find.textContaining('Зогсолт'), findsNothing);
    expect(find.textContaining('зогссон'), findsNothing);
  });

  testWidgets('a run charged for its whole duration says so on its own chip, '
      'beside the stopped-time one and in the same colour: both are money '
      'earned by the clock rather than by the odometer', (t) async {
    await _pump(
      t,
      await _storeWith([
        _trip(
          DateTime(2026, 7, 31, 14, 5),
          fareMnt: 9600,
          waitingFareMnt: 900,
          waitingSeconds: 180,
          durationFareMnt: 1400,
        ),
      ]),
    );

    // Both, on one row, unremarked -- the stopped three minutes are inside
    // the trip's duration too, and charging them twice is the driver's own
    // commercial decision (see fare_calc.dart).
    expect(find.text('Зогсолт ${_mnt('900')}'), findsOneWidget);
    expect(find.text('Хугацаа ${_mnt('1 400')}'), findsOneWidget);
  });

  testWidgets('a run whose driver does not charge for trip duration carries '
      'no duration chip -- every run has a duration, so a chip keyed on '
      'elapsed time would appear on every row in the book', (t) async {
    await _pump(
      t,
      await _storeWith([
        _trip(DateTime(2026, 7, 31, 9, 12), minutes: 14, fareMnt: 12400),
      ]),
    );

    expect(find.textContaining('Хугацаа'), findsNothing);
    // The elapsed time itself still shows: that is a fact about the run, not
    // a charge.
    expect(find.text('14 мин'), findsOneWidget);
  });

  testWidgets('deleting asks first, and cancelling leaves the run and the '
      'totals exactly as they were', (t) async {
    final store = await _storeWith([
      _trip(DateTime(2026, 7, 31, 9, 12), fareMnt: 12400),
    ]);
    await _pump(t, store);

    await t.tap(find.byIcon(Icons.delete_outline));
    await t.pumpAndSettle();
    expect(find.text('Энэ аяллыг устгах уу?'), findsOneWidget);

    await t.tap(find.text('Цуцлах'));
    await t.pumpAndSettle();

    expect(await store.loadAll(), hasLength(1));
    expect(find.text('7-р сарын 31, 09:12'), findsOneWidget);
  });

  testWidgets('confirming the delete takes the run out of the store, off the '
      'list and out of the totals', (t) async {
    final store = await _storeWith([
      _trip(DateTime(2026, 7, 31, 9, 12), fareMnt: 12400),
      _trip(DateTime(2026, 7, 28, 18, 40), fareMnt: 9000),
    ]);
    await _pump(t, store);

    // The first row is the newest, i.e. today's 12 400₮ run.
    await t.tap(find.byIcon(Icons.delete_outline).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Устгах'));
    await t.pumpAndSettle();

    final remaining = await store.loadAll();
    expect(remaining, hasLength(1));
    expect(remaining.single.fareMnt, 9000);

    expect(find.text('7-р сарын 31, 09:12'), findsNothing);
    expect(find.text('7-р сарын 28, 18:40'), findsOneWidget);

    final rows = t.widgetList<SummaryRow>(find.byType(SummaryRow)).toList();
    expect(rows[0].detail, 'Аялал: 0');
    expect(rows[0].value, _mnt('0'));
    expect(rows[1].detail, 'Аялал: 1');
    expect(rows[1].value, _mnt('9 000'));
  });

  testWidgets('deleting the last run leaves the empty state, not a blank '
      'page', (t) async {
    final store = await _storeWith([
      _trip(DateTime(2026, 7, 31, 9, 12), fareMnt: 12400),
    ]);
    await _pump(t, store);

    await t.tap(find.byIcon(Icons.delete_outline));
    await t.pumpAndSettle();
    await t.tap(find.text('Устгах'));
    await t.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(await store.loadAll(), isEmpty);
  });
}
