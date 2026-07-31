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

  // ## There is deliberately no reference tariff here
  //
  // A `referenceKmTariffMnt: 2000` field used to sit below, and the
  // passenger's price step multiplied it by the routed distance to show a
  // "roughly this much" figure. Nothing measured that 2000. Its own comment
  // called it "a round, deliberately unremarkable number ... nobody does
  // [stand behind it]", and the rounding that made it feel modest is exactly
  // what made it read as checked.
  //
  // That is not a harmless placeholder. It sat on the one screen where a
  // rider types the price they are willing to pay, and a number on that
  // screen is an anchor: quote 2000 ₮/km to a city and enough people will
  // type what it implies for the invention to become the going rate. An app
  // with no company behind it, whose whole premise is that drivers and
  // riders set prices between themselves, does not get to seed that number
  // out of nowhere.
  //
  // So the price step now shows what the routing service actually measured
  // -- distance and driving time -- and no money at all until a real driver
  // names a real price. If a fork ever has a *sourced* rate (a published
  // municipal tariff, a regulator's table), that is when this field comes
  // back, with the citation next to it.

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
