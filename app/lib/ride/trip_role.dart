// SPDX-License-Identifier: AGPL-3.0-or-later

/// Which side of a trip the local device is on.
enum TripRole {
  driver,
  passenger;

  /// The wire value `buildTripReceipt`'s `role` field and PROTOCOL.md §4.2
  /// expect — 'driver' or 'passenger'. Kept as an explicit mapping (rather
  /// than relying on `.name`, which happens to match today) so a future
  /// rename of the enum case can never silently change the wire value.
  String get wireValue => switch (this) {
    TripRole.driver => 'driver',
    TripRole.passenger => 'passenger',
  };
}
