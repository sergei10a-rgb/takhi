// SPDX-License-Identifier: AGPL-3.0-or-later

/// The short, preset coordination messages a driver and passenger send each
/// other with one tap while they are finding one another at the kerb.
///
/// Presets, not free text, and deliberately so: at pickup the driver is
/// parked in moving traffic and the passenger is scanning the street, and
/// neither has a spare hand or a spare moment to type. Four fixed phrases —
/// two from each side — cover the whole of what actually needs saying in that
/// minute ("I'm coming", "I'm here"), and ride the same NIP-17 gift-wrap as
/// every other ride DM, so no server ever sees who told whom to come out.
enum CannedMessage {
  /// Driver → passenger: on my way to you.
  driverOnMyWay,

  /// Driver → passenger: I have reached the pickup, waiting.
  driverArrived,

  /// Passenger → driver: coming out to you now.
  passengerComingOut,

  /// Passenger → driver: one moment, I will be right there.
  passengerOneMoment;

  /// The wire token — an explicit switch rather than [name], so renaming a
  /// value here can never silently change what travels on the wire. The same
  /// rule `TripRole.wireValue` and `RideCancelReason.wireValue` already keep.
  String get wireValue => switch (this) {
    CannedMessage.driverOnMyWay => 'driver_on_my_way',
    CannedMessage.driverArrived => 'driver_arrived',
    CannedMessage.passengerComingOut => 'passenger_coming_out',
    CannedMessage.passengerOneMoment => 'passenger_one_moment',
  };

  /// Whether the driver is the one who sends this (the passenger sends the
  /// other two). Decides which pair of buttons each side is shown, so a
  /// passenger is never offered "I have arrived" nor a driver "coming out".
  bool get isFromDriver =>
      this == CannedMessage.driverOnMyWay ||
      this == CannedMessage.driverArrived;

  /// Decodes a wire token, **throwing** on an unrecognized one.
  ///
  /// The opposite contract to `RideCancelReason.fromWire`, and for the
  /// opposite reason. A cancel has to tear the screen down whatever reason
  /// rode with it, so an unknown reason must still yield a value. A canned
  /// message only ever paints a banner; a preset a newer client added and
  /// this one does not know is better shown as nothing than as a guess — so
  /// it throws, and the inbox drops that one message whole (its per-wrap
  /// `try`/`catch`) without disturbing the trip around it.
  static CannedMessage fromWire(String value) => values.firstWhere(
    (m) => m.wireValue == value,
    orElse: () => throw FormatException('unknown canned message: $value'),
  );
}
