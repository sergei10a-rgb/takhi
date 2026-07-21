// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

/// The structured content carried inside a NIP-17 rumor for every private
/// ride message (spec §6: offer/agreement, handoff, and cancellation all
/// share the encrypted-DM channel; this is the JSON schema for that
/// channel's `content`). [encode] is what goes into `nip17Wrap`'s
/// `content:`; [RideDmPayload.decode] is what a rumor's content is parsed
/// back into after `nip17Unwrap`.
sealed class RideDmPayload {
  const RideDmPayload();

  String encode() => jsonEncode(toJson());
  Map<String, dynamic> toJson();

  /// Parses a rumor's `content` back into a typed payload. Throws
  /// [FormatException] for malformed JSON or an unrecognized `type`.
  static RideDmPayload decode(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return switch (map['type']) {
      'offer' => RideOfferPayload._fromJson(map),
      'handoff' => RideHandoffPayload._fromJson(map),
      'cancel' => RideCancelPayload._fromJson(map),
      final other => throw FormatException(
          'unknown ride DM payload type: $other'),
    };
  }
}

/// A driver's offer on a ride request: proposed price, ETA, and a short
/// vehicle description (spec §6 "Санал / тохиролцоо", §7.1 step 3).
/// [rideRequestId] correlates the offer back to the `NostrEvent.id` of the
/// public kind-20177 request it answers -- a field the spec's summary
/// table leaves implicit but the DM payload must carry explicitly.
final class RideOfferPayload extends RideDmPayload {
  final String rideRequestId;
  final int priceMnt;
  final int etaMinutes;
  final String vehicleDescription;

  const RideOfferPayload({
    required this.rideRequestId,
    required this.priceMnt,
    required this.etaMinutes,
    required this.vehicleDescription,
  });

  factory RideOfferPayload._fromJson(Map<String, dynamic> map) =>
      RideOfferPayload(
        rideRequestId: map['rideRequestId'] as String,
        priceMnt: map['priceMnt'] as int,
        etaMinutes: map['etaMinutes'] as int,
        vehicleDescription: map['vehicleDescription'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'offer',
        'rideRequestId': rideRequestId,
        'priceMnt': priceMnt,
        'etaMinutes': etaMinutes,
        'vehicleDescription': vehicleDescription,
      };
}

/// The passenger's exact pickup handoff to the driver they selected: only
/// ever sent to that one driver (spec §6 "Тохироо + яг байршил", §9
/// privacy tiering -- the exact point is never public).
final class RideHandoffPayload extends RideDmPayload {
  final String rideRequestId;
  final String tripId;
  final double lat;
  final double lon;
  final String plusCode;
  final String landmarkText;

  const RideHandoffPayload({
    required this.rideRequestId,
    required this.tripId,
    required this.lat,
    required this.lon,
    required this.plusCode,
    required this.landmarkText,
  });

  factory RideHandoffPayload._fromJson(Map<String, dynamic> map) =>
      RideHandoffPayload(
        rideRequestId: map['rideRequestId'] as String,
        tripId: map['tripId'] as String,
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
        plusCode: map['plusCode'] as String,
        landmarkText: map['landmarkText'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'handoff',
        'rideRequestId': rideRequestId,
        'tripId': tripId,
        'lat': lat,
        'lon': lon,
        'plusCode': plusCode,
        'landmarkText': landmarkText,
      };
}

/// Either side backing out before the trip starts (spec §7.5).
final class RideCancelPayload extends RideDmPayload {
  final String rideRequestId;
  final String reason;

  const RideCancelPayload({required this.rideRequestId, this.reason = ''});

  factory RideCancelPayload._fromJson(Map<String, dynamic> map) =>
      RideCancelPayload(
        rideRequestId: map['rideRequestId'] as String,
        reason: map['reason'] as String? ?? '',
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'cancel',
        'rideRequestId': rideRequestId,
        'reason': reason,
      };
}
