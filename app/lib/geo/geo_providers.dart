// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_source.dart';

/// The app-wide [LocationSource]. Overridden with a `FakeLocationSource` in
/// every widget test that needs GPS (Task 7/8) — mirrors
/// `relayPoolProvider`'s override pattern exactly.
final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);
