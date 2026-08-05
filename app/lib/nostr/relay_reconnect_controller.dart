// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'reconnect_backoff.dart';
import 'relay_pool.dart';

/// Redials dropped relays on its own, so a driver whose connection blips
/// while their phone is in a pocket does not silently stop receiving ride
/// offers until they happen to reopen the app.
///
/// Takhi's realtime is the relay connection and nothing else, so this is the
/// difference between a dropped socket being a two-second gap and being the
/// rest of a shift offline. The manual reconnect already existed
/// (`reconnectRelays`, driven by a button); this is the same action fired on
/// a schedule whenever the pool reports relays down.
///
/// Feed it every [RelayStatus] the pool emits via [onStatus]. It owns a
/// single timer:
///
///  * **All relays reachable** — cancels any pending retry and resets the
///    backoff. A blip that healed on its own costs nothing and does not make
///    the next real outage wait longer.
///  * **Any relay down** — schedules [onReconnect] after
///    [ReconnectBackoff.delayFor] the current attempt, then re-arms for the
///    attempt after that. A retry that reconnects everything produces an
///    all-reachable status, which cancels the re-armed timer through the
///    first branch; a retry that does not simply lets the next, longer wait
///    run — the exponential back-off the operators need.
///
/// No clock of its own beyond `Timer`, so it is fully testable with
/// `fake_async`: the untestable-on-a-device part (the socket) stays in
/// `WsRelaySocket`, and the *policy* — when to retry, how long to wait — is
/// exercised here without a network.
class RelayReconnectController {
  final ReconnectBackoff backoff;

  /// Fired to redial the down relays. In the app this invalidates
  /// `relayConnectionProvider`, which re-runs `RelayPool.connectAll` and
  /// dials only the relays that are actually down.
  final void Function() onReconnect;

  int _attempt = 0;
  Timer? _timer;
  bool _disposed = false;

  RelayReconnectController({
    required this.onReconnect,
    this.backoff = const ReconnectBackoff(),
  });

  /// The current retry attempt count. Zero while everything is reachable.
  int get attempt => _attempt;

  /// Whether a retry is currently scheduled.
  bool get isRetryScheduled => _timer != null;

  void onStatus(RelayStatus status) {
    if (_disposed) return;
    if (status.unreachableUrls.isEmpty) {
      _attempt = 0;
      _timer?.cancel();
      _timer = null;
      return;
    }
    // Already waiting on a retry: let it run rather than restarting the
    // clock every time a still-down status arrives, which would starve the
    // back-off and hammer the relays.
    if (_timer != null) return;
    _timer = Timer(backoff.delayFor(_attempt), _fire);
  }

  void _fire() {
    _timer = null;
    _attempt++;
    onReconnect();
    // Re-arm for the next, longer wait. If the reconnect just fixed things,
    // the resulting all-reachable status cancels this through [onStatus]
    // before it can fire.
    if (!_disposed) {
      _timer = Timer(backoff.delayFor(_attempt), _fire);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
