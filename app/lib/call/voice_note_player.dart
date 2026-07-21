// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Plays back a received voice note's base64 Opus payload. Writes it to a
/// short-lived temp file rather than `BytesSource` directly -- keeps this
/// class's behavior identical across the `audioplayers` platform backends,
/// which have historically had uneven `BytesSource` support, at the cost
/// of one small, self-cleaning temp-file write per playback.
class VoiceNotePlayer {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playBase64(String audioBase64) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/takhi-voice-note-playback-${DateTime.now().millisecondsSinceEpoch}.ogg';
    final file = File(path);
    await file.writeAsBytes(base64Decode(audioBase64));
    await _player.play(DeviceFileSource(path));
  }

  Future<void> stop() => _player.stop();
}
