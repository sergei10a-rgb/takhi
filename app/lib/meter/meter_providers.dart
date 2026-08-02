// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device/screen_awake.dart';
import '../nostr/relay_pool_provider.dart';
import '../profile/tariff_survey_service.dart';
import 'meter_diagnostics_file.dart';
import 'meter_journal.dart';
import 'meter_run_store.dart';
import 'routing_client.dart';
import 'tariff_store.dart';

final tariffStoreProvider = Provider<TariffStore>(
  (ref) => SharedPreferencesTariffStore(SharedPreferences.getInstance),
);

final meterJournalStoreProvider = Provider<MeterJournalStore>(
  (ref) => SharedPreferencesMeterJournalStore(SharedPreferences.getInstance),
);

/// The run currently on the clock, so a killed app does not take a fare
/// with it. Cleared the moment a run is finished.
final meterRunStoreProvider = Provider<MeterRunStore>(
  (ref) => SharedPreferencesMeterRunStore(SharedPreferences.getInstance),
);

/// Rows for the GPS diagnostic, kept on disk so they survive the app being
/// killed — which is one of the things being diagnosed.
///
/// `getApplicationDocumentsDirectory` rather than a cache directory: a cache
/// is what the OS deletes first when storage runs low, and the one moment a
/// driver reaches for this file is after something went wrong.
final meterDiagnosticSinkProvider = Provider<MeterDiagnosticSink>(
  (ref) => FileMeterDiagnosticSink(getApplicationDocumentsDirectory),
);

/// Holds the display on for as long as a run is on the clock.
///
/// A provider rather than a direct call so widget tests get
/// [NoopScreenAwake] by default — `wakelock_plus` is a platform channel and
/// would throw in `flutter test`, and a screen that crashed because it asked
/// to stay lit would be a worse bug than the dark screen it was fixing.
final screenAwakeProvider = Provider<ScreenAwake>(
  (ref) => const WakelockScreenAwake(),
);

/// What other drivers on this network charge. Driver-facing only — see
/// `tariff_survey.dart` for why the same figure must never reach a
/// passenger's screen.
final tariffSurveyServiceProvider = Provider<TariffSurveyService>(
  (ref) => TariffSurveyService(ref.watch(relayPoolProvider)),
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
