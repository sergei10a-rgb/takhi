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

  /// The notice every [watch] call asked for, in order.
  ///
  /// Recorded rather than ignored because passing one is the *only* thing
  /// that turns the location stream into an Android foreground service, and
  /// a screen that forgets to ask has no visible symptom in a test — the
  /// fixes still arrive, because a fake has no operating system to be
  /// throttled by. It goes wrong only on a real phone, in a driver's hand,
  /// as a fare that came out too small. So it is asserted here instead.
  final List<LocationBackgroundNotice?> requestedNotices = [];

  /// Whether any subscription asked to keep running off screen.
  bool get requestedBackgroundDelivery =>
      requestedNotices.any((notice) => notice != null);

  @override
  Stream<GpsFix> watch({
    Duration interval = const Duration(seconds: 5),
    LocationBackgroundNotice? backgroundNotice,
  }) {
    requestedNotices.add(backgroundNotice);
    return _controller.stream;
  }

  void emit(GpsFix fix) => _controller.add(fix);

  Future<void> dispose() => _controller.close();
}
