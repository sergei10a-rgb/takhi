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
  final int distanceMeters;

  /// What the run came to in total — distance plus waiting.
  final int fareMnt;

  /// The waiting half of [fareMnt], and the time it was charged for (spec
  /// §7.4). Zero on a run where the vehicle never stopped, and on every
  /// entry written before waiting fares existed.
  final int waitingFareMnt;
  final int waitingSeconds;

  /// Time the driver had the meter paused — billed to nobody, recorded so a
  /// run whose elapsed time far exceeds its charges still explains itself.
  final int pausedSeconds;

  const MeterTripEntry({
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.fareMnt,
    this.waitingFareMnt = 0,
    this.waitingSeconds = 0,
    this.pausedSeconds = 0,
  });

  /// The distance half of [fareMnt]. Derived rather than stored so the two
  /// rows of a breakdown can never add up to something other than the total
  /// the driver was actually paid — and so an entry written before waiting
  /// fares existed reads correctly as an all-distance run.
  int get distanceFareMnt => fareMnt - waitingFareMnt;

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt,
    'endedAt': endedAt,
    'distanceMeters': distanceMeters,
    'fareMnt': fareMnt,
    'waitingFareMnt': waitingFareMnt,
    'waitingSeconds': waitingSeconds,
    'pausedSeconds': pausedSeconds,
  };

  /// Absent breakdown fields read as zero rather than throwing: entries
  /// written by an earlier version of the app are already on real devices,
  /// and a driver's own trip history is not worth losing over a field that
  /// did not exist yet.
  factory MeterTripEntry.fromJson(Map<String, dynamic> json) => MeterTripEntry(
    startedAt: json['startedAt'] as int,
    endedAt: json['endedAt'] as int,
    distanceMeters: json['distanceMeters'] as int,
    fareMnt: json['fareMnt'] as int,
    waitingFareMnt: json['waitingFareMnt'] as int? ?? 0,
    waitingSeconds: json['waitingSeconds'] as int? ?? 0,
    pausedSeconds: json['pausedSeconds'] as int? ?? 0,
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
