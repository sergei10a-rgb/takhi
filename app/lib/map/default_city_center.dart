// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:latlong2/latlong.dart' as ll;

/// Ulaanbaatar's Sukhbaatar Square -- the one shared map-center fallback
/// every ride/meter screen falls back to until a real city-config seam
/// exists (spec §11; see `RideMap`'s doc comment). Previously redeclared
/// separately in `meter/taximeter_page.dart`, `ride/active_trip_view.dart`,
/// `ride/driver_inbox_page.dart`, and `ride/passenger_ride_page.dart` --
/// centralized here so the one literal only needs updating in one place
/// once a real city-config seam exists (DRY).
///
/// Kept as separate `double` consts alongside [defaultCityCenter] (rather
/// than deriving them back out of the `LatLng`) because `LatLng`'s fields,
/// while `final`, aren't const-evaluable through instance-field access on
/// this SDK -- `passenger_ride_page.dart`'s `_pickup`/`_destination` field
/// initializers need plain `double` consts, not a const expression derived
/// from a `LatLng` instance (see Task 9 deviations).
const double defaultCityCenterLat = 47.9186;
const double defaultCityCenterLon = 106.9176;
const ll.LatLng defaultCityCenter = ll.LatLng(
  defaultCityCenterLat,
  defaultCityCenterLon,
);
