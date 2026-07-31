// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'driver_photo_codec.dart';
import 'driver_photo_face_check.dart';
import 'driver_photo_rules.dart';
import 'driver_photo_store.dart';

/// Takes whatever the image picker handed over and, if it survives both
/// checks, makes it the driver's stored portrait.
///
/// The order is compress, then look for a face, then store, and each step
/// is that way round on purpose:
///
///  * **Compress first** so the face check runs on the same 512px JPEG that
///    will actually be stored and sent. Checking the 12-megapixel original
///    and shipping the shrunken copy would be checking something other than
///    what a passenger ends up looking at.
///  * **Store last, and only on success.** A rejected photo must not
///    disturb the one already saved: a driver who has a working portrait
///    and then picks a blurry one by mistake keeps the working one, rather
///    than being left with nothing and unable to send offers until they
///    find another photo.
class DriverPhotoService {
  final FaceDetector _detector;
  final DriverPhotoStore _store;

  DriverPhotoService(this._detector, this._store);

  /// Replaces the stored portrait with [raw]. Returns `null` when the photo
  /// was accepted and saved, or the reason it was refused -- each of which
  /// the UI must turn into a *different* sentence, since "we could not read
  /// this file", "there is nobody in this picture" and "there are two
  /// people in this picture" are fixed in three different ways.
  ///
  /// Never throws for a bad photo: a picture the user chose is untrusted
  /// input, and the profile screen must show a sentence, not a crash.
  Future<DriverPhotoRejection?> replacePhoto(Uint8List raw) async {
    final compressed = compressDriverPhoto(raw);
    switch (compressed) {
      case DriverPhotoCompressionRejected(:final reason):
        return reason;
      case DriverPhotoCompressed(:final jpegBytes):
        final faceProblem = await checkDriverPhotoFace(_detector, jpegBytes);
        if (faceProblem != null) return faceProblem;
        await _store.save(jpegBytes);
        return null;
    }
  }

  /// The stored portrait, or `null` if the driver has not set one.
  Future<Uint8List?> load() => _store.load();

  /// Forgets the portrait. Leaves the driver unable to send offers until
  /// they set another, which is the intended consequence rather than a side
  /// effect -- see `driver_offer_eligibility.dart`.
  Future<void> clear() => _store.clear();
}
