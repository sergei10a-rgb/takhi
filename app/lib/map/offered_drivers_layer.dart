// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../ride/offer_ranking.dart';
import '../theme/takhi_theme.dart';

/// Draws a car for every driver who has offered on this request, so the
/// passenger can choose one off the map rather than off a list of
/// strangers' names.
///
/// The mirror image of `NearbyRequestsLayer`, which draws waiting
/// passengers for a driver -- and it exists on the same terms. Each car is
/// plotted at the CENTRE of the geohash-7 cell the offer carried
/// (`RideOfferPayload.driverGeohash`, ~±76m), never at a coordinate,
/// because a coordinate is not something this layer is ever given.
///
/// **Only drivers who have already offered appear here.** Showing every
/// free driver in the city was considered for this feature and refused:
/// it would require drivers to broadcast their position publicly, and
/// their kind-0 profile already carries the car, the colour and the plate,
/// so the combination would let anyone follow a named, plated vehicle all
/// day and work out where its driver sleeps. A driver who has answered
/// this one request has chosen to reveal themselves to this one passenger,
/// inside a gift wrap nobody else can read.
///
/// An offer whose `driverGeohash` is absent -- an older client, or a phone
/// whose first GPS fix has not landed -- simply draws no car. It is still
/// in the list underneath and still choosable; a driver must never drop
/// out of the running because their GPS was slow.
/// The tappable square around each car.
///
/// Comfortably over the 44dp touch floor even when the disc inside is at
/// its smaller size: these sit on a draggable map, where a marker the size
/// of its own glyph is a target the passenger stabs at while the map is
/// still sliding under their finger.
const _kCarHitSize = 48.0;

/// The disc itself, unselected and selected.
///
/// The selected car grows rather than only changing colour: colour alone
/// is the one difference a passenger with a colour-vision deficiency may
/// not see, and this is the control that decides who drives them.
const _kCarDisc = 32.0;
const _kCarDiscSelected = 40.0;
const _kCarGlyph = 18.0;
const _kCarGlyphSelected = 22.0;

/// An unselected car only needs an edge so it does not dissolve into a
/// pale map tile; the selected one is ringed at the weight the app uses
/// for any "this one" indicator ([TakhiStroke.indicator]).
const _kCarEdge = 1.0;

class OfferedDriversLayer extends StatelessWidget {
  final List<RankedRideOffer> offers;

  /// Which driver's card is open, by pubkey, or `null` when none is.
  /// The matching car is drawn larger and in the accent colour so the two
  /// halves of the screen agree about what is selected.
  final String? highlightedDriverPubkey;

  final ValueChanged<RankedRideOffer> onTap;

  const OfferedDriversLayer({
    super.key,
    required this.offers,
    required this.onTap,
    this.highlightedDriverPubkey,
  });

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    for (final ranked in offers) {
      final cell = ranked.offer.payload.driverGeohash;
      if (cell == null || cell.isEmpty) continue;
      final centre = geohashDecodeCenter(cell);
      final selected =
          highlightedDriverPubkey != null &&
          highlightedDriverPubkey == ranked.offer.driverPubkey;
      markers.add(
        Marker(
          point: ll.LatLng(centre.lat, centre.lon),
          width: _kCarHitSize,
          height: _kCarHitSize,
          child: _CarMarker(selected: selected, onTap: () => onTap(ranked)),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }
}

/// One car on the map.
///
/// A filled disc behind the glyph rather than a bare icon: these are drawn
/// over map tiles whose colour this app does not control, and a plain dark
/// icon disappears over a dark block of buildings.
class _CarMarker extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _CarMarker({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final fill = selected ? TakhiColors.gold : surfaces.sheet;
    final ink = selected ? TakhiColors.ink : surfaces.onSheet;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: TakhiMotion.fast,
          width: selected ? _kCarDiscSelected : _kCarDisc,
          height: selected ? _kCarDiscSelected : _kCarDisc,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? TakhiColors.ink : surfaces.hairline,
              width: selected ? TakhiStroke.indicator : _kCarEdge,
            ),
          ),
          child: Icon(
            Icons.local_taxi,
            size: selected ? _kCarGlyphSelected : _kCarGlyph,
            color: ink,
          ),
        ),
      ),
    );
  }
}
