// SPDX-License-Identifier: AGPL-3.0-or-later

/// Where the diagnostic rows live between being measured and being read.
///
/// On disk rather than only in memory, because of what is being diagnosed.
/// One of the three suspects for the missing kilometres is Android stopping
/// the app once it goes to the background — and a log held in RAM dies with
/// the process it was trying to indict. A diagnostic that disappears in
/// exactly the case it exists to prove is no diagnostic at all.
///
/// Only the rows are persisted, not the summary. Every total in the report
/// is recoverable from the rows, so storing both would mean two versions of
/// the same truth and a day spent working out which one lied.
library;

import 'dart:io';

/// Rows for one meter run, appended as they are measured.
abstract interface class MeterDiagnosticSink {
  /// Adds [rows] (newline-terminated CSV, no header) to the current run.
  Future<void> append(String rows);

  /// Starts a fresh run, discarding whatever the last one left behind.
  ///
  /// Called at the start of a run rather than the end of one: a driver whose
  /// app was killed mid-trip still has yesterday's rows to send, which is
  /// the only copy of the evidence in the one case that matters most.
  Future<void> beginRun(String header);

  /// Everything recorded for the run currently on disk, or `null` if there
  /// is none.
  Future<String?> read();

  Future<void> clear();
}

/// A single file under the app's own directory.
class FileMeterDiagnosticSink implements MeterDiagnosticSink {
  /// Resolves the directory to write into. Injected rather than calling
  /// `path_provider` directly so the whole class is testable against a temp
  /// directory, the same split `DriverProfileStore` uses.
  final Future<Directory> Function() _directory;

  /// Name is stable across runs: there is only ever one diagnostic on disk,
  /// and a driver asked to "send the GPS file" must not have to choose
  /// between six of them.
  static const _fileName = 'takhi_gps_diagnostic.csv';

  const FileMeterDiagnosticSink(this._directory);

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$_fileName');

  @override
  Future<void> beginRun(String header) async {
    final file = await _file();
    await file.writeAsString(header, flush: true);
  }

  @override
  Future<void> append(String rows) async {
    if (rows.isEmpty) return;
    final file = await _file();
    // `flush: true` on every batch, deliberately. The failure being
    // investigated is the process dying without warning; buffered writes
    // that never reach the disk would reproduce the data loss this file
    // exists to survive.
    await file.writeAsString(rows, mode: FileMode.append, flush: true);
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

/// Test double.
class InMemoryMeterDiagnosticSink implements MeterDiagnosticSink {
  final StringBuffer _buffer = StringBuffer();
  bool _started = false;

  @override
  Future<void> beginRun(String header) async {
    _buffer
      ..clear()
      ..write(header);
    _started = true;
  }

  @override
  Future<void> append(String rows) async => _buffer.write(rows);

  @override
  Future<String?> read() async => _started ? _buffer.toString() : null;

  @override
  Future<void> clear() async {
    _buffer.clear();
    _started = false;
  }
}
