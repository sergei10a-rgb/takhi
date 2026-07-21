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
  final int fareMnt;

  const MeterTripEntry({
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.fareMnt,
  });

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt,
        'endedAt': endedAt,
        'distanceMeters': distanceMeters,
        'fareMnt': fareMnt,
      };

  factory MeterTripEntry.fromJson(Map<String, dynamic> json) =>
      MeterTripEntry(
        startedAt: json['startedAt'] as int,
        endedAt: json['endedAt'] as int,
        distanceMeters: json['distanceMeters'] as int,
        fareMnt: json['fareMnt'] as int,
      );
}

abstract interface class MeterJournalStore {
  Future<void> append(MeterTripEntry entry);
  Future<List<MeterTripEntry>> loadAll();
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
}

/// Test double, mirrors `InMemoryKeyStore`.
class InMemoryMeterJournalStore implements MeterJournalStore {
  final List<MeterTripEntry> _entries = [];

  @override
  Future<void> append(MeterTripEntry entry) async => _entries.add(entry);

  @override
  Future<List<MeterTripEntry>> loadAll() async =>
      List.unmodifiable(_entries);
}
