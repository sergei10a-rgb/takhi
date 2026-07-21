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
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }

  @override
  Future<void> get ready => Future<void>.value();

  /// Delivers a raw relay frame (already JSON-encoded) to every listener,
  /// as if it arrived over the wire.
  void emit(String frame) => _controller.add(frame);
}
