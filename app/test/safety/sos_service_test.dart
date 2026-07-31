// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/safety/sos_service.dart';

void main() {
  test('buildEmergencyDialUri produces a tel: URI for the given number', () {
    final uri = buildEmergencyDialUri(kPoliceNumber);
    expect(uri.scheme, 'tel');
    expect(uri.path, '102');
  });

  test(
    'buildEmergencyDialUri works for the ambulance and fire numbers too',
    () {
      expect(buildEmergencyDialUri(kAmbulanceNumber).path, '103');
      expect(buildEmergencyDialUri(kFireNumber).path, '101');
    },
  );

  test('buildEmergencySmsUri addresses the contact and includes the Plus '
      'Code in the body', () {
    final uri = buildEmergencySmsUri(
      contactPhone: '99887766',
      plusCode: '8Q7XPJ9Q+2V',
      lat: 47.9186,
      lon: 106.9176,
    );
    expect(uri.scheme, 'sms');
    expect(uri.path, '99887766');
    final body = uri.queryParameters['body']!;
    expect(body.contains('8Q7XPJ9Q+2V'), isTrue);
    expect(body.contains('47.9186'), isTrue);
    expect(body.contains('106.9176'), isTrue);
  });
}
