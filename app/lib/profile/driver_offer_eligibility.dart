// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:takhi_protocol/takhi_protocol.dart';

import 'driver_photo_rules.dart';

/// What is stopping this driver from sending an offer.
enum DriverOfferBlock {
  /// Овог or нэр (or both) missing, blank, or not a usable name.
  missingName,

  /// No stored portrait -- or one that has somehow grown past the size a
  /// gift-wrapped offer can carry.
  missingPhoto,
}

/// Thrown by `OfferService.sendOffer` when [driverOfferBlock] refuses.
///
/// An exception rather than a quietly-dropped send: the driver tapped a
/// button and something has to answer them. Silence would look exactly like
/// a delivered offer that nobody replied to.
class DriverOfferBlockedException implements Exception {
  final DriverOfferBlock block;
  const DriverOfferBlockedException(this.block);
  @override
  String toString() => 'DriverOfferBlockedException: $block';
}

/// `null` when this driver may send offers.
///
/// A passenger deciding whether to get into a stranger's car at night has
/// almost nothing to go on. A name and a face are the two things that turn
/// «npub1qz8…» into a person -- one they can say out loud at the window,
/// one they can compare to the driver who pulls up. Neither is verified and
/// neither can be (see [DriverPhotoRejection]'s doc comment); what they do
/// is make a rider's own judgement possible, which is the only protection
/// that actually exists here. So they are required, not encouraged.
///
/// The rule lives in this function, and `OfferService.sendOffer` enforces
/// it, rather than living in a disabled button. A greyed-out button is a
/// suggestion: it is bypassed by a modified client, by a second code path
/// added later, and by any test that calls the service directly. The core
/// is where a rule with a safety reason behind it has to sit; the UI's job
/// is only to explain the refusal before the driver runs into it.
///
/// The name is reported first when both are missing, because it is the
/// cheaper of the two to fix -- a driver told "add a photo" who then
/// discovers they also need a name has been sent back twice.
DriverOfferBlock? driverOfferBlock({
  required String? familyName,
  required String? givenName,
  required Uint8List? photoJpeg,
}) {
  if (familyName == null || givenName == null) {
    return DriverOfferBlock.missingName;
  }
  if (!isValidDriverNamePart(familyName) || !isValidDriverNamePart(givenName)) {
    return DriverOfferBlock.missingName;
  }
  if (photoJpeg == null || photoJpeg.isEmpty) {
    return DriverOfferBlock.missingPhoto;
  }
  // A portrait over the cap is not a portrait this offer can carry: relays
  // drop oversized events, so sending it would produce an offer that simply
  // never arrives, with nothing on either screen to say why. Refusing here
  // is the difference between a message the driver can act on and silence.
  if (photoJpeg.length > kDriverPhotoMaxBytes) {
    return DriverOfferBlock.missingPhoto;
  }
  return null;
}
