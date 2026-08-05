// SPDX-License-Identifier: AGPL-3.0-or-later

/// The waiting schedule between automatic attempts to redial a relay that
/// has gone down.
///
/// Takhi's realtime is a relay connection and nothing else — no company
/// socket, no push fallback — so a dead relay that is never retried is a
/// driver who silently stops receiving ride offers. The reconnect itself
/// already exists (`reconnectRelays`, `relay_pool_provider.dart`); what was
/// missing is *when* to fire it on its own, without either giving up too
/// soon or hammering a relay that is down for maintenance.
///
/// Exponential, because the two failure modes want opposite things: a
/// blip wants an immediate retry, and an outage wants the app to back off
/// so a thousand phones do not all redial the same second it comes back up
/// (the "thundering herd" every relay operator fears). Doubling from a short
/// base to a capped ceiling serves both — quick at first, then patient.
///
/// Pure and deterministic: the delay is a function of the attempt count and
/// nothing else, so the schedule is testable without a clock or a socket,
/// which is exactly the property the untestable-on-a-device parts of the
/// relay layer (`WsRelaySocket`) do not have. Jitter, when it is added, will
/// be a separate wrapper taking an injected source of randomness, so this
/// core stays reproducible.
class ReconnectBackoff {
  /// The wait before the very first retry.
  final Duration base;

  /// The ceiling the delay never exceeds however long an outage lasts.
  final Duration max;

  /// How much longer each successive wait is than the one before it.
  final double multiplier;

  const ReconnectBackoff({
    this.base = const Duration(seconds: 2),
    this.max = const Duration(seconds: 32),
    this.multiplier = 2.0,
  }) : assert(multiplier >= 1, 'a backoff that shrinks is not a backoff');

  /// The delay before retry number [attempt] (0 for the first): [base]
  /// multiplied by [multiplier] to the power of [attempt], capped at [max].
  ///
  /// A negative or zero [attempt] is the first retry and waits [base].
  /// Computed by repeated multiplication rather than `pow` so a large
  /// attempt count saturates at [max] instead of overflowing to infinity —
  /// a shift that has run for an hour must still ask for a finite wait.
  Duration delayFor(int attempt) {
    if (attempt <= 0) return base;
    final capMs = max.inMilliseconds;
    var ms = base.inMilliseconds.toDouble();
    for (var i = 0; i < attempt; i++) {
      ms *= multiplier;
      if (ms >= capMs) return max;
    }
    return Duration(milliseconds: ms.round());
  }
}
