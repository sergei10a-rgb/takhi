// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// The user's own pre-configured emergency contact number (spec §6 SOS).
/// Local-only, never published or sent anywhere except as the `sms:`
/// intent's destination the user themselves confirms sending -- mirrors
/// `PhoneShareSettingsStore`/`TariffStore`'s interface shape exactly.
abstract interface class EmergencyContactStore {
  Future<String?> loadPhone();
  Future<void> savePhone(String phone);
}

const _kPhoneKey = 'takhi_emergency_contact_phone';

class SharedPreferencesEmergencyContactStore implements EmergencyContactStore {
  final Future<SharedPreferences> Function() _instance;
  SharedPreferencesEmergencyContactStore(this._instance);

  @override
  Future<String?> loadPhone() async =>
      (await _instance()).getString(_kPhoneKey);

  @override
  Future<void> savePhone(String phone) async =>
      (await _instance()).setString(_kPhoneKey, phone);
}

class InMemoryEmergencyContactStore implements EmergencyContactStore {
  String? _phone;
  @override
  Future<String?> loadPhone() async => _phone;
  @override
  Future<void> savePhone(String phone) async => _phone = phone;
}
