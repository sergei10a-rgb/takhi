// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Abstracts playback of a received voice note's base64 Opus payload
/// behind a plain play/stop pair -- mirrors [VoiceNoteRecorder]'s role on
/// the sending side (`voice_note_recorder.dart`), letting `ActiveTripView`
/// (Plan 5 review CRITICAL-3 fix: wiring up the *receiving* side of
/// spec §7.3-③'s voice-note fallback) be tested with a fake player
/// instead of a real `audioplayers`/`path_provider` platform channel.
abstract interface class VoiceNotePlayer {
  Future<void> playBase64(String audioBase64);
  Future<void> stop();
}

/// Real [VoiceNotePlayer] backed by `package:audioplayers`. Writes the
/// decoded payload to a short-lived temp file rather than `BytesSource`
/// directly -- keeps this class's behavior identical across the
/// `audioplayers` platform backends, which have historically had uneven
/// `BytesSource` support, at the cost of one small, self-cleaning
/// temp-file write per playback: [_lastTempPath] deletes the *previous*
/// playback's file the moment a new one starts (or [stop] is called),
/// rather than never deleting it at all -- across a long trip with
/// several fallback voice notes, that used to leave one new `.ogg` file
/// behind in the OS temp directory per playback, forever (review minor:
/// this class's own doc comment already claimed "self-cleaning" while the
/// code never actually deleted anything).
class AudioPlayersVoiceNotePlayer implements VoiceNotePlayer {
  final AudioPlayer _player = AudioPlayer();
  String? _lastTempPath;

  @override
  Future<void> playBase64(String audioBase64) async {
    await _deleteLastTempFile();
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/takhi-voice-note-playback-${DateTime.now().millisecondsSinceEpoch}.ogg';
    final file = File(path);
    await file.writeAsBytes(base64Decode(audioBase64));
    _lastTempPath = path;
    await _player.play(DeviceFileSource(path));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await _deleteLastTempFile();
  }

  Future<void> _deleteLastTempFile() async {
    final path = _lastTempPath;
    if (path == null) return;
    _lastTempPath = null;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

/// Test double -- records calls instead of touching any platform channel,
/// mirrors [FakeVoiceNoteRecorder]'s role on the sending side.
class FakeVoiceNotePlayer implements VoiceNotePlayer {
  final List<String> played = [];
  bool stopped = false;

  @override
  Future<void> playBase64(String audioBase64) async {
    played.add(audioBase64);
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
