// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device's own phone number is attached to the exact-
/// location handoff DM (spec §7.3-②), and the number itself. Local-only
/// -- never published anywhere, never sent to a relay on its own; it only
/// ever travels inside an already-NIP-17-encrypted `RideHandoffPayload`
/// addressed to one specific, already-selected driver (`handoff_service.
/// dart`, Step 8 below). Mirrors `TariffStore` (Plan 4)'s
/// interface/implementation shape exactly.
abstract interface class PhoneShareSettingsStore {
  /// Defaults to `true` (spec §7.3-②: "toggle (default: асаалттай)") --
  /// callers must explicitly opt OUT, not opt in, matching the spec's
  /// literal default.
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
  Future<String?> loadOwnPhone();
  Future<void> saveOwnPhone(String phone);
}

const _kEnabledKey = 'takhi_phone_share_enabled';
const _kPhoneKey = 'takhi_phone_share_own_number';

class SharedPreferencesPhoneShareSettingsStore
    implements PhoneShareSettingsStore {
  final Future<SharedPreferences> Function() _instance;
  SharedPreferencesPhoneShareSettingsStore(this._instance);

  @override
  Future<bool> isEnabled() async =>
      (await _instance()).getBool(_kEnabledKey) ?? true;

  @override
  Future<void> setEnabled(bool enabled) async =>
      (await _instance()).setBool(_kEnabledKey, enabled);

  @override
  Future<String?> loadOwnPhone() async =>
      (await _instance()).getString(_kPhoneKey);

  @override
  Future<void> saveOwnPhone(String phone) async =>
      (await _instance()).setString(_kPhoneKey, phone);
}

/// Test double, mirrors `InMemoryTariffStore` (Plan 4)/`InMemoryKeyStore`
/// (Plan 1).
class InMemoryPhoneShareSettingsStore implements PhoneShareSettingsStore {
  bool _enabled = true;
  String? _phone;

  @override
  Future<bool> isEnabled() async => _enabled;
  @override
  Future<void> setEnabled(bool enabled) async => _enabled = enabled;
  @override
  Future<String?> loadOwnPhone() async => _phone;
  @override
  Future<void> saveOwnPhone(String phone) async => _phone = phone;
}
