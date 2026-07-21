// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' as record_pkg;
import 'package:takhi/call/voice_note_recorder.dart';
import 'package:takhi/call/voice_note_service.dart' show kMaxVoiceNoteBytes;

/// Records which [record_pkg.AudioRecorder] methods were invoked and lets a
/// test control [isEncoderSupported]'s answer, without ever touching the
/// real platform channel -- `AudioRecorder`'s methods are plain (non-final)
/// so overriding them here never calls through to `RecordPlatform.instance`.
class _StubAudioRecorder extends record_pkg.AudioRecorder {
  bool encoderSupported = true;
  bool startCalled = false;
  record_pkg.RecordConfig? lastConfig;

  @override
  Future<bool> isEncoderSupported(record_pkg.AudioEncoder encoder) async =>
      encoderSupported;

  @override
  Future<void> start(
    record_pkg.RecordConfig config, {
    required String path,
  }) async {
    startCalled = true;
    lastConfig = config;
  }

  @override
  Future<String?> stop() async => null;

  @override
  Future<bool> hasPermission() async => true;
}

void main() {
  group('kVoiceNoteRecordConfig', () {
    test('opus encoder, mono, matches the tuned bitrate/sample rate', () {
      expect(kVoiceNoteRecordConfig.encoder, record_pkg.AudioEncoder.opus);
      expect(kVoiceNoteRecordConfig.bitRate, kVoiceNoteBitRate);
      expect(kVoiceNoteRecordConfig.sampleRate, kVoiceNoteSampleRate);
      expect(kVoiceNoteRecordConfig.numChannels, kVoiceNoteChannels);
    });

    test('a full-length recording stays under kMaxVoiceNoteBytes -- '
        'regression guard for the package default (128000bps/2ch) blowing '
        'through the 35KB budget in ~2.2s instead of lasting 10s', () {
      const assumedMaxDurationSeconds = 10;
      final estimatedBytes = (kVoiceNoteBitRate / 8 * assumedMaxDurationSeconds)
          .round();

      expect(estimatedBytes, lessThan(kMaxVoiceNoteBytes));

      // The package default this replaces would blow the budget in ~2.2s,
      // not last the full assumed duration -- pin that down explicitly so a
      // future accidental revert back to the default is caught here too.
      const packageDefaultBitRate = 128000;
      final secondsUntilBudgetExhausted =
          kMaxVoiceNoteBytes * 8 / packageDefaultBitRate;
      expect(secondsUntilBudgetExhausted, lessThan(assumedMaxDurationSeconds));
    });
  });

  group('RecordPackageVoiceNoteRecorder.start', () {
    test('throws VoiceNoteEncoderUnsupportedException when Opus is '
        'unsupported, without ever calling the underlying start', () async {
      final stub = _StubAudioRecorder()..encoderSupported = false;
      final recorder = RecordPackageVoiceNoteRecorder(recorder: stub);

      await expectLater(
        recorder.start,
        throwsA(isA<VoiceNoteEncoderUnsupportedException>()),
      );
      expect(stub.startCalled, isFalse);
    });
  });
}
