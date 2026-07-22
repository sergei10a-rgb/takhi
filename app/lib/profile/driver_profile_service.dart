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

  Future<void> publishAndSave({
    required String privHex,
    required int now,
    required String name,
    required String car,
    required String color,
    required String plate,
    required int kmTariffMnt,
  }) async {
    final pubHex = pubkeyFromPrivate(privHex);
    final unsigned = buildDriverProfile(
      pubkey: pubHex,
      now: now,
      name: name,
      car: car,
      color: color,
      plate: plate,
      kmTariffMnt: kmTariffMnt,
    );
    final signed = signEvent(unsigned, privHex);
    await _pool.publish(signed);
    await _store.save(
      DriverProfile(
        name: name,
        car: car,
        color: color,
        plate: plate,
        kmTariffMnt: kmTariffMnt,
      ),
    );
  }

  /// Reads whatever profile was last saved locally -- either by this
  /// device's own `publishAndSave`, or pre-seeded for tests.
  Future<DriverProfile?> loadLocalProfile() => _store.load();
}
