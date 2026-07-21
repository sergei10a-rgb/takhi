// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nostr/relay_pool_provider.dart';
import 'driver_inbox_service.dart';
import 'handoff_service.dart';
import 'offer_service.dart';
import 'ride_dm_channel.dart';
import 'ride_request_service.dart';
import 'trip_receipt_repository.dart';

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
