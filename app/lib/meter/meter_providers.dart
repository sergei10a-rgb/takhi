// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meter_journal.dart';
import 'routing_client.dart';
import 'tariff_store.dart';

final tariffStoreProvider = Provider<TariffStore>(
  (ref) => SharedPreferencesTariffStore(SharedPreferences.getInstance),
);

final meterJournalStoreProvider = Provider<MeterJournalStore>(
  (ref) => SharedPreferencesMeterJournalStore(SharedPreferences.getInstance),
);

final routingClientProvider = Provider<RoutingClient>(
  (ref) => OsrmRoutingClient(defaultRoutingEndpoints.first),
);
