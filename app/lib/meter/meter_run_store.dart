// SPDX-License-Identifier: AGPL-3.0-or-later

/// Where an in-progress run is kept so it can outlive the process.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'meter_run_snapshot.dart';

/// How stale a snapshot may be before it is treated as abandoned rather
/// than interrupted, measured from its last fix.
///
/// Six hours is roughly a shift. Inside that window an unfinished run is
/// almost certainly the one the driver is standing in the middle of, and
/// restoring it hands back a fare they would otherwise have to invent.
/// Outside it, silently resuming would put a stranger's kilometres on the
/// next passenger's bill, which is the one direction this app does not
/// resolve doubt in.
const int kMaxResumeAgeSeconds = 6 * 60 * 60;

abstract interface class MeterRunStore {
  Future<void> save(MeterRunSnapshot snapshot);

  /// The interrupted run, or `null` when there is none.
  Future<MeterRunSnapshot?> load();

  Future<void> clear();
}

class SharedPreferencesMeterRunStore implements MeterRunStore {
  static const _key = 'takhi_meter_run_in_progress';

  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesMeterRunStore(this._prefs);

  @override
  Future<void> save(MeterRunSnapshot snapshot) async {
    final prefs = await _prefs();
    await prefs.setString(_key, snapshot.encode());
  }

  @override
  Future<MeterRunSnapshot?> load() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return MeterRunSnapshot.decode(raw);
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_key);
  }
}

class InMemoryMeterRunStore implements MeterRunStore {
  MeterRunSnapshot? _value;

  @override
  Future<void> save(MeterRunSnapshot snapshot) async => _value = snapshot;

  @override
  Future<MeterRunSnapshot?> load() async => _value;

  @override
  Future<void> clear() async => _value = null;
}

/// Whether [snapshot] is recent enough to put back on the clock.
///
/// [nowSeconds] is passed in rather than read from the system clock so the
/// boundary is testable — the one place this decision is made is also the
/// one place it could quietly start charging the wrong passenger.
bool isResumable(MeterRunSnapshot snapshot, int nowSeconds) {
  final age = nowSeconds - snapshot.lastFixSeconds;
  // A snapshot whose clock is ahead of ours (the device time changed, or a
  // timezone shifted underneath it) is not evidence of a stale run. Treat
  // it as current: the driver is more likely mid-shift than time-travelling.
  if (age < 0) return true;
  return age <= kMaxResumeAgeSeconds;
}
