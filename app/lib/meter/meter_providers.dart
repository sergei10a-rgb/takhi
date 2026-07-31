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

/// The same public OSRM endpoint, asked for the *shape* of a route instead
/// of its length -- what the passenger's trip preview draws (spec §7.1).
///
/// Its own provider rather than a cast of [routingClientProvider]: the two
/// are separate interfaces on purpose (see `routing_client.dart`), and a
/// test that wants a route drawn a particular way must be able to override
/// this without also lying to the fare estimator.
final routePathClientProvider = Provider<RoutePathClient>(
  (ref) => OsrmRoutingClient(defaultRoutingEndpoints.first),
);
