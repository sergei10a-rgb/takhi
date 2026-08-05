// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The backoff decides how patiently the app redials a dead relay. Too eager
// and a thousand phones hammer a relay the second it reboots; too slow and a
// driver stops getting ride offers for no reason they can see. The schedule
// is a pure function of the attempt count, so both ends are pinned here.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/reconnect_backoff.dart';

void main() {
  const backoff = ReconnectBackoff(
    base: Duration(seconds: 2),
    max: Duration(seconds: 32),
    multiplier: 2,
  );

  test('the first retry waits the base delay', () {
    expect(backoff.delayFor(0), const Duration(seconds: 2));
  });

  test('a negative attempt is treated as the first', () {
    expect(backoff.delayFor(-1), const Duration(seconds: 2));
  });

  test('each attempt doubles the wait', () {
    expect(backoff.delayFor(1), const Duration(seconds: 4));
    expect(backoff.delayFor(2), const Duration(seconds: 8));
    expect(backoff.delayFor(3), const Duration(seconds: 16));
  });

  test('the wait is capped and never exceeds the ceiling', () {
    expect(backoff.delayFor(4), const Duration(seconds: 32));
    expect(backoff.delayFor(5), const Duration(seconds: 32));
  });

  test('a shift-long outage saturates at the ceiling, not infinity', () {
    expect(backoff.delayFor(100000), const Duration(seconds: 32));
  });

  test('the defaults are a sane schedule out of the box', () {
    const d = ReconnectBackoff();
    expect(d.delayFor(0), const Duration(seconds: 2));
    expect(d.delayFor(100), const Duration(seconds: 32));
  });
}
