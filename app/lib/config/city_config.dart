// SPDX-License-Identifier: AGPL-3.0-or-later

/// The one seam spec §11 calls for ("Хотын багц" = config JSON: map
/// center, default relay hints, locale) collapsed to its smallest useful
/// form for this MVP: just the map's starting center, which is the only
/// literal city-specific value that was actually hardcoded and duplicated
/// across `passenger_ride_page.dart`, `driver_inbox_page.dart`, and
/// `taximeter_page.dart` (each previously defined its own
/// `_defaultLat`/`_defaultLon`/`_defaultCityCenter` consts, all three
/// pointing at the same coordinates). `FORKING.md` points a new city's
/// fork at exactly this one file. `defaultRelayUrls` (Plan 2,
/// `nostr/relay_pool_provider.dart`) and locale (`app/lib/l10n/`,
/// `MaterialApp.router`'s `locale:`) remain their own separate seams --
/// unifying all three into one `CityConfig` object is a reasonable future
/// step once a second city fork actually exists to prove out the right
/// shape (YAGNI: no second fork exists yet to design against).
class CityConfig {
  final String name;
  final double centerLat;
  final double centerLon;

  const CityConfig({
    required this.name,
    required this.centerLat,
    required this.centerLon,
  });
}

/// Ulaanbaatar, Sukhbaatar Square -- the coordinates every ride/taximeter
/// screen already defaulted to independently before this task.
const CityConfig defaultCityConfig = CityConfig(
  name: 'Улаанбаатар',
  centerLat: 47.9186,
  centerLon: 106.9176,
);
