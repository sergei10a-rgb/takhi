// SPDX-License-Identifier: AGPL-3.0-or-later

/// The thresholds and the vocabulary of refusals for a driver's portrait.
///
/// Kept in one file, apart from both the compressor and the face check, for
/// the reason the design tokens are kept apart from the widgets: these are
/// the numbers somebody will want to *tune* after watching real drivers fail
/// to get a photo accepted in a dim ger district courtyard, and they should
/// be tunable in one place rather than hunted across two algorithms.
library;

/// What the automatic check can and cannot tell you.
///
/// **This is a gate, not proof of identity.** Everything below says only
/// "there is one human face, reasonably close, in this picture". No
/// server-less app can establish that the face is *this driver's*: a photo
/// of a friend, a celebrity, or a stranger pulled off the internet passes
/// every one of these rules, as does a photograph of a printed photograph
/// or of another phone's screen -- there is no liveness detection here at
/// all. The check is also client-side and this client is AGPL, so a
/// modified build can skip it outright; it is a barrier against the
/// careless, not against someone who means it.
///
/// The UI must say this in as many words. A passenger who believes a
/// verified badge that does not exist is worse off than one who knows they
/// are looking at an unverified picture, because they will stop applying
/// the judgement that actually protects them.
enum DriverPhotoRejection {
  /// The bytes are not an image this app can read at all -- a truncated
  /// download, a HEIC variant the decoder does not know, a renamed file.
  undecodable,

  /// Still over [kDriverPhotoMaxBytes] at the bottom of the quality ladder.
  /// Essentially unreachable once the longest edge is down to
  /// [kDriverPhotoMaxEdgePx]; it exists so that "we ran out of options" is a
  /// stated outcome rather than an oversized photo shipped anyway.
  tooLargeAfterCompression,

  /// No face at all. The single most likely cause is not a mountain
  /// photograph but a real driver standing too far from the camera, or
  /// backlit, or in the dark -- so this must be phrased as instructions
  /// ("hold the phone closer, face a window"), never as an accusation.
  noFaceFound,

  /// More than one face: a group photo, or a passenger's face in the
  /// background. A rider needs to know which of them is opening the car
  /// door, and a photo of two people answers that for neither.
  multipleFaces,

  /// A face was found, but it covers less than [kMinFaceAreaFraction] of the
  /// frame -- a person standing next to their car at ten metres. The face is
  /// then too few pixels to recognise a stranger by at night, which is the
  /// one moment the picture exists for.
  faceTooSmall,

  /// The detector itself could not run: the model is missing from the
  /// bundle, the native library failed to load, the platform is one this
  /// build has no delegate for.
  ///
  /// Deliberately a *rejection* and not a silent pass. A check that
  /// disappears when its engine is missing is worse than no check, because
  /// the promise stays on screen after the mechanism behind it is gone.
  faceCheckUnavailable,
}

/// The longest edge, in pixels, a stored portrait is scaled down to.
///
/// 512 is chosen from the far end of the pipeline rather than from how the
/// photo looks in the profile page: this image is carried inside a NIP-17
/// gift-wrapped offer, and relays drop oversized events -- so the binding
/// constraint is [kDriverPhotoMaxBytes], and the resolution is whatever
/// still looks like a person at that size. 512 fills any phone's avatar
/// circle at 3x density with pixels to spare.
///
/// Smaller images are never scaled *up*: enlarging adds bytes and no
/// information, and a driver who submits a 300px photo gets a 300px photo.
const int kDriverPhotoMaxEdgePx = 512;

/// The hard ceiling on the stored/transmitted JPEG.
///
/// The photo does not travel alone -- it shares a gift-wrapped event with
/// the offer's own fields and two layers of NIP-44 framing, and base64
/// inflates whatever it is by a third on the way. 60KB of JPEG becomes
/// roughly 80KB of base64, which sits well inside the 128KB-ish limit
/// common relays impose, with room for the rest of the payload. Going
/// bigger does not fail loudly at the sender; it fails as an offer that
/// silently never arrives, which is the worst way for this to break.
const int kDriverPhotoMaxBytes = 60 * 1024;

/// JPEG qualities tried in order, stopping at the first that fits under
/// [kDriverPhotoMaxBytes].
///
/// Descending rather than a binary search on purpose: the ladder is short,
/// each rung is cheap at 512px, and "the first quality that fits" is a rule
/// somebody reading a bug report can reproduce by hand. Stops at 40 --
/// below that a face acquires the blocking artefacts that make one stranger
/// look like another, which defeats the point of storing a face.
const List<int> kDriverPhotoJpegQualityLadder = <int>[88, 80, 70, 60, 50, 40];

/// How confident the detector must be before a detection is counted as a
/// face at all.
///
/// Detections below this are discarded *before* the one-face rule is
/// applied -- otherwise a low-confidence smudge on a wall would be counted
/// as a second person and reject a perfectly good portrait with a confusing
/// "there are two faces here".
const double kMinFaceDetectionScore = 0.55;

/// The smallest share of the frame a face may occupy, as a fraction of
/// total area.
///
/// 0.06 is a face box of roughly 125x125 inside a 512x512 frame -- an
/// arm's-length photo, comfortably passed by anyone holding a phone at
/// normal selfie distance, and failed by someone photographed standing next
/// to their car. Raising it makes the app pickier at the cost of rejecting
/// honest drivers; that trade is why the number is named and lives here.
const double kMinFaceAreaFraction = 0.06;
