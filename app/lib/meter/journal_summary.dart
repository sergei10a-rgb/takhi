// SPDX-License-Identifier: AGPL-3.0-or-later
import 'meter_journal.dart';

/// How many runs a stretch of time holds and what they came to, in төгрөг.
///
/// Only the two figures the journal actually records can appear here.
/// A driver's *earnings* would need what they spent on fuel, what the car
/// costs them and what they hand over at the end of a shift, and the meter
/// journal knows none of that — so this is takings, and the screen says so
/// rather than implying a profit the app cannot compute.
class JournalPeriodTotals {
  /// Runs whose meter was started inside the period.
  final int trips;

  /// Sum of those runs' [MeterTripEntry.fareMnt] — distance and waiting
  /// together, i.e. what was charged.
  final int fareMnt;

  const JournalPeriodTotals({required this.trips, required this.fareMnt});

  static const empty = JournalPeriodTotals(trips: 0, fareMnt: 0);
}

/// The three stretches the journal screen reports: today, the current week
/// and the current month.
///
/// Nested rather than cumulative — a run today is counted in all three, which
/// is what a driver checking "have I made rent this month" expects. The
/// screen labels them as the three periods they are, never as a sum.
class JournalSummary {
  final JournalPeriodTotals today;
  final JournalPeriodTotals week;
  final JournalPeriodTotals month;

  const JournalSummary({
    required this.today,
    required this.week,
    required this.month,
  });

  static const empty = JournalSummary(
    today: JournalPeriodTotals.empty,
    week: JournalPeriodTotals.empty,
    month: JournalPeriodTotals.empty,
  );
}

/// When [entry]'s meter was started, in the phone's own time zone.
///
/// [MeterTripEntry.startedAt] is whole seconds since the epoch (see
/// `TaximeterPage._finish`), so it is multiplied back up before being read
/// as a moment.
DateTime journalEntryStart(MeterTripEntry entry) =>
    DateTime.fromMillisecondsSinceEpoch(
      entry.startedAt * Duration.millisecondsPerSecond,
    );

/// Local midnight opening the day [now] falls in.
DateTime _startOfDay(DateTime now) => DateTime(now.year, now.month, now.day);

/// Local midnight opening the Monday of [now]'s week.
///
/// Monday, because that is where the Mongolian week starts and a driver
/// counting a week's takings counts from it. Arrived at by handing
/// [DateTime] an out-of-range day number rather than by subtracting a
/// [Duration]: day arithmetic on the constructor normalises across a month
/// boundary *and* keeps the result at local midnight, where subtracting
/// 24-hour Durations would land an hour off on any day the offset moves.
DateTime _startOfWeek(DateTime now) =>
    DateTime(now.year, now.month, now.day - (now.weekday - DateTime.monday));

/// Local midnight opening the first of [now]'s month.
DateTime _startOfMonth(DateTime now) => DateTime(now.year, now.month);

/// [entries] that began at or after [from], counted and added up.
JournalPeriodTotals _totalsSince(
  Iterable<MeterTripEntry> entries,
  DateTime from,
) {
  var trips = 0;
  var fareMnt = 0;
  for (final entry in entries) {
    if (journalEntryStart(entry).isBefore(from)) continue;
    trips++;
    fareMnt += entry.fareMnt;
  }
  return JournalPeriodTotals(trips: trips, fareMnt: fareMnt);
}

/// What [entries] come to over the day, week and month containing [now].
///
/// A run is filed by **when it started**, not when it finished: a fare that
/// begins at 23:50 and ends at 00:10 belongs to the shift the driver thinks
/// of as that evening, and filing it by its end would move it into a day
/// they had already stopped working. It also means the answer never changes
/// for a run once it is recorded.
///
/// [now] is a parameter rather than a `DateTime.now()` inside, because every
/// boundary here is a judgement about the local calendar and a test that
/// cannot choose the day it is asking about can only assert tautologies.
JournalSummary summariseJournal(
  Iterable<MeterTripEntry> entries,
  DateTime now,
) => JournalSummary(
  today: _totalsSince(entries, _startOfDay(now)),
  week: _totalsSince(entries, _startOfWeek(now)),
  month: _totalsSince(entries, _startOfMonth(now)),
);
