// SPDX-License-Identifier: AGPL-3.0-or-later
import '../geo/gps_fix.dart';
import '../geo/gps_track.dart';
import 'fare_calc.dart';

/// Accumulates GPS fixes for one taximeter run (spec §7.4 step 3: the big
/// live ₮/km/time display) and derives the running fare. `TaximeterPage`
/// (Task 8) owns the actual `LocationSource` subscription and calls
/// [addFix] as fixes arrive; this class has no I/O of its own.
class MeterSession {
  final int mntPerKm;
  final GpsTrackAccumulator _track = GpsTrackAccumulator();

  MeterSession({required this.mntPerKm});

  void addFix(GpsFix fix) => _track.addFix(fix);

  List<GpsFix> get fixes => _track.fixes;
  int get distanceMeters => _track.distanceMeters;
  int get durationSeconds => _track.durationSeconds;
  int get fareMnt =>
      computeFareMnt(mntPerKm: mntPerKm, distanceMeters: distanceMeters);
}
