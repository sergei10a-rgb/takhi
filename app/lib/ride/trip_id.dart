// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:convert/convert.dart';

/// Generates a fresh trip id: 16 random bytes, hex-encoded. The passenger
/// mints this at handoff time (spec §6 "Тохироо + яг байршил", §9) and it
/// becomes the `d` tag both sides' eventual trip receipts (kind 30177,
/// Plan 4) share.
///
/// Pass [randomBytes16] for deterministic output in tests; otherwise
/// secure randomness is used, mirroring `generateKeyPair`'s pattern in
/// `takhi_protocol`.
String generateTripId([List<int>? randomBytes16]) {
  final bytes = randomBytes16 ?? _secureRandom16();
  if (bytes.length != 16) {
    throw ArgumentError('trip id seed must be 16 bytes');
  }
  return hex.encode(bytes);
}

List<int> _secureRandom16() {
  final r = math.Random.secure();
  return List<int>.generate(16, (_) => r.nextInt(256));
}
