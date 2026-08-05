// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The auto-reconnect policy: when to redial dropped relays and how long to
// wait between tries. Takhi's realtime is the relay connection alone, so a
// controller that gives up too soon strands a driver offline and one that
// retries too eagerly hammers a relay that is down for maintenance. Both
// ends are pinned here, without a network, via fake_async.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/reconnect_backoff.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_reconnect_controller.dart';

const _urls = ['wss://a', 'wss://b'];

RelayStatus _status(Set<String> connected) =>
    RelayStatus(urls: _urls, connectedUrls: connected);

void main() {
  test('does nothing while every relay is reachable', () {
    fakeAsync((async) {
      var calls = 0;
      final c = RelayReconnectController(onReconnect: () => calls++);
      c.onStatus(_status({'wss://a', 'wss://b'}));
      expect(c.isRetryScheduled, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(calls, 0);
      c.dispose();
    });
  });

  test('schedules a retry after the base delay when a relay drops', () {
    fakeAsync((async) {
      var calls = 0;
      final c = RelayReconnectController(
        onReconnect: () => calls++,
        backoff: const ReconnectBackoff(base: Duration(seconds: 2)),
      );
      c.onStatus(_status({'wss://a'})); // b is down
      expect(c.isRetryScheduled, isTrue);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 0, reason: 'not yet — the base wait is 2s');
      async.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      c.dispose();
    });
  });

  test('backs off exponentially while the outage persists', () {
    fakeAsync((async) {
      var calls = 0;
      final c = RelayReconnectController(
        onReconnect: () => calls++,
        backoff: const ReconnectBackoff(
          base: Duration(seconds: 2),
          max: Duration(seconds: 32),
        ),
      );
      c.onStatus(_status({})); // fully offline
      async.elapse(const Duration(seconds: 2)); // attempt 0 → 2s
      expect(calls, 1);
      async.elapse(const Duration(seconds: 4)); // attempt 1 → 4s
      expect(calls, 2);
      async.elapse(const Duration(seconds: 8)); // attempt 2 → 8s
      expect(calls, 3);
      c.dispose();
    });
  });

  test('a still-down status does not restart the pending wait', () {
    fakeAsync((async) {
      var calls = 0;
      final c = RelayReconnectController(
        onReconnect: () => calls++,
        backoff: const ReconnectBackoff(base: Duration(seconds: 10)),
      );
      c.onStatus(_status({})); // down, schedules at 10s
      async.elapse(const Duration(seconds: 6));
      c.onStatus(_status({})); // still down 6s in — must not reset to 10s
      async.elapse(const Duration(seconds: 4)); // 10s total
      expect(calls, 1, reason: 'the original wait must fire on schedule');
      c.dispose();
    });
  });

  test('reconnecting everything cancels retries and resets the backoff', () {
    fakeAsync((async) {
      var calls = 0;
      final c = RelayReconnectController(
        onReconnect: () => calls++,
        backoff: const ReconnectBackoff(base: Duration(seconds: 2)),
      );
      c.onStatus(_status({})); // down
      async.elapse(const Duration(seconds: 2));
      expect(calls, 1);
      c.onStatus(_status({'wss://a', 'wss://b'})); // all back
      expect(c.isRetryScheduled, isFalse);
      expect(c.attempt, 0);
      async.elapse(const Duration(minutes: 5));
      expect(calls, 1, reason: 'no further retries once healthy');
      c.dispose();
    });
  });

  test('dispose stops all further retries', () {
    fakeAsync((async) {
      var calls = 0;
      final c = RelayReconnectController(
        onReconnect: () => calls++,
        backoff: const ReconnectBackoff(base: Duration(seconds: 2)),
      );
      c.onStatus(_status({}));
      c.dispose();
      async.elapse(const Duration(minutes: 5));
      expect(calls, 0);
    });
  });
}
