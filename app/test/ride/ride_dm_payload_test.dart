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

  test('call_offer payload round-trips through encode/decode', () {
    const offer = CallOfferPayload(tripId: 'trip-1', sdp: 'v=0\r\n...');
    final decoded = RideDmPayload.decode(offer.encode()) as CallOfferPayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.sdp, 'v=0\r\n...');
  });

  test('call_answer payload round-trips through encode/decode', () {
    const answer = CallAnswerPayload(tripId: 'trip-1', sdp: 'v=0\r\n...ans');
    final decoded = RideDmPayload.decode(answer.encode()) as CallAnswerPayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.sdp, 'v=0\r\n...ans');
  });

  test('call_ice payload round-trips through encode/decode', () {
    const ice = CallIceCandidatePayload(
      tripId: 'trip-1',
      candidate: 'candidate:1 1 UDP 2122260223 10.0.0.1 54321 typ host',
      sdpMid: 'audio',
      sdpMLineIndex: 0,
    );
    final decoded =
        RideDmPayload.decode(ice.encode()) as CallIceCandidatePayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.candidate, ice.candidate);
    expect(decoded.sdpMid, 'audio');
    expect(decoded.sdpMLineIndex, 0);
  });

  test('call_hangup payload round-trips through encode/decode', () {
    const hangup = CallHangupPayload(tripId: 'trip-1', reason: 'no answer');
    final decoded = RideDmPayload.decode(hangup.encode()) as CallHangupPayload;
    expect(decoded.tripId, 'trip-1');
    expect(decoded.reason, 'no answer');
  });

  test('call_hangup payload defaults reason to empty string', () {
    const hangup = CallHangupPayload(tripId: 'trip-1');
    final decoded = RideDmPayload.decode(hangup.encode()) as CallHangupPayload;
    expect(decoded.reason, '');
  });

  test('handoff payload phone field round-trips when present', () {
    const handoff = RideHandoffPayload(
      rideRequestId: 'req1',
      tripId: 'trip-1',
      lat: 47.9,
      lon: 106.9,
      plusCode: 'ABC+123',
      landmarkText: 'цагаан хаалга',
      phone: '99112233',
    );
    final decoded =
        RideDmPayload.decode(handoff.encode()) as RideHandoffPayload;
    expect(decoded.phone, '99112233');
  });

  test('handoff payload phone field is null when omitted', () {
    const handoff = RideHandoffPayload(
      rideRequestId: 'req1',
      tripId: 'trip-1',
      lat: 47.9,
      lon: 106.9,
      plusCode: 'ABC+123',
      landmarkText: 'цагаан хаалга',
    );
    final decoded =
        RideDmPayload.decode(handoff.encode()) as RideHandoffPayload;
    expect(decoded.phone, isNull);
  });
}
