// SPDX-License-Identifier: AGPL-3.0-or-later

/// Why a ride was called off (spec §7.5), as a small closed set both sides
/// understand — distinct from the free-text `reason` that has always ridden
/// alongside it.
///
/// It is informational, not punitive: Тахь takes no fee, keeps no wallet and
/// has no dispatcher to arbitrate, so a reason can never fine anyone or move
/// money. Its whole worth is that the other side reads *why* rather than a
/// bare "cancelled", and that a no-show is a nameable thing rather than a
/// silent disappearance.
enum RideCancelReason {
  /// Absent, wrong-typed, or a value a newer client sent that this build does
  /// not know. Never written to the wire (it is omitted, exactly as an old
  /// client omits the field), so it doubles as the safe target every
  /// unrecognised code drops to — a cancel from a hostile or newer peer must
  /// still tear the ride down, never throw.
  unknown,

  /// The rider no longer needs the ride. The honest default, and what the
  /// passenger's picker starts on.
  passengerChangedMind,

  /// The rider is not willing to wait for how far the driver is. The one
  /// rider reason a driver most benefits from seeing.
  driverTooFar,

  /// The driver waited and the passenger never appeared. Sent only by the
  /// driver, as a fixed value — the driver has no picker, so this code *is*
  /// the «Зорчигч ирсэнгүй» button.
  passengerNoShow,

  /// Something outside the named set. Keeps the picker short and the
  /// free-text `reason` meaningful rather than forcing a mis-categorisation.
  other;

  /// The token this reason travels as. An explicit mapping rather than
  /// `.name` — mirroring [TripRole.wireValue] — so renaming an enum case can
  /// never silently change the wire and strand every deployed client on the
  /// old spelling.
  String get wireValue => switch (this) {
    RideCancelReason.unknown => 'unknown',
    RideCancelReason.passengerChangedMind => 'passenger_changed_mind',
    RideCancelReason.driverTooFar => 'driver_too_far',
    RideCancelReason.passengerNoShow => 'passenger_no_show',
    RideCancelReason.other => 'other',
  };

  /// The reason a wire token names, or [unknown] for anything unrecognised —
  /// an absent field, a value from a future build, or outright garbage. Never
  /// throws: the drop-to-fallback contract that keeps a cancel decodable no
  /// matter who sent it (explicitly unlike the trip-phase decode, where an
  /// unknown value is a protocol error worth refusing).
  static RideCancelReason fromWire(String value) => RideCancelReason.values
      .firstWhere((r) => r.wireValue == value, orElse: () => unknown);
}
