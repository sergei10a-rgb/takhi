// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nostr/relay_pool_provider.dart';
import '../ride/ride_providers.dart';
import 'call_signal_service.dart';
import 'helper_directory_service.dart';
import 'phone_share_settings.dart';

final callSignalServiceProvider = Provider<CallSignalService>(
  (ref) => CallSignalService(ref.watch(rideDmChannelProvider)),
);

final helperDirectoryServiceProvider = Provider<HelperDirectoryService>(
  (ref) => HelperDirectoryService(ref.watch(relayPoolProvider)),
);

final phoneShareSettingsStoreProvider = Provider<PhoneShareSettingsStore>(
  (ref) =>
      SharedPreferencesPhoneShareSettingsStore(SharedPreferences.getInstance),
);
