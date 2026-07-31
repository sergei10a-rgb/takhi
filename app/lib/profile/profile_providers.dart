// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nostr/relay_pool_provider.dart';
import 'driver_photo_face_check.dart';
import 'driver_photo_service.dart';
import 'driver_photo_store.dart';
import 'driver_profile_service.dart';
import 'driver_profile_store.dart';
import 'face/tflite_face_detector.dart';

final driverProfileStoreProvider = Provider<DriverProfileStore>(
  (ref) => SharedPreferencesDriverProfileStore(SharedPreferences.getInstance),
);

final driverProfileServiceProvider = Provider<DriverProfileService>(
  (ref) => DriverProfileService(
    ref.watch(relayPoolProvider),
    ref.watch(driverProfileStoreProvider),
  ),
);

/// Where the driver's portrait lives: a file in the app's private documents
/// directory, never a relay. Same shape as `driverQrStoreProvider`
/// (`payment/payment_providers.dart`).
final driverPhotoStoreProvider = Provider<DriverPhotoStore>(
  (ref) => FileDriverPhotoStore(
    () async => (await getApplicationDocumentsDirectory()).path,
  ),
);

/// The face detector the portrait check runs on: MediaPipe BlazeFace,
/// bundled as an Apache-2.0 asset and run entirely on the device.
///
/// This provider used to return [UnavailableFaceDetector], which throws for
/// every photograph. That was written as a deliberate fail-closed
/// placeholder -- the argument being that a check which waves everything
/// through once its engine is missing is worse than no check, because the
/// promise stays on screen after the mechanism behind it is gone.
///
/// The argument was right and the consequence was still a disaster, so it
/// is worth recording rather than quietly deleting. `driverOfferBlock`
/// makes a portrait mandatory and `OfferService.sendOffer` enforces it, so
/// a detector that refuses every photo does not merely disable a check --
/// it means **no driver anywhere can send a single offer**, which is what
/// shipped in v0.2.0. Every test in the repo overrode this provider with a
/// detector that accepts, so all 848 of them passed.
///
/// The lesson taken is not "fail open". It is that a gate must never be
/// shipped ahead of the engine that opens it, and that a provider every
/// test replaces is a provider nothing tests. See
/// `test/profile/driver_profile_persistence_test.dart`, which exercises
/// this one for real and would have caught it.
///
/// Kept alive for the process: [Interpreter] loading dominates the cost,
/// and a driver retaking a rejected photo runs it several times in a row.
final faceDetectorProvider = Provider<FaceDetector>((ref) {
  final detector = TfliteFaceDetector();
  ref.onDispose(detector.close);
  return detector;
});

final driverPhotoServiceProvider = Provider<DriverPhotoService>(
  (ref) => DriverPhotoService(
    ref.watch(faceDetectorProvider),
    ref.watch(driverPhotoStoreProvider),
  ),
);
