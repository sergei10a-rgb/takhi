// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/dialog_action_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_chip.dart';
import '../widgets/section_heading.dart';
import '../widgets/summary_row.dart';
import 'distance_format.dart';
import 'journal_summary.dart';
import 'meter_journal.dart';
import 'meter_providers.dart';
import 'money_format.dart';

/// The driver's own taximeter journal, read back.
///
/// `MeterJournalStore` has been recording every finished run since the meter
/// shipped -- distance, duration, the waiting half, the total -- and until
/// now nothing in the app could open it. A driver could see what one trip
/// came to, in the seconds before they tapped "Эхлүүл" again, and after that
/// the figure was gone: no way to answer "what did I take this week", which
/// is the question the whole taximeter exists to serve.
///
/// Three things it deliberately is not:
///
/// * **not earnings.** The journal records what was *charged*. Fuel, the
///   car, what a driver hands over at the end of a shift -- the app knows
///   none of it, so this screen says takings and never implies a profit;
/// * **not Nostr.** Nothing here is signed, published or fetched. The meter
///   is the offline half of the app (spec §7.4) and its journal explicitly
///   creates no reputation, so the screen carries no identity, no relay
///   state and no share affordance;
/// * **not a ledger.** Rows can be deleted, and the sums move when they are.
///   It is the driver's own note of their own work, not a record anyone else
///   is entitled to rely on.
class MeterJournalPage extends ConsumerStatefulWidget {
  /// Reads the moment the three periods are measured against.
  ///
  /// A parameter, defaulted to [DateTime.now], because every boundary on
  /// this screen -- midnight, Monday, the first of the month -- is a
  /// question about *which day it is*, and a screen that can only ever ask
  /// the real clock can only be tested on the day the test happens to run.
  /// It is also what keeps the design screenshots reproducible: the pictures
  /// pin a date, so the same code produces the same PNG next month.
  final DateTime Function() now;

  const MeterJournalPage({super.key, this.now = DateTime.now});

  @override
  ConsumerState<MeterJournalPage> createState() => _MeterJournalPageState();
}

class _MeterJournalPageState extends ConsumerState<MeterJournalPage> {
  /// The journal, newest first. `null` until the first read of the store
  /// lands -- distinct from an empty list, which is the state that gets the
  /// [EmptyState]. Flashing "no trips yet" at a driver who has two hundred
  /// of them, for the frame it takes to read `shared_preferences`, would be
  /// the app telling them their day had been lost.
  List<MeterTripEntry>? _entries;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final all = await ref.read(meterJournalStoreProvider).loadAll();
    if (!mounted) return;
    setState(() {
      // A fresh list rather than a sort in place: `loadAll` may hand back an
      // unmodifiable view (`InMemoryMeterJournalStore` does), and the store's
      // own order is append order, which is the opposite of the one a driver
      // reads -- today's runs are the ones they came for.
      _entries = [...all]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    });
  }

  /// Asks, then deletes. The journal is the only copy of these figures, and
  /// the control sits on every row, so an unguarded tap would silently take
  /// a run out of the week's total.
  ///
  /// Emphasis on cancelling, the same way `ConfirmLeaveScope` puts it on
  /// staying: the loud button is the one that changes nothing.
  /// [DialogActionTone.destructive] stays reserved for losing the private
  /// key -- one row of a driver's own statistics is a real loss, but not
  /// that one.
  Future<void> _confirmDelete(MeterTripEntry entry) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.journalDeleteConfirmTitle),
        content: Text(l.journalDeleteConfirmMessage),
        actions: [
          DialogActionBar(
            dismiss: DialogAction(
              label: l.cancelAction,
              tone: DialogActionTone.primary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            proceed: DialogAction(
              label: l.journalDeleteAction,
              tone: DialogActionTone.caution,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(meterJournalStoreProvider).delete(entry.startedAt);
    // Re-read rather than dropping the row locally: the store is the truth,
    // and a list rebuilt from it can never disagree with the totals computed
    // from the same read.
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final entries = _entries;

    return Scaffold(
      backgroundColor: surfaces.canvas,
      // Pushed from the settings menu, so the bar is here to carry the back
      // arrow -- the title is the SectionHeading below, at a size worth
      // reading, exactly as on `SettingsPage`.
      appBar: AppBar(
        backgroundColor: surfaces.canvas,
        foregroundColor: surfaces.onSheet,
        elevation: 0,
      ),
      body: SafeArea(child: _body(entries)),
    );
  }

  Widget _body(List<MeterTripEntry>? entries) {
    if (entries == null) return const SizedBox.shrink();
    if (entries.isEmpty) return const _EmptyJournal();
    return _JournalList(
      entries: entries,
      now: widget.now(),
      onDelete: _confirmDelete,
    );
  }
}

/// Outer padding shared by both shapes of the screen, so the heading does
/// not shift sideways when the first trip is recorded.
const _kPagePadding = EdgeInsets.fromLTRB(
  TakhiSpace.md,
  TakhiSpace.lg,
  TakhiSpace.md,
  TakhiSpace.xl,
);

/// The journal before the driver's first run.
///
/// Heading and nothing else above the mark: the totals block is left out
/// rather than shown as three zeroes, which would read as a bad week rather
/// than as an empty book.
class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Padding(
      padding: _kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: l.settingsJournalMenuLabel,
            subtitle: l.journalSubtitle,
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.receipt_long,
              title: l.journalEmptyTitle,
              message: l.journalEmptyMessage,
            ),
          ),
        ],
      ),
    );
  }
}

/// Totals on top, then every run, newest first.
class _JournalList extends StatelessWidget {
  final List<MeterTripEntry> entries;

  /// The moment the three periods are measured against -- see
  /// [MeterJournalPage.now].
  final DateTime now;

  final ValueChanged<MeterTripEntry> onDelete;

  const _JournalList({
    required this.entries,
    required this.now,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final summary = summariseJournal(entries, now);

    return ListView(
      padding: _kPagePadding,
      children: [
        SectionHeading(
          title: l.settingsJournalMenuLabel,
          subtitle: l.journalSubtitle,
        ),
        const SizedBox(height: TakhiSpace.lg),
        _TotalsCard(summary: summary),
        const SizedBox(height: TakhiSpace.xl),
        SectionHeading(compact: true, title: l.journalTripsHeading),
        const SizedBox(height: TakhiSpace.md),
        for (final entry in entries) ...[
          _TripRow(entry: entry, onDelete: () => onDelete(entry)),
          const SizedBox(height: TakhiSpace.xs),
        ],
      ],
    );
  }
}

/// Today, this week, this month -- takings on the right, run count under it.
class _TotalsCard extends StatelessWidget {
  final JournalSummary summary;

  const _TotalsCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.sheet,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Today is the emphasised row, not the month: it is the figure
            // the screen is opened for, and the only one that is still
            // moving.
            _totalsRow(l, l.journalTodayRow, summary.today, emphasised: true),
            const SizedBox(height: TakhiSpace.sm),
            _totalsRow(l, l.journalWeekRow, summary.week),
            const SizedBox(height: TakhiSpace.sm),
            _totalsRow(l, l.journalMonthRow, summary.month),
          ],
        ),
      ),
    );
  }

  Widget _totalsRow(
    AppLocalizations l,
    String label,
    JournalPeriodTotals totals, {
    bool emphasised = false,
  }) => SummaryRow(
    label: label,
    value: l.meterFareLabel(groupedMnt(totals.fareMnt)),
    detail: l.journalTripCountLabel(totals.trips),
    emphasised: emphasised,
  );
}

/// One recorded run: when it was, what it came to, and what made it up.
class _TripRow extends StatelessWidget {
  final MeterTripEntry entry;
  final VoidCallback onDelete;

  const _TripRow({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final started = journalEntryStart(entry);
    // Both, not either -- the same rule the finished-meter summary applies:
    // a run can wait without being charged for it, and a short stop at a
    // small rate can round to zero төгрөг after genuinely waiting.
    final waited = entry.waitingSeconds > 0 || entry.waitingFareMnt > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.sheet,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    l.journalTripWhenLabel(
                      started.month,
                      started.day,
                      _clockText(started),
                    ),
                    style: TakhiType.title.copyWith(color: surfaces.onSheet),
                  ),
                ),
                const SizedBox(width: TakhiSpace.sm),
                Text(
                  l.meterFareLabel(groupedMnt(entry.fareMnt)),
                  style: TakhiType.numeric.copyWith(color: surfaces.onSheet),
                ),
              ],
            ),
            const SizedBox(height: TakhiSpace.xs),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: TakhiSpace.xs,
                    runSpacing: TakhiSpace.xs,
                    children: [
                      InfoChip(
                        icon: Icons.straighten,
                        label: l.meterRunningDistanceLabel(
                          displayKm(entry.distanceMeters),
                        ),
                      ),
                      InfoChip(
                        icon: Icons.schedule_outlined,
                        label: l.meterRunningDurationLabel(
                          (entry.endedAt - entry.startedAt) ~/
                              Duration.secondsPerMinute,
                        ),
                      ),
                      // One waiting chip, carrying whichever half of the
                      // wait is the answer: the money when there was any --
                      // that is the figure a driver did not watch the
                      // odometer earn -- and the minutes when the wait was
                      // free, where the time is all there is to report.
                      if (waited)
                        InfoChip(
                          accent: TakhiAccent.clay,
                          icon: Icons.hourglass_bottom,
                          label: entry.waitingFareMnt > 0
                              ? l.meterWaitingFareLabel(
                                  groupedMnt(entry.waitingFareMnt),
                                )
                              : l.meterWaitingTimeLabel(
                                  entry.waitingSeconds ~/
                                      Duration.secondsPerMinute,
                                ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: l.journalDeleteAction,
                  icon: Icon(Icons.delete_outline, color: surfaces.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// `14:32`, zero-padded on both halves.
  ///
  /// Built here rather than taken from a locale formatter because the app
  /// bundles no locale data beyond its own two `.arb` files, and a 24-hour
  /// clock is what both of them read: a driver comparing an 08:05 run with a
  /// 14:32 one wants the two to line up under each other, which is also why
  /// the hour is padded.
  String _clockText(DateTime at) {
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
