// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record_pkg;

/// Abstracts Opus voice-note capture behind a plain start/stop pair so
/// `CallScreen` (Task 7) is testable with a fake recorder instead of a
/// real microphone -- mirrors `LocationSource` (Plan 4)'s role for GPS.
abstract interface class VoiceNoteRecorder {
  Future<bool> hasPermission();
  Future<void> start();

  /// Stops recording and returns the captured Opus-encoded bytes plus the
  /// elapsed duration in whole seconds.
  Future<(List<int> bytes, int durationSeconds)> stop();
}

/// Real [VoiceNoteRecorder] backed by `package:record`, recording to a
/// temporary `.ogg` (Opus) file and reading it back into memory on
/// [stop] -- `record`'s own permission handling (`hasPermission`) covers
/// `RECORD_AUDIO` without this app needing a separate `permission_handler`
/// dependency.
class RecordPackageVoiceNoteRecorder implements VoiceNoteRecorder {
  final record_pkg.AudioRecorder _recorder = record_pkg.AudioRecorder();
  DateTime? _startedAt;
  String? _path;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/takhi-voice-note-${DateTime.now().millisecondsSinceEpoch}.ogg';
    _startedAt = DateTime.now();
    await _recorder.start(
      const record_pkg.RecordConfig(encoder: record_pkg.AudioEncoder.opus),
      path: _path!,
    );
  }

  @override
  Future<(List<int>, int)> stop() async {
    final path = await _recorder.stop();
    final durationSeconds = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inSeconds;
    if (path == null) return (const <int>[], durationSeconds);
    final bytes = await File(path).readAsBytes();
    return (bytes, durationSeconds);
  }
}

/// Test double -- returns canned bytes/duration instead of recording,
/// mirrors `FakeLocationSource`'s role.
class FakeVoiceNoteRecorder implements VoiceNoteRecorder {
  bool permissionGranted = true;
  List<int> nextBytes = [1, 2, 3];
  int nextDurationSeconds = 3;
  bool started = false;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start() async => started = true;

  @override
  Future<(List<int>, int)> stop() async {
    started = false;
    return (nextBytes, nextDurationSeconds);
  }
}
