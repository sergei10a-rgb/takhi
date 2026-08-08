// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One completed taximeter run, kept purely as the driver's own local
/// statistics (spec §7.4 step 7: "локал журналд бичигдэнэ ... нэр хүнд
/// ҮҮСГЭХГҮЙ"). Never signed, never published, never leaves the device,
/// and — critically — never fed into `computeReputation`: no counterpart
/// ever signs a reciprocal receipt for it, so per spec §9/§4.3 it can
/// never be anything but weightless even if it were mistakenly published.
class MeterTripEntry {
  final int startedAt;
  final int endedAt;

  /// How long the trip actually lasted, measured from the GPS track: the last
  /// fix's second minus the first's, the whole span whether moving, waiting or
  /// stopped.
  ///
  /// Stored rather than shown as [endedAt] − [startedAt] because those are
  /// wall-clock stamps read off `DateTime.now`, and the elapsed figure the
  /// receipt prints must be the *measured* one — the same track the distance
  /// and the duration charge come off, so a passenger who checks the clock
  /// against the charge below it finds they agree. Zero on an entry written
  /// before this was recorded, and on a run too short to span two fixes; the
  /// finished screen falls back to the wall clock for those.
  final int durationSeconds;

  final int distanceMeters;

  /// What the run came to in total — distance plus stopped time plus trip
  /// duration.
  final int fareMnt;

  /// The waiting share of [fareMnt], and the time it was charged for.
  ///
  /// Since v0.4.0 this covers only the minutes a driver put the meter into
  /// its waiting phase for — the passenger keeping them. Traffic is not in
  /// here; it is inside [durationFareMnt], because a jam is part of the
  /// trip. Entries written before v0.4.0 have the old meaning, and there is
  /// no way to tell them apart, which is a reason to read old history as
  /// approximate rather than to rewrite it.
  final int waitingFareMnt;
  final int waitingSeconds;

  /// The flag-fall, charged once at the start. Zero for a driver who
  /// charges none — the default for a street hail — and on every entry
  /// written before the charge existed.
  final int boardingFareMnt;

  /// The booking base charged once at the start (spec §7.4) — a booked ride's
  /// flat fee, distinct from the flag-fall. Zero for a driver who charges none,
  /// and on every entry written before the offline meter billed it.
  final int bookingBaseFareMnt;

  /// The whole-trip-duration share of [fareMnt] — the third rate, billed on
  /// every second of the run whether the car was moving or not.
  ///
  /// Stored rather than recomputed from [endedAt] − [startedAt] × a rate,
  /// because the rate a run was actually billed at is a fact about that
  /// run: a driver who changes their tariff tomorrow must not find
  /// yesterday's history quietly re-priced. Zero on a run whose driver does
  /// not charge for duration, and on every entry written before this rate
  /// existed.
  ///
  /// Does not overlap [waitingFareMnt]: a second is on one rate or the
  /// other. The overlap that used to be documented here as intentional was
  /// withdrawn in v0.4.0 — two rates at 150₮ charged 300₮ for one minute in
  /// a jam, which is not what either label promises.
  final int durationFareMnt;

  /// Time the driver had the meter paused — billed to nobody, recorded so a
  /// run whose elapsed time far exceeds its charges still explains itself.
  /// Seconds the car stood still without the driver calling it waiting.
  /// Carries no money column: the trip-duration rate already charged those
  /// minutes. Recorded so a receipt can account for a jam.
  final int stoppedSeconds;

  final int pausedSeconds;

  /// The top-up that lifted the fare to the driver's minimum, or zero when
  /// the metered charges already cleared it. Named here for the same reason
  /// every other share is: [distanceFareMnt] is derived as the total minus
  /// the shares it knows about, so a floor left out would come back as
  /// kilometres this car never drove.
  final int minFareTopUpMnt;

  const MeterTripEntry({
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.fareMnt,
    this.durationSeconds = 0,
    this.waitingFareMnt = 0,
    this.waitingSeconds = 0,
    this.durationFareMnt = 0,
    this.boardingFareMnt = 0,
    this.bookingBaseFareMnt = 0,
    this.stoppedSeconds = 0,
    this.pausedSeconds = 0,
    this.minFareTopUpMnt = 0,
  });

  /// The distance share of [fareMnt]. Derived rather than stored so the rows
  /// of a breakdown can never add up to something other than the total the
  /// driver was actually paid — and so an entry written before the
  /// time-based rates existed reads correctly as an all-distance run.
  ///
  /// Every non-distance share must be subtracted here, which is why adding
  /// the duration rate had to change this line: while it read
  /// `fareMnt - waitingFareMnt`, a run billed for its duration would have
  /// had that whole charge silently folded into the distance row, and a
  /// driver reading their own history would have seen a distance fare that
  /// their tariff and their odometer could not produce. A derived field
  /// stays honest only as long as everything it derives *from* is named in
  /// it.
  int get distanceFareMnt =>
      fareMnt -
      waitingFareMnt -
      durationFareMnt -
      boardingFareMnt -
      bookingBaseFareMnt -
      minFareTopUpMnt;

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt,
    'endedAt': endedAt,
    'durationSeconds': durationSeconds,
    'distanceMeters': distanceMeters,
    'fareMnt': fareMnt,
    'waitingFareMnt': waitingFareMnt,
    'waitingSeconds': waitingSeconds,
    'durationFareMnt': durationFareMnt,
    'boardingFareMnt': boardingFareMnt,
    'bookingBaseFareMnt': bookingBaseFareMnt,
    'stoppedSeconds': stoppedSeconds,
    'pausedSeconds': pausedSeconds,
    'minFareTopUpMnt': minFareTopUpMnt,
  };

  /// Absent breakdown fields read as zero rather than throwing: entries
  /// written by an earlier version of the app are already on real devices,
  /// and a driver's own trip history is not worth losing over a field that
  /// did not exist yet.
  factory MeterTripEntry.fromJson(Map<String, dynamic> json) => MeterTripEntry(
    startedAt: json['startedAt'] as int,
    endedAt: json['endedAt'] as int,
    durationSeconds: json['durationSeconds'] as int? ?? 0,
    distanceMeters: json['distanceMeters'] as int,
    fareMnt: json['fareMnt'] as int,
    waitingFareMnt: json['waitingFareMnt'] as int? ?? 0,
    waitingSeconds: json['waitingSeconds'] as int? ?? 0,
    durationFareMnt: json['durationFareMnt'] as int? ?? 0,
    boardingFareMnt: json['boardingFareMnt'] as int? ?? 0,
    bookingBaseFareMnt: json['bookingBaseFareMnt'] as int? ?? 0,
    stoppedSeconds: json['stoppedSeconds'] as int? ?? 0,
    pausedSeconds: json['pausedSeconds'] as int? ?? 0,
    minFareTopUpMnt: json['minFareTopUpMnt'] as int? ?? 0,
  );
}

abstract interface class MeterJournalStore {
  Future<void> append(MeterTripEntry entry);
  Future<List<MeterTripEntry>> loadAll();

  /// Drops the run that began at [startedAt], and says nothing when no run
  /// did -- a journal the driver has already deleted from twice is not an
  /// error condition.
  ///
  /// Keyed by the start second rather than by list position, because the
  /// only caller reads the journal, sorts it for display and then hands one
  /// entry back: an index into *that* order means nothing to a store that
  /// keeps its own. Two runs cannot share a start second -- a run spans at
  /// least one GPS interval -- but if one ever did, both go, which is the
  /// safe direction for a delete the driver asked for.
  Future<void> delete(int startedAt);
}

/// Persists the journal as one JSON array under a single
/// `shared_preferences` key. A local append-only list of a few dozen
/// entries a day comfortably fits `shared_preferences`' expected size
/// envelope; a real database is unwarranted for this MVP volume (YAGNI).
class SharedPreferencesMeterJournalStore implements MeterJournalStore {
  static const _key = 'takhi_meter_journal';
  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesMeterJournalStore(this._prefs);

  @override
  Future<void> append(MeterTripEntry entry) async {
    final prefs = await _prefs();
    final all = await loadAll();
    final updated = [...all, entry];
    await prefs.setString(
      _key,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Future<List<MeterTripEntry>> loadAll() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MeterTripEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> delete(int startedAt) async {
    final prefs = await _prefs();
    final all = await loadAll();
    final kept = all.where((e) => e.startedAt != startedAt).toList();
    // Written back even when nothing matched: re-encoding a list this size
    // costs nothing, and a branch that skips the write is a branch that can
    // be wrong about whether it matched.
    await prefs.setString(
      _key,
      jsonEncode(kept.map((e) => e.toJson()).toList()),
    );
  }
}

/// Test double, mirrors `InMemoryKeyStore`.
class InMemoryMeterJournalStore implements MeterJournalStore {
  final List<MeterTripEntry> _entries = [];

  @override
  Future<void> append(MeterTripEntry entry) async => _entries.add(entry);

  @override
  Future<List<MeterTripEntry>> loadAll() async => List.unmodifiable(_entries);

  @override
  Future<void> delete(int startedAt) async =>
      _entries.removeWhere((e) => e.startedAt == startedAt);
}
