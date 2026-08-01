// SPDX-License-Identifier: AGPL-3.0-or-later

/// Below this speed the vehicle counts as *waiting*, not travelling, and the
/// meter switches from the km-tariff to the minute-tariff. Set well above
/// the couple of km/h a parked phone's GPS fixes drift at, and well below
/// anything a car does deliberately: at a red light in Ulaanbaatar traffic
/// the meter must land on the waiting side, not creep forward on jitter.
const double kWaitingSpeedThresholdKmh = 5.0;

/// Whether [speedKmh] puts the meter in its waiting mode. The threshold
/// itself counts as moving, so the two modes partition every speed exactly
/// once and this boundary is stated in one place rather than repeated as a
/// bare `<` at each call site.
bool isWaitingSpeed(double speedKmh) => speedKmh < kWaitingSpeedThresholdKmh;

/// Metered fare for a completed (or in-progress) distance: tariff ×
/// distance (spec §7.4 step 3: "бодогдож буй ₮ = профайлын км-тариф ×
/// явсан зай"). Rounds to the nearest whole төгрөг.
int computeFareMnt({required int mntPerKm, required int distanceMeters}) =>
    (mntPerKm * distanceMeters / 1000).round();

/// Metered fare for time spent stopped: tariff × minutes waited, rounded to
/// the nearest whole төгрөг.
///
/// Part-minutes are charged *proportionally, by the second* rather than
/// rounded up to whole started minutes. Started-minute billing is simpler to
/// explain but it makes the running total jump by a full minute's charge at
/// unpredictable moments — a passenger watching the screen sees the number
/// leap the instant a light turns red, and one extra second of waiting can
/// cost the same as fifty-nine. Charging by the second keeps the number
/// moving smoothly and keeps two passengers who waited nearly the same time
/// paying nearly the same amount.
int computeWaitingFareMnt({
  required int mntPerMinute,
  required int waitingSeconds,
}) => _timeFareMnt(mntPerMinute, waitingSeconds);

/// Metered fare for the whole time the trip lasted, moving or not.
///
/// The third, independent rate a driver may set (added 2026-08-01 at the
/// app author's request). Where [computeWaitingFareMnt] bills only the
/// seconds the car stood still, this bills every second from the first fix
/// to the last.
///
/// **It deliberately overlaps the waiting charge, and that is not a bug to
/// be fixed later.** A driver who fills in both the jam rate and the
/// duration rate charges stopped time twice, because the stopped seconds
/// are inside the trip's duration as well. The author was asked about this
/// directly and confirmed it: the three rates are independent, each does
/// exactly what its label says, and which of them to use is the driver's
/// commercial decision rather than something the app should second-guess.
/// So there is no validation forcing a combination, no warning about the
/// overlap, and no "moving time only" reinterpretation of this figure.
///
/// Every rate is optional. Zero — the default — means the component is
/// simply not charged, which is how every tariff saved before this existed
/// keeps behaving.
///
/// Prorated by the second for the same reason as the waiting fare: a total
/// that leaps by a whole minute's charge while the passenger is watching it
/// reads as the meter cheating, whatever the arithmetic.
int computeDurationFareMnt({
  required int mntPerMinute,
  required int durationSeconds,
}) => _timeFareMnt(mntPerMinute, durationSeconds);

/// Rate x minutes, with both halves floored at zero.
///
/// The clamp is the core's own guard, not a duplicate of the forms'. Both
/// rate boxes already refuse a negative (`TaximeterPage._parsePrice`,
/// `DriverProfilePage._parsePrice`), but a rate reaches this function from
/// places no text field guards: a profile cached by a version of the app
/// from before those parsers existed, and a kind-0 event published by any
/// other client on the network, which this app does not get to validate
/// before reading. A negative per-minute rate subtracts money for as long
/// as the trip lasts and can carry a whole fare below zero — a number that
/// is not a price and that no screen here is built to show.
///
/// Seconds are floored too. They should never arrive negative, but they are
/// derived from device clocks on both ends of a segment, and a fare is the
/// wrong place to find out that one of them stepped backwards.
int _timeFareMnt(int mntPerMinute, int seconds) {
  if (mntPerMinute <= 0 || seconds <= 0) return 0;
  return (mntPerMinute * seconds / Duration.secondsPerMinute).round();
}

/// The whole metered fare: distance, plus stopped time, plus trip duration.
///
/// Deliberately the sum of the *already-rounded* parts, not one rounding
/// of the exact total. The finished screen and the trip receipt both show
/// the rows, and a passenger who adds them up must get the number they
/// are being asked to pay — a one-төгрөг discrepancy between the rows and
/// the total is small in money and large in trust.
int computeTotalFareMnt({
  required int mntPerKm,
  required int distanceMeters,
  required int mntPerMinute,
  required int waitingSeconds,
  int durationMntPerMinute = 0,
  int durationSeconds = 0,
}) =>
    computeFareMnt(mntPerKm: mntPerKm, distanceMeters: distanceMeters) +
    computeWaitingFareMnt(
      mntPerMinute: mntPerMinute,
      waitingSeconds: waitingSeconds,
    ) +
    computeDurationFareMnt(
      mntPerMinute: durationMntPerMinute,
      durationSeconds: durationSeconds,
    );

/// The offline pre-trip estimate (spec §7.4 step 2): straight-line
/// distance inflated by [urbanFactor] (spec default 1.35 — a real street
/// grid is never a straight line) times the tariff. The caller is always
/// responsible for labeling this "ойролцоогоор" (approximate) — this
/// function only computes the number.
///
/// Deliberately distance-only: how long a trip will sit in traffic is
/// exactly what cannot be predicted before it starts, and quoting a
/// confident-looking waiting charge up front would make the estimate less
/// honest, not more.
int estimateFareMntOffline({
  required int mntPerKm,
  required double straightLineDistanceMeters,
  double urbanFactor = 1.35,
}) => (mntPerKm * straightLineDistanceMeters * urbanFactor / 1000).round();
