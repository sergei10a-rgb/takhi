// SPDX-License-Identifier: AGPL-3.0-or-later

// A 5 km/h "this counts as waiting" threshold used to live here. It was
// retired in v0.4.0: it was the second of two per-segment rules that each
// discarded a segment's distance for good when it failed, and together they
// cost a real driver 26% of one measured ride. `MeterSession` now decides
// travel-versus-waiting with a single test -- has the car measurably left
// the anchor -- which cannot lose metres, because a segment that does not
// clear the floor keeps its anchor and tries again on the next fix.

/// Metered fare for a completed (or in-progress) distance: tariff ×
/// distance (spec §7.4 step 3: "бодогдож буй ₮ = профайлын км-тариф ×
/// явсан зай"). Rounds to the nearest whole төгрөг.
int computeFareMnt({required int mntPerKm, required int distanceMeters}) =>
    (mntPerKm * billedKm(distanceMeters)).round();

/// The kilometre figure a fare is actually charged on: metres rounded to the
/// tenth of a kilometre the receipt prints.
///
/// This exists so the arithmetic on the receipt is arithmetic a passenger
/// can do. The line reads «5.2 км × 1 500 ₮/км», and before v0.4.0 the
/// answer beside it was 7 871₮ — because the display rounded 5.247 km to
/// one decimal while the fare kept every metre. Two numbers that do not
/// multiply to the third, printed at the exact moment somebody is being
/// asked to hand over money, is worse than printing no arithmetic at all:
/// it invites the check and then fails it.
///
/// The cost is a rounding of at most 50 metres, in whichever direction the
/// distance happens to fall — symmetric, so it favours neither side, and
/// smaller than the tenth of a kilometre a phone's GPS track can honestly
/// claim anyway. Every taximeter ever built has counted in increments.
double billedKm(int distanceMeters) =>
    double.parse((distanceMeters / 1000).toStringAsFixed(1));

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
/// **It does not overlap the waiting charge.** It used to, and the overlap
/// was documented here as intentional; the author withdrew that once it was
/// put to them in figures — two rates at 150₮ would charge 300₮ for a
/// minute in a jam, which is not what either label promises. Traffic is
/// part of the trip's duration and is paid for here; waiting is a phase the
/// driver enters when the passenger is keeping them, and `MeterSession`
/// runs exactly one of the two at a time.
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
