// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' as record_pkg;
import 'package:takhi/call/voice_note_recorder.dart';
import 'package:takhi/call/voice_note_service.dart' show kMaxVoiceNoteBytes;

/// `record` 6.x's `AudioRecorder()` constructor itself now calls through
/// the platform channel (a `create` message, to allocate a native recorder
/// session) instead of staying lazy until `.start()` as it did on 5.x --
/// confirmed live while fixing this test against the real `record: ^6.2.0`
/// bump (Task 10, `flutter build apk --release` dependency-consistency
/// fix, see `pubspec.yaml`). A plain `test()` has no
/// `TestWidgetsFlutterBinding`/mock messenger, so that channel call would
/// throw "Binding has not yet been initialized" -- this stub responds to
/// it so `_StubAudioRecorder()`'s constructor succeeds without ever
/// reaching a real platform.
const _recordChannel = MethodChannel('com.llfbandit.record/messages');

/// Records which [record_pkg.AudioRecorder] methods were invoked and lets a
/// test control [isEncoderSupported]'s answer. Every method this test cares
/// about is overridden here so it never calls through to
/// `RecordPlatform.instance` -- only the base constructor's platform-channel
/// call (mocked above) is unavoidable.
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
  Future<bool> hasPermission({bool request = true}) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordChannel, (call) async => null);

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
