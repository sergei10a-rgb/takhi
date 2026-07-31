// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:takhi/nostr/relay_pool.dart';

/// Shared no-network [RelaySocket] test double, reused by every Plan 3
/// service test that drives a [RelayPool] through `connect:`. Mirrors the
/// fake originally written inline in `relay_pool_test.dart` (Plan 2) --
/// pulled out here so Plan 3's several new relay-backed services don't
/// each hand-roll their own copy (DRY).
class FakeRelaySocket implements RelaySocket {
  final _controller = StreamController<String>.broadcast();
  final _done = Completer<void>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_done.isCompleted) _done.complete();
    await _controller.close();
  }

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Future<void> get done => _done.future;

  /// The connection dying under the app -- the network going away, or the
  /// relay hanging up. [RelayPool] stops counting the relay as connected.
  void dropFromTheOtherEnd() {
    if (!_done.isCompleted) _done.complete();
  }

  /// Delivers a raw relay frame (already JSON-encoded) to every listener,
  /// as if it arrived over the wire.
  void emit(String frame) => _controller.add(frame);
}

/// A relay that never comes up: DNS failure, connection refused, TLS
/// failure, aeroplane mode -- [RelayPool] treats them all alike, and so does
/// every screen, so one double covers the lot.
///
/// Pair it with [FakeRelaySocket] to stage a partly-reachable network, or use
/// it alone for the case that matters most: Тахь has no server, so with every
/// relay unreachable a published ride request goes nowhere at all.
class UnreachableRelaySocket implements RelaySocket {
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void send(String data) {}

  @override
  Future<void> close() async => _controller.close();

  @override
  Future<void> get ready => Future<void>.error(Exception('unreachable'));

  @override
  Future<void> get done => Completer<void>().future;
}
