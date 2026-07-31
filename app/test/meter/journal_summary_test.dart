// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/meter/journal_summary.dart';
import 'package:takhi/meter/meter_journal.dart';

/// A finished run that started at [at] and came to [fareMnt].
///
/// Built from a local [DateTime] rather than from a raw epoch number so the
/// day, week and month a case is talking about are readable in the test --
/// and so the assertions hold in whatever time zone the machine is set to,
/// which is the same zone `journalEntryStart` reads the entry back in.
MeterTripEntry _trip(DateTime at, {int fareMnt = 1000}) => MeterTripEntry(
  startedAt: at.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
  endedAt:
      at.add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/
      Duration.millisecondsPerSecond,
  distanceMeters: 4000,
  fareMnt: fareMnt,
);

void main() {
  // 2026-07-31 is a Friday, so the week it belongs to opens on Monday
  // 2026-07-27 and the month on 2026-07-01. Every boundary case below is
  // measured against this instant.
  final now = DateTime(2026, 7, 31, 21, 30);

  test('an empty journal is three zeroes, not a crash or a null', () {
    final summary = summariseJournal(const [], now);
    expect(summary.today.trips, 0);
    expect(summary.today.fareMnt, 0);
    expect(summary.week.trips, 0);
    expect(summary.month.fareMnt, 0);
  });

  test('the three periods are nested, not carved up: a run today counts in '
      'the week and the month as well', () {
    final summary = summariseJournal([
      _trip(DateTime(2026, 7, 31, 9, 12), fareMnt: 12400),
    ], now);
    expect(summary.today.trips, 1);
    expect(summary.week.trips, 1);
    expect(summary.month.trips, 1);
    expect(summary.today.fareMnt, 12400);
    expect(summary.month.fareMnt, 12400);
  });

  test('each period counts only the runs inside it', () {
    final summary = summariseJournal([
      _trip(DateTime(2026, 7, 31, 9, 12), fareMnt: 12400), // today
      _trip(DateTime(2026, 7, 31, 14, 5), fareMnt: 7600), // today
      _trip(DateTime(2026, 7, 28, 18, 40), fareMnt: 9000), // this week
      _trip(DateTime(2026, 7, 14, 7, 55), fareMnt: 5000), // this month
      _trip(DateTime(2026, 6, 30, 22, 0), fareMnt: 4000), // last month
    ], now);

    expect(summary.today.trips, 2);
    expect(summary.today.fareMnt, 20000);
    expect(summary.week.trips, 3);
    expect(summary.week.fareMnt, 29000);
    expect(summary.month.trips, 4);
    expect(summary.month.fareMnt, 34000);
  });

  test('midnight opens the day: a run one minute before it is yesterday, '
      'one minute after it is today', () {
    final summary = summariseJournal([
      _trip(DateTime(2026, 7, 30, 23, 59), fareMnt: 3000),
      _trip(DateTime(2026, 7, 31, 0, 1), fareMnt: 5000),
    ], now);
    expect(summary.today.trips, 1);
    expect(summary.today.fareMnt, 5000);
    // Both are still inside the same week and month.
    expect(summary.week.trips, 2);
    expect(summary.month.trips, 2);
  });

  test('the week opens on Monday, so Sunday belongs to the week before', () {
    final summary = summariseJournal([
      // Sunday 2026-07-26, the day before this week's Monday.
      _trip(DateTime(2026, 7, 26, 20, 0), fareMnt: 6000),
      // Monday 2026-07-27, the first day of it.
      _trip(DateTime(2026, 7, 27, 6, 0), fareMnt: 7000),
    ], now);
    expect(summary.week.trips, 1);
    expect(summary.week.fareMnt, 7000);
    expect(summary.month.trips, 2);
  });

  test('a Monday is its own week: nothing earlier is counted, and the day '
      'that started nine minutes ago still is', () {
    final monday = DateTime(2026, 7, 27, 0, 9);
    final summary = summariseJournal([
      _trip(DateTime(2026, 7, 26, 23, 50), fareMnt: 6000),
      _trip(DateTime(2026, 7, 27, 0, 5), fareMnt: 7000),
    ], monday);
    expect(summary.today.trips, 1);
    expect(summary.week.trips, 1);
    expect(summary.week.fareMnt, 7000);
  });

  test('a week that straddles a month start still opens on its Monday -- the '
      'month is a separate question, not a clamp on it', () {
    // Saturday 2026-08-01. The week opened on Monday 2026-07-27, i.e. in
    // the previous month.
    final firstOfMonth = DateTime(2026, 8, 1, 12, 0);
    final summary = summariseJournal([
      _trip(DateTime(2026, 7, 29, 10, 0), fareMnt: 8000),
      _trip(DateTime(2026, 8, 1, 10, 0), fareMnt: 2000),
    ], firstOfMonth);

    expect(summary.week.trips, 2);
    expect(summary.week.fareMnt, 10000);
    // The July run is not in August, so the month reads lower than the week.
    // Correct, not a bug: a calendar week is not contained in a month.
    expect(summary.month.trips, 1);
    expect(summary.month.fareMnt, 2000);
  });

  test('a run is filed by when it started, not when it finished', () {
    // Starts at 23:50 on the 30th, runs past midnight into the 31st.
    const twentyMinutes = Duration(minutes: 20);
    final start = DateTime(2026, 7, 30, 23, 50);
    final overnight = MeterTripEntry(
      startedAt: start.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
      endedAt:
          start.add(twentyMinutes).millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond,
      distanceMeters: 9000,
      fareMnt: 15000,
    );

    final summary = summariseJournal([overnight], now);
    expect(
      summary.today.trips,
      0,
      reason:
          'the fare belongs to the evening the driver worked, not to the '
          'day it happened to end in',
    );
    expect(summary.week.trips, 1);
  });

  test('journalEntryStart reads the stored second back as a local moment', () {
    final at = DateTime(2026, 7, 31, 9, 12);
    expect(journalEntryStart(_trip(at)), at);
  });
}
