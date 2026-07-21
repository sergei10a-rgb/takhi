// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/ride_dm_payload.dart';
import 'package:takhi/ride/trip_phase.dart';

void main() {
  test('offer payload round-trips through encode/decode', () {
    const offer = RideOfferPayload(
      rideRequestId: 'req1',
      priceMnt: 5000,
      etaMinutes: 4,
      vehicleDescription: 'цагаан Prius, 1234УНА',
    );
    final decoded = RideDmPayload.decode(offer.encode()) as RideOfferPayload;
    expect(decoded.rideRequestId, 'req1');
    expect(decoded.priceMnt, 5000);
    expect(decoded.etaMinutes, 4);
    expect(decoded.vehicleDescription, 'цагаан Prius, 1234УНА');
  });

  test('handoff payload round-trips through encode/decode', () {
    const handoff = RideHandoffPayload(
      rideRequestId: 'req1',
      tripId: 'trip-abc',
      lat: 47.9186,
      lon: 106.9176,
      plusCode: '8Q7XJP2Q+2Q',
      landmarkText: 'Сүхбаатарын талбайн урд, цагаан хаалга',
    );
    final decoded =
        RideDmPayload.decode(handoff.encode()) as RideHandoffPayload;
    expect(decoded.rideRequestId, 'req1');
    expect(decoded.tripId, 'trip-abc');
    expect(decoded.lat, 47.9186);
    expect(decoded.lon, 106.9176);
    expect(decoded.plusCode, '8Q7XJP2Q+2Q');
    expect(decoded.landmarkText, 'Сүхбаатарын талбайн урд, цагаан хаалга');
  });

  test('cancel payload round-trips and defaults reason to empty', () {
    const cancel = RideCancelPayload(rideRequestId: 'req1');
    final decoded = RideDmPayload.decode(cancel.encode()) as RideCancelPayload;
    expect(decoded.rideRequestId, 'req1');
    expect(decoded.reason, '');
  });

  test('decode throws FormatException for an unrecognized type', () {
    expect(
      () => RideDmPayload.decode('{"type":"mystery"}'),
      throwsFormatException,
    );
  });

  test('decode throws FormatException for malformed JSON', () {
    expect(() => RideDmPayload.decode('not json'), throwsFormatException);
  });

  test('decode throws FormatException when JSON is not an object', () {
    expect(() => RideDmPayload.decode('42'), throwsFormatException);
  });

  test('decode throws FormatException when JSON is a bare array', () {
    expect(() => RideDmPayload.decode('[1,2,3]'), throwsFormatException);
  });

  test('offer decode throws FormatException when priceMnt is wrong-typed', () {
    expect(
      () => RideDmPayload.decode(
        jsonEncode({
          'type': 'offer',
          'rideRequestId': 'req1',
          'priceMnt': '5000',
          'etaMinutes': 4,
          'vehicleDescription': 'Prius',
        }),
      ),
      throwsFormatException,
    );
  });

  test(
    'offer decode throws FormatException when a required field is missing',
    () {
      expect(
        () => RideDmPayload.decode(
          jsonEncode({
            'type': 'offer',
            'rideRequestId': 'req1',
            'etaMinutes': 4,
            'vehicleDescription': 'Prius',
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test('offer decode throws FormatException when rideRequestId is '
      'wrong-typed', () {
    expect(
      () => RideDmPayload.decode(
        jsonEncode({
          'type': 'offer',
          'rideRequestId': 42,
          'priceMnt': 5000,
          'etaMinutes': 4,
          'vehicleDescription': 'Prius',
        }),
      ),
      throwsFormatException,
    );
  });

  test('handoff decode throws FormatException when lat is wrong-typed', () {
    expect(
      () => RideDmPayload.decode(
        jsonEncode({
          'type': 'handoff',
          'rideRequestId': 'req1',
          'tripId': 'trip-abc',
          'lat': 'not-a-number',
          'lon': 106.9176,
          'plusCode': '8Q7XJP2Q+2Q',
          'landmarkText': 'landmark',
        }),
      ),
      throwsFormatException,
    );
  });

  test('handoff decode accepts an integer lat/lon as a number', () {
    final decoded =
        RideDmPayload.decode(
              jsonEncode({
                'type': 'handoff',
                'rideRequestId': 'req1',
                'tripId': 'trip-abc',
                'lat': 48,
                'lon': 107,
                'plusCode': '8Q7XJP2Q+2Q',
                'landmarkText': 'landmark',
              }),
            )
            as RideHandoffPayload;
    expect(decoded.lat, 48.0);
    expect(decoded.lon, 107.0);
  });

  test('handoff decode throws FormatException when a required field is '
      'missing', () {
    expect(
      () => RideDmPayload.decode(
        jsonEncode({
          'type': 'handoff',
          'rideRequestId': 'req1',
          'lat': 47.9186,
          'lon': 106.9176,
          'plusCode': '8Q7XJP2Q+2Q',
          'landmarkText': 'landmark',
        }),
      ),
      throwsFormatException,
    );
  });

  test('cancel decode throws FormatException when reason is wrong-typed', () {
    expect(
      () => RideDmPayload.decode(
        jsonEncode({'type': 'cancel', 'rideRequestId': 'req1', 'reason': 42}),
      ),
      throwsFormatException,
    );
  });

  test(
    'cancel decode throws FormatException when rideRequestId is missing',
    () {
      expect(
        () => RideDmPayload.decode(jsonEncode({'type': 'cancel'})),
        throwsFormatException,
      );
    },
  );

  test('trip_status payload round-trips through encode/decode', () {
    const status = RideTripStatusPayload(
      tripId: 'trip-abc',
      phase: TripPhase.tripInProgress,
    );
    final decoded =
        RideDmPayload.decode(status.encode()) as RideTripStatusPayload;
    expect(decoded.tripId, 'trip-abc');
    expect(decoded.phase, TripPhase.tripInProgress);
  });

  test('trip_status decode throws FormatException for an unknown phase '
      'string', () {
    expect(
      () => RideDmPayload.decode(
        jsonEncode({
          'type': 'trip_status',
          'tripId': 'trip-abc',
          'phase': 'flying',
        }),
      ),
      throwsFormatException,
    );
  });
}
