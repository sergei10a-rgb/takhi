// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emergency_contact_store.dart';

// ShareSession (Task 8) is created directly by ActiveTripView (a fresh
// one per "start sharing" tap, not a singleton), so it needs no provider
// of its own -- this file exists from Task 8 onward so Task 9's
// EmergencyContactStore provider has an established home alongside it,
// matching call_providers.dart's role for app/lib/call/.
final emergencyContactStoreProvider = Provider<EmergencyContactStore>(
  (ref) =>
      SharedPreferencesEmergencyContactStore(SharedPreferences.getInstance),
);
