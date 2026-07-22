// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_source.dart';

/// The app-wide [LocationSource]. Overridden with a `FakeLocationSource` in
/// every widget test that needs GPS (Task 7/8) — mirrors
/// `relayPoolProvider`'s override pattern exactly.
final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);

/// Wraps [ensureLocationPermission] behind a provider, mirroring
/// [locationSourceProvider]'s override pattern. [ensureLocationPermission]
/// itself calls `package:geolocator` static methods directly, which hit a
/// real platform channel and throw `MissingPluginException` under
/// `flutter_test` with no plugin registered -- widget tests (Task 7/8)
/// override this provider with a fake `() async => true`/`false` instead of
/// mocking geolocator's channel, keeping every GPS-facing behavior testable
/// per the Global Constraints without a real device.
final locationPermissionCheckProvider = Provider<Future<bool> Function()>(
  (ref) => ensureLocationPermission,
);
