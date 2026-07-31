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

/// The face detector the portrait check runs on.
///
/// ⚠️ Currently [UnavailableFaceDetector], which **refuses every photo**.
/// That is a deliberate placeholder, not a bug to route around, and it
/// fails closed on purpose: a check that waves everything through when its
/// engine is missing is worse than no check at all, because the promise
/// stays on the screen after the mechanism behind it is gone and nothing
/// says so. Refusing is loud -- the first driver to try to set a photo is
/// told the checker is not working, which is a bug report.
///
/// Two steps make it real, both of which need network access this code
/// could not take on its own:
///
///  1. `flutter pub add tflite_flutter` (Apache-2.0), excluding the
///     `litert-gpu` artifact in `android/app/build.gradle.kts` -- one
///     128x128 inference when a driver edits their profile does not need a
///     GPU delegate, and dropping it saves ~2.4MB on arm64.
///  2. Bundle MediaPipe's `blaze_face_short_range.tflite` (Apache-2.0,
///     ~224KB) as an asset and implement [FaceDetector] against it,
///     returning boxes normalized to the image. Everything else -- the
///     confidence floor, the exactly-one rule, the size floor -- is already
///     in `faceCheckProblem` and needs no changes.
///
/// The implementation must not touch the network;
/// `test/profile/driver_photo_offline_test.dart` enforces that mechanically
/// and will fail if it does.
final faceDetectorProvider = Provider<FaceDetector>(
  (ref) => const UnavailableFaceDetector(),
);

final driverPhotoServiceProvider = Provider<DriverPhotoService>(
  (ref) => DriverPhotoService(
    ref.watch(faceDetectorProvider),
    ref.watch(driverPhotoStoreProvider),
  ),
);
