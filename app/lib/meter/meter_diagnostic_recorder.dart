// SPDX-License-Identifier: AGPL-3.0-or-later

/// Ties the live [MeterDiagnosticLog] to the file the rows are kept in.
///
/// Its own class rather than a handful of fields on `TaximeterPage` for one
/// reason: the batching and the write ordering both have to be right, and a
/// screen that is also drawing a map at sixty frames a second is the wrong
/// place to reason about either.
library;

import 'dart:async';

import '../geo/gps_fix.dart';
import 'meter_diagnostics.dart';
import 'meter_diagnostics_file.dart';
import 'meter_diagnostics_report.dart';
import 'meter_fix_verdict.dart';

/// How many fixes accumulate before the rows are written out.
///
/// Twenty fixes is roughly a hundred seconds at the requested interval —
/// often enough that a crash loses very little, rare enough that the meter
/// is not touching the disk every five seconds for a whole shift.
const int kDiagnosticFlushEvery = 20;

class MeterDiagnosticRecorder {
  final MeterDiagnosticSink _sink;
  final int flushEvery;

  final MeterDiagnosticLog log = MeterDiagnosticLog();

  MeterDiagnosticRecorder(this._sink, {this.flushEvery = kDiagnosticFlushEvery});

  final List<MeterDiagnosticSample> _pending = [];
  int _writtenRows = 0;
  int? _firstArrivalMillis;
  int? _firstFixSeconds;

  /// Serialises writes. Two `append` calls racing would interleave partial
  /// lines into the file, and a corrupt row is worse than a missing one —
  /// it reads as data.
  Future<void> _writes = Future<void>.value();

  /// The last write failure, kept rather than swallowed. A diagnostic that
  /// quietly stops recording is the one thing this class must not do, so the
  /// failure is surfaced in the report instead of hidden in a log line.
  Object? lastWriteError;

  Future<void> begin() {
    _pending.clear();
    _writtenRows = 0;
    _firstArrivalMillis = null;
    _firstFixSeconds = null;
    lastWriteError = null;
    return _enqueue(() => _sink.beginRun(kMeterDiagnosticCsvHeader));
  }

  /// Files one fix. Returns immediately; the disk write happens in the
  /// background once [flushEvery] rows have piled up.
  void record({
    required GpsFix fix,
    required int arrivalMillis,
    required MeterFixVerdict verdict,
  }) {
    _firstArrivalMillis ??= arrivalMillis;
    _firstFixSeconds ??= fix.timestampSeconds;
    log.record(fix: fix, arrivalMillis: arrivalMillis, verdict: verdict);
    _pending.add(
      MeterDiagnosticSample(
        fix: fix,
        arrivalMillis: arrivalMillis,
        verdict: verdict,
      ),
    );
    if (_pending.length >= flushEvery) unawaited(flush());
  }

  /// Writes everything not yet on disk. Called on every finish, and safe to
  /// call at any other time.
  Future<void> flush() {
    if (_pending.isEmpty) return _writes;
    final batch = List<MeterDiagnosticSample>.of(_pending);
    _pending.clear();
    final startIndex = _writtenRows;
    _writtenRows += batch.length;
    final rows = formatMeterDiagnosticCsvRows(
      batch,
      firstArrivalMillis: _firstArrivalMillis ?? batch.first.arrivalMillis,
      firstFixSeconds: _firstFixSeconds ?? batch.first.fix.timestampSeconds,
      startIndex: startIndex,
    );
    return _enqueue(() => _sink.append(rows));
  }

  /// Everything on disk for the current run, or `null` when nothing was
  /// recorded.
  Future<String?> readRows() async {
    await flush();
    return _sink.read();
  }

  Future<void> _enqueue(Future<void> Function() work) {
    _writes = _writes.then((_) => work()).catchError((Object error) {
      // Storage being full or unwritable must not take a fare down with it:
      // the meter's job is to bill the trip, and the diagnostic is a
      // passenger on that journey, not the driver of it.
      lastWriteError = error;
    });
    return _writes;
  }
}
