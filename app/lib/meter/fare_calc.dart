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
}) => (mntPerMinute * waitingSeconds / Duration.secondsPerMinute).round();

/// The whole metered fare: distance plus waiting.
///
/// Deliberately the sum of the two *already-rounded* parts, not one rounding
/// of the exact total. The finished screen and the trip receipt both show
/// the two rows, and a passenger who adds them up must get the number they
/// are being asked to pay — a one-төгрөг discrepancy between the rows and
/// the total is small in money and large in trust.
int computeTotalFareMnt({
  required int mntPerKm,
  required int distanceMeters,
  required int mntPerMinute,
  required int waitingSeconds,
}) =>
    computeFareMnt(mntPerKm: mntPerKm, distanceMeters: distanceMeters) +
    computeWaitingFareMnt(
      mntPerMinute: mntPerMinute,
      waitingSeconds: waitingSeconds,
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
