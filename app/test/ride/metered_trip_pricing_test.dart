// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/geo/gps_fix.dart';
import 'package:takhi/geo/gps_track.dart';
import 'package:takhi/meter/fare_calc.dart';
import 'package:takhi/meter/meter_session.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

/// Headless (no widgets) coverage of the §7.2 GPS-taximeter pricing
/// pipeline `ActiveTripView` composes at runtime: a GPS track -> a fare
/// computed from the driver's own tariff -> a pair of trip receipts (one
/// per side) that sign the *same* price for the *same* trip_id. Exercised
/// here as plain function calls, independent of `ActiveTripView`'s widget
/// state machine, so the arithmetic and receipt-pairing contract are
/// verified without pumping any widget tree.
void main() {
  test('the driver\'s own GPS track and km-tariff produce the fare that both '
      'sides end up signing', () {
    final track = GpsTrackAccumulator()
      ..addFix(const GpsFix(lat: 47.9186, lon: 106.9176, timestampSeconds: 0))
      ..addFix(
        const GpsFix(lat: 47.9200, lon: 106.9200, timestampSeconds: 300),
      );

    final fareMnt = computeFareMnt(
      mntPerKm: 1500,
      distanceMeters: track.distanceMeters,
    );

    expect(track.distanceMeters, greaterThan(0));
    expect(fareMnt, (1500 * track.distanceMeters / 1000).round());
  });

  test('a driver and passenger receipt built from the same metered fare pair '
      'via computeReputation (spec §9)', () {
    final driver = generateKeyPair(List<int>.filled(32, 41));
    final passenger = generateKeyPair(List<int>.filled(32, 42));
    const tripId = 'trip-metered-1';

    final track = GpsTrackAccumulator()
      ..addFix(const GpsFix(lat: 47.90, lon: 106.90, timestampSeconds: 0))
      ..addFix(const GpsFix(lat: 47.92, lon: 106.93, timestampSeconds: 600));
    final fareMnt = computeFareMnt(
      mntPerKm: 1200,
      distanceMeters: track.distanceMeters,
    );

    final driverReceipt = buildTripReceipt(
      pubkey: driver.publicHex,
      now: 1000,
      tripId: tripId,
      counterpartyPubkey: passenger.publicHex,
      role: 'driver',
      ratingStars: 5,
      distanceMeters: track.distanceMeters,
      durationSeconds: track.durationSeconds,
      priceMnt: fareMnt,
    );
    final passengerReceipt = buildTripReceipt(
      pubkey: passenger.publicHex,
      now: 1005,
      tripId: tripId,
      counterpartyPubkey: driver.publicHex,
      role: 'passenger',
      ratingStars: 5,
      // The passenger's own GPS measurement may differ slightly (spec
      // §7.2 "ил тод байдал") -- that is *why* distance is not asserted
      // equal here -- but the confirmed price must match exactly.
      distanceMeters: track.distanceMeters + 40,
      durationSeconds: track.durationSeconds,
      priceMnt: fareMnt,
    );

    final parsedDriver = parseTripReceipt(driverReceipt);
    final parsedPassenger = parseTripReceipt(passengerReceipt);
    expect(parsedDriver.priceMnt, parsedPassenger.priceMnt);

    final reputation = computeReputation(
      subjectPubkey: driver.publicHex,
      allReceipts: [parsedDriver, parsedPassenger],
    );
    expect(reputation.pairedTripCount, 1);
    expect(reputation.averageRating, 5.0);
  });

  test('a trip that sat in traffic bills the wait once, and both sides sign '
      'the same breakdown rather than each deriving their own', () {
    final driver = generateKeyPair(List<int>.filled(32, 43));
    final passenger = generateKeyPair(List<int>.filled(32, 44));
    const tripId = 'trip-metered-wait';

    // Five minutes of driving, then five parked at a light with the phone's
    // fixes drifting a couple of metres either way.
    final meter = MeterSession(mntPerKm: 1200, waitTariffMntPerMinute: 300)
      ..addFix(const GpsFix(lat: 47.90, lon: 106.90, timestampSeconds: 0))
      ..addFix(const GpsFix(lat: 47.92, lon: 106.93, timestampSeconds: 300))
      ..addFix(const GpsFix(lat: 47.920018, lon: 106.93, timestampSeconds: 450))
      ..addFix(const GpsFix(lat: 47.92, lon: 106.93, timestampSeconds: 600));

    expect(meter.waitingSeconds, 300);
    expect(meter.waitingFareMnt, 1500); // 300₮/мин × 5 мин
    expect(meter.fareMnt, meter.distanceFareMnt + meter.waitingFareMnt);

    // What the driver's side puts on the wire at `TripPhase.arrived`.
    final status = RideTripStatusPayload(
      tripId: tripId,
      phase: TripPhase.arrived,
      finalFareMnt: meter.fareMnt,
      finalWaitingFareMnt: meter.waitingFareMnt,
      finalWaitingSeconds: meter.waitingSeconds,
    );
    final received =
        RideDmPayload.decode(status.encode()) as RideTripStatusPayload;

    final driverReceipt = buildTripReceipt(
      pubkey: driver.publicHex,
      now: 1000,
      tripId: tripId,
      counterpartyPubkey: passenger.publicHex,
      role: 'driver',
      ratingStars: 5,
      distanceMeters: meter.distanceMeters,
      durationSeconds: meter.durationSeconds,
      priceMnt: meter.fareMnt,
      waitingSeconds: meter.waitingSeconds,
      waitingFareMnt: meter.waitingFareMnt,
    );
    // The passenger signs the numbers that arrived, not ones recomputed
    // from their own track — which measured the same stop a few seconds
    // differently, as two phones always will.
    final passengerReceipt = buildTripReceipt(
      pubkey: passenger.publicHex,
      now: 1005,
      tripId: tripId,
      counterpartyPubkey: driver.publicHex,
      role: 'passenger',
      ratingStars: 5,
      distanceMeters: meter.distanceMeters + 40,
      durationSeconds: meter.durationSeconds,
      priceMnt: received.finalFareMnt!,
      waitingSeconds: received.finalWaitingSeconds!,
      waitingFareMnt: received.finalWaitingFareMnt!,
    );

    final parsedDriver = parseTripReceipt(driverReceipt);
    final parsedPassenger = parseTripReceipt(passengerReceipt);
    expect(parsedPassenger.priceMnt, parsedDriver.priceMnt);
    expect(parsedPassenger.waitingSeconds, parsedDriver.waitingSeconds);
    expect(parsedPassenger.waitingFareMnt, parsedDriver.waitingFareMnt);
    expect(parsedPassenger.distanceFareMnt, parsedDriver.distanceFareMnt);
    expect(
      parsedDriver.distanceFareMnt + parsedDriver.waitingFareMnt,
      parsedDriver.priceMnt,
    );
  });
}
