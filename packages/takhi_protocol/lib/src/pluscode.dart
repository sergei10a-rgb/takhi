// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:open_location_code/open_location_code.dart' as olc;

String plusCodeEncode(double lat, double lon) =>
    olc.PlusCode.encode(olc.LatLng(lat, lon), codeLength: 11).toString();

({double lat, double lon}) plusCodeDecodeCenter(String code) {
  final area = olc.PlusCode(code).decode();
  return (lat: area.center.latitude, lon: area.center.longitude);
}
