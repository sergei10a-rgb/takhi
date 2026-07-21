// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import '../ride/ride_dm_channel.dart';
import '../ride/ride_dm_payload.dart';

/// Spec §7.3-③'s own numbers: "≤10 сек opus ~30KB". [kMaxVoiceNoteBytes]
/// is set slightly above the literal ~30KB target (35KB) to give Opus's
/// variable bitrate a little headroom without ever approving a note that
/// would meaningfully miss the spec's intent.
const int kMaxVoiceNoteDurationSeconds = 10;
const int kMaxVoiceNoteBytes = 35 * 1024;

class VoiceNoteTooLongException implements Exception {
  final int actualSeconds;
  const VoiceNoteTooLongException(this.actualSeconds);
  @override
  String toString() =>
      'VoiceNoteTooLongException: ${actualSeconds}s exceeds '
      '${kMaxVoiceNoteDurationSeconds}s';
}

class VoiceNoteTooLargeException implements Exception {
  final int actualBytes;
  const VoiceNoteTooLargeException(this.actualBytes);
  @override
  String toString() =>
      'VoiceNoteTooLargeException: $actualBytes bytes exceeds '
      '$kMaxVoiceNoteBytes bytes';
}

/// Throws [VoiceNoteTooLongException]/[VoiceNoteTooLargeException] if
/// [audioBytes]/[durationSeconds] exceed spec §7.3-③'s limits. Pure and
/// synchronous -- called by [VoiceNoteService.send] before it ever touches
/// the network, so an oversized recording is rejected locally and never
/// published (verified by this task's "rejects an oversized note before
/// touching the network" test, which asserts nothing was sent).
void validateVoiceNoteAudio(List<int> audioBytes, int durationSeconds) {
  if (durationSeconds > kMaxVoiceNoteDurationSeconds) {
    throw VoiceNoteTooLongException(durationSeconds);
  }
  if (audioBytes.length > kMaxVoiceNoteBytes) {
    throw VoiceNoteTooLargeException(audioBytes.length);
  }
}

class ReceivedVoiceNote {
  final String senderPubkey;
  final VoiceNotePayload payload;
  const ReceivedVoiceNote(this.senderPubkey, this.payload);
}

/// Sends/receives short voice messages over the existing `RideDmChannel`
/// -- the reliable, NAT-agnostic last rung of the calling fallback chain.
class VoiceNoteService {
  final RideDmChannel _dm;
  VoiceNoteService(this._dm);

  Future<void> send({
    required String senderPrivHex,
    required String recipientPubHex,
    required String tripId,
    required List<int> audioBytes,
    required int durationSeconds,
    required int now,
  }) async {
    validateVoiceNoteAudio(audioBytes, durationSeconds);
    await _dm.send(
      senderPrivHex: senderPrivHex,
      recipientPubHex: recipientPubHex,
      payload: VoiceNotePayload(
        tripId: tripId,
        audioBase64: base64Encode(audioBytes),
        durationSeconds: durationSeconds,
      ),
      now: now,
    );
  }

  Stream<ReceivedVoiceNote> watchVoiceNotes(
    String myPubHex,
    String myPrivHex,
  ) {
    return _dm
        .inbox(myPubHex, myPrivHex)
        .where((dm) => dm.payload is VoiceNotePayload)
        .map(
          (dm) => ReceivedVoiceNote(
            dm.senderPubkey,
            dm.payload as VoiceNotePayload,
          ),
        );
  }
}
