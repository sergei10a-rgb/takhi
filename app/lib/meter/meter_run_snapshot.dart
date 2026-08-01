// SPDX-License-Identifier: AGPL-3.0-or-later

/// Enough of a running meter to put it back together after the app dies.
///
/// The foreground service (AndroidManifest.xml) makes an outright kill much
/// less likely, but "much less likely" is not a guarantee a driver can bank
/// a fare on. Losing a run halfway is not a cosmetic failure: there is no
/// record of the distance, no way to reconstruct it, and the driver has to
/// either guess a price or work for nothing. Both are worse than a phone
/// that asks one question when it comes back.
///
/// Deliberately stores the *accumulated totals* rather than the fix track.
/// A snapshot of every reading would grow without bound over a long shift,
/// and the totals are what the fare is made of — re-deriving them would
/// re-run the same jitter rules over the same points and land in the same
/// place, at the cost of writing kilobytes every five seconds.
library;

import 'dart:convert';

/// One interrupted run.
class MeterRunSnapshot {
  final int mntPerKm;
  final int waitTariffMntPerMinute;
  final int durationTariffMntPerMinute;

  /// Unix seconds the run started, so a resumed run's receipt still says
  /// when it actually began rather than when the app came back.
  final int startedAtSeconds;

  final int distanceMeters;
  final int waitingSeconds;
  final int billableDurationSeconds;
  final int pausedSeconds;
  final bool isPaused;

  /// Unix seconds of the last fix folded in, so a resumed run knows how old
  /// its own numbers are.
  final int lastFixSeconds;

  const MeterRunSnapshot({
    required this.mntPerKm,
    required this.waitTariffMntPerMinute,
    required this.durationTariffMntPerMinute,
    required this.startedAtSeconds,
    required this.distanceMeters,
    required this.waitingSeconds,
    required this.billableDurationSeconds,
    required this.pausedSeconds,
    required this.isPaused,
    required this.lastFixSeconds,
  });

  Map<String, Object?> toJson() => {
    'mntPerKm': mntPerKm,
    'waitTariff': waitTariffMntPerMinute,
    'durationTariff': durationTariffMntPerMinute,
    'startedAt': startedAtSeconds,
    'distanceMeters': distanceMeters,
    'waitingSeconds': waitingSeconds,
    'billableDurationSeconds': billableDurationSeconds,
    'pausedSeconds': pausedSeconds,
    'isPaused': isPaused,
    'lastFixSeconds': lastFixSeconds,
  };

  /// Reads a snapshot back, or `null` if the stored value is not one.
  ///
  /// Returns null rather than throwing on anything malformed. This is read
  /// at app start; a parse error that propagated would turn a corrupt
  /// preference into a phone that cannot open its own taximeter, which is a
  /// far worse failure than losing the run the snapshot was meant to save.
  static MeterRunSnapshot? fromJson(Map<String, Object?> json) {
    final mntPerKm = json['mntPerKm'];
    final startedAt = json['startedAt'];
    if (mntPerKm is! int || startedAt is! int) return null;
    int intOr(String key) {
      final value = json[key];
      return value is int && value >= 0 ? value : 0;
    }

    return MeterRunSnapshot(
      mntPerKm: mntPerKm,
      waitTariffMntPerMinute: intOr('waitTariff'),
      durationTariffMntPerMinute: intOr('durationTariff'),
      startedAtSeconds: startedAt,
      distanceMeters: intOr('distanceMeters'),
      waitingSeconds: intOr('waitingSeconds'),
      billableDurationSeconds: intOr('billableDurationSeconds'),
      pausedSeconds: intOr('pausedSeconds'),
      isPaused: json['isPaused'] == true,
      lastFixSeconds: intOr('lastFixSeconds'),
    );
  }

  String encode() => jsonEncode(toJson());

  static MeterRunSnapshot? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return fromJson(decoded);
    } on FormatException {
      return null;
    }
  }
}
