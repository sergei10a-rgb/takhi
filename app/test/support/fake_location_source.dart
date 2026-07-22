// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/location_source.dart';

/// Deterministic [LocationSource] test double — feeds pre-scripted fixes
/// via [emit] instead of a real GPS radio, mirroring [FakeRelaySocket]'s
/// role for [RelayPool]. `GeolocatorLocationSource` itself is intentionally
/// left without a dedicated unit test, for the same reason
/// `WsRelaySocket` (`nostr/relay_pool.dart`) has none: it is a thin,
/// untestable-without-a-real-device wrapper around a platform plugin —
/// everything built on top of the [LocationSource] interface is fully
/// covered through this fake instead.
class FakeLocationSource implements LocationSource {
  final _controller = StreamController<GpsFix>.broadcast();

  @override
  Stream<GpsFix> watch({Duration interval = const Duration(seconds: 5)}) =>
      _controller.stream;

  void emit(GpsFix fix) => _controller.add(fix);

  Future<void> dispose() => _controller.close();
}
