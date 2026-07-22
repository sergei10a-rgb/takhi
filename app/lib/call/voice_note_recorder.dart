// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record_pkg;

/// Opus encoding parameters for voice notes -- deliberately far below
/// `package:record`'s own `RecordConfig` defaults (128000bps, 2 channels,
/// verified in `record_platform_interface-1.6.0`'s `RecordConfig`) so that a
/// full 10-second recording stays inside `voice_note_service.dart`'s
/// `kMaxVoiceNoteBytes` (35KB) budget. At the package defaults, 128kbps
/// stereo fills that budget in ~2.2s -- nowhere near the spec's "10 сек"
/// (§7.3-③) promise. At 24kbps mono, 10s of Opus is ~30,000 bytes
/// (~29.3KB), comfortably under the 35KB cap with headroom for
/// variable-bitrate overhead. `voice_note_recorder_test.dart` asserts this
/// arithmetic against the real `kMaxVoiceNoteDurationSeconds`/
/// `kMaxVoiceNoteBytes` constants so the two files can't silently drift.
const int kVoiceNoteBitRate = 24000;
const int kVoiceNoteSampleRate = 16000;
const int kVoiceNoteChannels = 1;

/// The [record_pkg.RecordConfig] every real recording uses. Pulled out as a
/// top-level constant (rather than inlined in [RecordPackageVoiceNoteRecorder
/// .start]) so a plain unit test can assert its byte budget without needing
/// a real microphone or a mocked `path_provider` channel.
const record_pkg.RecordConfig kVoiceNoteRecordConfig = record_pkg.RecordConfig(
  encoder: record_pkg.AudioEncoder.opus,
  bitRate: kVoiceNoteBitRate,
  sampleRate: kVoiceNoteSampleRate,
  numChannels: kVoiceNoteChannels,
);

/// Thrown by [RecordPackageVoiceNoteRecorder.start] when Opus recording is
/// not supported on the current platform/OS version -- e.g. Android below
/// API 29 (`Build.VERSION_CODES.Q`), where `record_android`'s
/// `OpusFormat.getContainer()` throws a native `IllegalAccessException` if a
/// recording is attempted anyway. Checking `AudioRecorder.isEncoderSupported`
/// up front turns that native crash into a catchable Dart exception so
/// callers (Task 7's `CallService`) can fall back instead of crashing.
class VoiceNoteEncoderUnsupportedException implements Exception {
  const VoiceNoteEncoderUnsupportedException();
  @override
  String toString() =>
      'VoiceNoteEncoderUnsupportedException: Opus recording is not '
      'supported on this device/OS version';
}

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
  RecordPackageVoiceNoteRecorder({record_pkg.AudioRecorder? recorder})
    : _recorder = recorder ?? record_pkg.AudioRecorder();

  final record_pkg.AudioRecorder _recorder;
  DateTime? _startedAt;
  String? _path;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final encoderSupported = await _recorder.isEncoderSupported(
      record_pkg.AudioEncoder.opus,
    );
    if (!encoderSupported) {
      throw const VoiceNoteEncoderUnsupportedException();
    }

    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/takhi-voice-note-${DateTime.now().millisecondsSinceEpoch}.ogg';
    _startedAt = DateTime.now();
    await _recorder.start(kVoiceNoteRecordConfig, path: _path!);
  }

  @override
  Future<(List<int>, int)> stop() async {
    final path = await _recorder.stop();
    final durationSeconds = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inSeconds;
    if (path == null) return (const <int>[], durationSeconds);
    final file = File(path);
    final bytes = await file.readAsBytes();
    // Review minor: the recording is already fully read into [bytes]
    // above (which is what `CallScreen`/`VoiceNoteService.send` actually
    // use) -- leaving the on-disk copy behind forever, one new file per
    // recording, served no purpose and is the sending-side twin of the
    // exact same never-cleaned-up temp file issue on the receiving side
    // (`AudioPlayersVoiceNotePlayer`).
    if (await file.exists()) await file.delete();
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
