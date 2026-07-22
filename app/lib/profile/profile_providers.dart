// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nostr/relay_pool_provider.dart';
import 'driver_profile_service.dart';
import 'driver_profile_store.dart';

final driverProfileStoreProvider = Provider<DriverProfileStore>(
  (ref) => SharedPreferencesDriverProfileStore(SharedPreferences.getInstance),
);

final driverProfileServiceProvider = Provider<DriverProfileService>(
  (ref) => DriverProfileService(
    ref.watch(relayPoolProvider),
    ref.watch(driverProfileStoreProvider),
  ),
);
