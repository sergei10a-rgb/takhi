// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The diagnostic has to survive the thing it is diagnosing.
//
// One of the suspects for the missing kilometres is Android killing the app
// once it goes to the background. A log that only ever lived in memory
// would vanish in exactly that case, so these tests pin the part that
// writes rows out as they are measured -- and pin that a storage failure
// costs the rows and never the fare.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/meter/meter_diagnostic_recorder.dart';
import 'package:takhi/meter/meter_diagnostics_file.dart';
import 'package:takhi/meter/meter_diagnostics_report.dart';
import 'package:takhi/meter/meter_fix_verdict.dart';

const _fix = GpsFix(
  lat: 47.9186,
  lon: 106.9176,
  timestampSeconds: 1000,
  accuracyMeters: 12,
);

const _travelled = MeterFixVerdict(
  outcome: MeterFixOutcome.travelled,
  seconds: 5,
  rawMeters: 40,
  countedMeters: 40,
  noiseFloorMeters: 24,
  speedKmh: 28.8,
);

/// Fails every write, like a full disk.
class _BrokenSink implements MeterDiagnosticSink {
  @override
  Future<void> append(String rows) async => throw Exception('storage full');

  @override
  Future<void> beginRun(String header) async =>
      throw Exception('storage full');

  @override
  Future<String?> read() async => null;

  @override
  Future<void> clear() async {}
}

void main() {
  test('begin writes the header and nothing else', () async {
    final sink = InMemoryMeterDiagnosticSink();
    final recorder = MeterDiagnosticRecorder(sink);
    await recorder.begin();

    expect(await sink.read(), kMeterDiagnosticCsvHeader);
  });

  test('rows reach storage once a batch fills, and read-back flushes the '
      'rest', () async {
    final sink = InMemoryMeterDiagnosticSink();
    final recorder = MeterDiagnosticRecorder(sink, flushEvery: 3);
    await recorder.begin();

    for (var i = 0; i < 2; i++) {
      recorder.record(
        fix: _fix,
        arrivalMillis: i * 5000,
        verdict: _travelled,
      );
    }
    // Under the batch size: still only the header on disk, but the live log
    // already knows about them — the summary never waits for a flush.
    expect((await sink.read())!.trim().split('\n').length, 1);
    expect(recorder.log.recordedCount, 2);

    recorder.record(fix: _fix, arrivalMillis: 10000, verdict: _travelled);
    final afterBatch = await recorder.readRows();
    expect(afterBatch!.trim().split('\n').length, 4); // header + 3

    recorder.record(fix: _fix, arrivalMillis: 15000, verdict: _travelled);
    final afterFlush = await recorder.readRows();
    expect(afterFlush!.trim().split('\n').length, 5);
  });

  test('row indices keep counting across batches', () async {
    final sink = InMemoryMeterDiagnosticSink();
    final recorder = MeterDiagnosticRecorder(sink, flushEvery: 2);
    await recorder.begin();

    for (var i = 0; i < 4; i++) {
      recorder.record(
        fix: _fix,
        arrivalMillis: i * 5000,
        verdict: _travelled,
      );
    }
    final rows = (await recorder.readRows())!.trim().split('\n');

    // A file whose numbering restarted at each flush would read as four
    // separate runs stitched together, which is worse than no numbering.
    expect(rows[1], startsWith('0,'));
    expect(rows[2], startsWith('1,'));
    expect(rows[3], startsWith('2,'));
    expect(rows[4], startsWith('3,'));
  });

  test('arrival offsets stay relative to the first fix across batches',
      () async {
    final sink = InMemoryMeterDiagnosticSink();
    final recorder = MeterDiagnosticRecorder(sink, flushEvery: 2);
    await recorder.begin();

    // A run that started at an arbitrary wall-clock moment.
    for (var i = 0; i < 4; i++) {
      recorder.record(
        fix: _fix,
        arrivalMillis: 1700000000000 + i * 5000,
        verdict: _travelled,
      );
    }
    final rows = (await recorder.readRows())!.trim().split('\n');

    // Second column is the offset. If a later batch re-based on its own
    // first row it would restart at 0 mid-file and hide a stall.
    expect(rows[1].split(',')[1], '0');
    expect(rows[4].split(',')[1], '15000');
  });

  test('a storage failure is kept, not swallowed, and the log keeps '
      'measuring', () async {
    final recorder = MeterDiagnosticRecorder(_BrokenSink(), flushEvery: 1);
    await recorder.begin();
    recorder.record(fix: _fix, arrivalMillis: 0, verdict: _travelled);
    await recorder.flush();

    // Surfaced, so the report can say the rows are incomplete...
    expect(recorder.lastWriteError, isNotNull);
    // ...and the run's own numbers are untouched, because a diagnostic must
    // never be able to take a fare down with it.
    expect(recorder.log.recordedCount, 1);
    expect(recorder.log.countedMeters, 40);
  });

  test('begin clears the error from a previous run', () async {
    final recorder = MeterDiagnosticRecorder(_BrokenSink(), flushEvery: 1);
    await recorder.begin();
    expect(recorder.lastWriteError, isNotNull);

    final healthy = MeterDiagnosticRecorder(InMemoryMeterDiagnosticSink());
    await healthy.begin();
    expect(healthy.lastWriteError, isNull);
  });
}
