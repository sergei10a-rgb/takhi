// SPDX-License-Identifier: AGPL-3.0-or-later

/// The driver-observed stage of an in-progress trip (spec §7.1 step 5:
/// "жолооч ирж байгаа→суусан→замд→хүрсэн"). Every transition is a driver
/// action (spec step 6: "Жолооч «Аялал дууслаа» дарна") — the passenger's
/// UI (Task 7) only ever displays whatever phase arrives via
/// [RideTripStatusPayload], it never sets one itself.
///
/// The spec's four Mongolian labels collapse to three enum values: "суусан"
/// (passenger boarded) and "замд" (en route to destination) merge into
/// [tripInProgress]. There is no driver action that distinguishes them —
/// the moment the driver marks the passenger boarded, the trip IS en
/// route; splitting them would add a state with no transition of its own
/// (YAGNI), and both share one display treatment (live map, "аяллын
/// явцад") regardless.
enum TripPhase {
  /// Initial phase, entered automatically the moment the active-trip view
  /// opens after handoff — the driver is navigating to the passenger's
  /// exact pickup point.
  enRouteToPickup,

  /// The passenger has boarded (driver tapped "Зорчигч сууллаа") and the
  /// trip is now underway toward the destination.
  tripInProgress,

  /// The driver tapped "Аялал дууслаа" — distance/duration tracking stops
  /// on both sides and both move to the rating + receipt step.
  arrived,
}
