// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nostr/relay_pool_provider.dart';
import 'driver_inbox_service.dart';
import 'handoff_service.dart';
import 'live_location_channel.dart';
import 'offer_service.dart';
import 'ride_dm_channel.dart';
import 'ride_request_service.dart';
import 'trip_receipt_repository.dart';
import 'trip_status_service.dart';
import 'trusted_drivers_store.dart';

/// The drivers this passenger has personally vouched for.
///
/// Feeds `computeReputation`'s `viewerTrusted`, which had no input until
/// this existed — see `trusted_drivers_store.dart`.
final trustedDriversStoreProvider = Provider<TrustedDriversStore>(
  (ref) => SharedPreferencesTrustedDriversStore(SharedPreferences.getInstance),
);

/// The set itself, loaded once and reused.
final trustedDriversProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(trustedDriversStoreProvider).load(),
);

final rideDmChannelProvider = Provider<RideDmChannel>(
  (ref) => RideDmChannel(ref.watch(relayPoolProvider)),
);

final rideRequestServiceProvider = Provider<RideRequestService>(
  (ref) => RideRequestService(
    ref.watch(relayPoolProvider),
    ref.watch(rideDmChannelProvider),
  ),
);

final driverInboxServiceProvider = Provider<DriverInboxService>(
  (ref) => DriverInboxService(ref.watch(relayPoolProvider)),
);

final offerServiceProvider = Provider<OfferService>(
  (ref) => OfferService(ref.watch(rideDmChannelProvider)),
);

final handoffServiceProvider = Provider<HandoffService>(
  (ref) => HandoffService(ref.watch(rideDmChannelProvider)),
);

final tripReceiptRepositoryProvider = Provider<TripReceiptRepository>(
  (ref) => TripReceiptRepository(ref.watch(relayPoolProvider)),
);

final liveLocationChannelProvider = Provider<LiveLocationChannel>(
  (ref) => LiveLocationChannel(ref.watch(relayPoolProvider)),
);

final tripStatusServiceProvider = Provider<TripStatusService>(
  (ref) => TripStatusService(ref.watch(rideDmChannelProvider)),
);
