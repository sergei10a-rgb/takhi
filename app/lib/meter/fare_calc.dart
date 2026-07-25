// SPDX-License-Identifier: AGPL-3.0-or-later

/// Metered fare for a completed (or in-progress) distance: tariff ×
/// distance (spec §7.4 step 3: "бодогдож буй ₮ = профайлын км-тариф ×
/// явсан зай"). Rounds to the nearest whole төгрөг.
int computeFareMnt({required int mntPerKm, required int distanceMeters}) =>
    (mntPerKm * distanceMeters / 1000).round();

/// The offline pre-trip estimate (spec §7.4 step 2): straight-line
/// distance inflated by [urbanFactor] (spec default 1.35 — a real street
/// grid is never a straight line) times the tariff. The caller is always
/// responsible for labeling this "ойролцоогоор" (approximate) — this
/// function only computes the number.
int estimateFareMntOffline({
  required int mntPerKm,
  required double straightLineDistanceMeters,
  double urbanFactor = 1.35,
}) => (mntPerKm * straightLineDistanceMeters * urbanFactor / 1000).round();
