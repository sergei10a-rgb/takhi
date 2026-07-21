// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/ride/ride_dm_payload.dart';

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
    final decoded =
        RideDmPayload.decode(cancel.encode()) as RideCancelPayload;
    expect(decoded.rideRequestId, 'req1');
    expect(decoded.reason, '');
  });

  test('decode throws FormatException for an unrecognized type', () {
    expect(() => RideDmPayload.decode('{"type":"mystery"}'),
        throwsFormatException);
  });

  test('decode throws FormatException for malformed JSON', () {
    expect(() => RideDmPayload.decode('not json'), throwsFormatException);
  });
}
