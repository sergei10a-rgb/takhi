// SPDX-License-Identifier: AGPL-3.0-or-later

/// Official Mongolian emergency numbers (spec §6 SOS: "native dialer-ээр
/// 102/103"). Fire is included too even though the spec text names only
/// police/ambulance -- showing all three costs nothing extra and is more
/// useful in a real emergency.
const String kPoliceNumber = '102';
const String kAmbulanceNumber = '103';
const String kFireNumber = '101';

/// A `tel:` URI that opens the phone's native dialer pre-filled with
/// [number] -- `ACTION_DIAL`, not `ACTION_CALL`: the user still presses
/// the call button themselves on their own device's own dialer UI.
/// Deliberate: this app never requests the `CALL_PHONE` permission, so it
/// structurally cannot place a call the user did not explicitly confirm.
Uri buildEmergencyDialUri(String number) => Uri(scheme: 'tel', path: number);

/// An `sms:` URI pre-filled with an emergency body naming [plusCode]
/// (spec §6: "сүүлийн байршлыг (Plus Code)") plus a plain-coordinates OSM
/// link, addressed to [contactPhone] -- the user's own pre-configured
/// emergency contact (`EmergencyContactStore`), never a number this app
/// chose on its own. Opens the phone's native SMS app; the user still
/// presses send themselves (no `SEND_SMS` permission is ever requested).
Uri buildEmergencySmsUri({
  required String contactPhone,
  required String plusCode,
  required double lat,
  required double lon,
}) {
  final body =
      'SOS. Миний сүүлийн байршил: $plusCode '
      '(https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon)';
  return Uri(
    scheme: 'sms',
    path: contactPhone,
    queryParameters: {'body': body},
  );
}
