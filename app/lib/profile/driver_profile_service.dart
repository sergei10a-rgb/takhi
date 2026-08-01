// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';
import 'driver_profile_store.dart';

/// Builds, signs, and publishes the driver's public kind-0 profile (spec
/// §6/§7.2), and keeps a local copy so `DriverProfilePage` and the §7.2
/// pricing-mode flow can read it without a relay round trip. Mirrors
/// `TripReceiptRepository.publish`'s build-sign-publish shape.
class DriverProfileService {
  final RelayPool _pool;
  final DriverProfileStore _store;
  DriverProfileService(this._pool, this._store);

  /// Publishes the vehicle-and-price half to every connected relay, and
  /// saves the whole profile -- names included -- locally.
  ///
  /// The asymmetry is the point, not an oversight. [familyName] and
  /// [givenName] are written to [_store] and go no further: a kind-0 event
  /// is world-readable and replicated forever, so a name published there is
  /// a name anyone can harvest against a pubkey that also carries this
  /// driver's plate number and, while they are working, a live geohash. The
  /// name reaches a passenger through the NIP-17 gift-wrapped offer
  /// instead, one passenger at a time, and only after that passenger asked
  /// for a ride the driver chose to answer.
  ///
  /// `buildDriverProfile` has no `name:` parameter at all, so this is
  /// enforced by the protocol layer rather than by remembering not to pass
  /// one here.
  Future<void> publishAndSave({
    required String privHex,
    required int now,
    required String car,
    required String color,
    required String plate,
    required int kmTariffMnt,
    String? familyName,
    String? givenName,
    int waitTariffMntPerMinute = 0,
    int durationTariffMntPerMinute = 0,
  }) async {
    final pubHex = pubkeyFromPrivate(privHex);
    final unsigned = buildDriverProfile(
      pubkey: pubHex,
      now: now,
      car: car,
      color: color,
      plate: plate,
      kmTariffMnt: kmTariffMnt,
      waitTariffMntPerMinute: waitTariffMntPerMinute,
      durationTariffMntPerMinute: durationTariffMntPerMinute,
    );
    final signed = signEvent(unsigned, privHex);
    await _pool.publish(signed);
    await _store.save(
      DriverProfile(
        familyName: familyName,
        givenName: givenName,
        car: car,
        color: color,
        plate: plate,
        kmTariffMnt: kmTariffMnt,
        waitTariffMntPerMinute: waitTariffMntPerMinute,
        durationTariffMntPerMinute: durationTariffMntPerMinute,
      ),
    );
  }

  /// Reads whatever profile was last saved locally -- either by this
  /// device's own `publishAndSave`, or pre-seeded for tests.
  Future<DriverProfile?> loadLocalProfile() => _store.load();
}
