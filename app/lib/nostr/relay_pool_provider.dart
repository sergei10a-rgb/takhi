// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'relay_pool.dart';
import 'relay_reconnect_controller.dart';

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
/// Connects [relayPoolProvider]'s pool to every configured relay. Widgets
/// that need the app "live" on the relay network — currently just
/// [HomePage] — watch this so [RelayPool.connectAll] actually runs once the
/// user reaches home.
///
/// Also the app's **reconnect**: `ref.invalidate(relayConnectionProvider)`
/// re-runs it, and [RelayPool.connectAll] only dials the relays that are
/// actually down, so a retry never disturbs a connection that is working.
/// While the retry is in flight this provider is loading again (with the
/// previous value retained), which is what lets the UI say "reconnecting…"
/// rather than flickering back to a blank state.
final relayConnectionProvider = FutureProvider<RelayPool>((ref) async {
  final pool = ref.watch(relayPoolProvider);
  await pool.connectAll();
  return pool;
});

/// The pool's live health: how many of the configured relays are reachable
/// right now, and which are not.
///
/// Separate from [relayConnectionProvider] because the two answer different
/// questions. That one is "is a connect attempt in flight?" and resolves
/// once, for good. This one keeps answering "can anything the app publishes
/// still reach a human?" — including the case nothing else would ever
/// prompt a rebuild for: the last relay dying, minutes later, while the
/// rider is looking at the screen.
final relayStatusProvider = StreamProvider<RelayStatus>(
  (ref) => ref.watch(relayPoolProvider).watchStatus(),
);

/// The pool's health, read fresh, rebuilding whenever it changes.
///
/// [relayStatusProvider] is watched purely as the *trigger* -- the value
/// itself comes straight off the pool. A [StreamProvider] has no value at
/// all until its stream has emitted, and any value it does hold is a
/// snapshot from whenever that happened; relay health is the one thing in
/// this app that must never be rendered from a stale or absent reading,
/// since "connected" shown while nothing is connected is precisely the bug
/// being fixed. Reading the pool directly cannot be stale by construction.
///
/// Shared by every surface that shows relay health so no two of them can
/// disagree about what "offline" means.
RelayStatus watchRelayStatus(WidgetRef ref) {
  ref.watch(relayStatusProvider);
  return ref.watch(relayPoolProvider).status;
}

/// Dials every relay that is currently down, leaving the working ones
/// untouched (see [RelayPool.connectAll]).
///
/// Re-running [relayConnectionProvider] rather than calling the pool
/// directly, so the "reconnecting…" state every surface renders comes from
/// one place -- the provider's own [AsyncValue] -- instead of each screen
/// keeping a bool it has to remember to clear.
void reconnectRelays(WidgetRef ref) => ref.invalidate(relayConnectionProvider);

/// Redials dropped relays on its own, on an exponential back-off, so a
/// connection that blips while the phone is pocketed does not leave a driver
/// silently offline until they reopen the app.
///
/// Kept alive by being watched wherever the app is meant to be live on the
/// network (the home status row). It listens to the pool's health and fires
/// the same reconnect the button does — [reconnectRelays]'s
/// `invalidate(relayConnectionProvider)` — whenever relays are down, resetting
/// the moment they are all back. The scheduling policy is
/// [RelayReconnectController], unit-tested without a network; its real-world
/// tuning is a field-test concern, like everything else that only a dropped
/// relay on a real phone can exercise.
final relayAutoReconnectProvider = Provider<RelayReconnectController>((ref) {
  final controller = RelayReconnectController(
    onReconnect: () => ref.invalidate(relayConnectionProvider),
  );
  final sub = ref
      .watch(relayPoolProvider)
      .watchStatus()
      .listen(controller.onStatus);
  ref.onDispose(() {
    sub.cancel();
    controller.dispose();
  });
  return controller;
});
