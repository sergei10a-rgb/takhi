// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'relay_pool.dart';

/// Public Nostr relays Тахь talks to by default. User-editable relay lists
/// are a later concern (Plan 2 settings) — for now every install connects
/// to the same well-known public set so passengers and drivers can
/// actually find each other's events (Plan 2 §5).
const defaultRelayUrls = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://relay.nostr.band',
];

/// The app-wide [RelayPool]. A plain [Provider] (not a [FutureProvider]) so
/// the pool object itself exists immediately and can be overridden in tests
/// with a fake-socket-backed pool; connecting is a separate, awaitable step
/// — see [relayConnectionProvider].
final relayPoolProvider = Provider<RelayPool>((ref) {
  final pool = RelayPool(defaultRelayUrls);
  ref.onDispose(pool.dispose);
  return pool;
});

/// Connects [relayPoolProvider]'s pool to every configured relay. Widgets
/// that need the app "live" on the relay network — currently just
/// [HomePage] — watch this so [RelayPool.connectAll] actually runs once the
/// user reaches home, and so the UI can render a connecting/connected
/// indicator from its [AsyncValue].
final relayConnectionProvider = FutureProvider<RelayPool>((ref) async {
  final pool = ref.watch(relayPoolProvider);
  await pool.connectAll();
  return pool;
});
