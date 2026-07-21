// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'driver_qr_store.dart';

final driverQrStoreProvider = Provider<DriverQrStore>(
  (ref) => FileDriverQrStore(
    () async => (await getApplicationDocumentsDirectory()).path,
  ),
);

/// Loads the driver's saved QR bytes exactly once per mount, caching the
/// result across every rebuild of anything that watches it (`DriverQrDisplay`)
/// instead of re-reading the file and re-showing "not set" every time the
/// surrounding widget tree happens to rebuild -- calling `.load()` straight
/// from a `FutureBuilder`'s `future:` would otherwise hand it a brand new
/// `Future` on every `build()`, which resets it to "waiting" for a frame
/// (a visible flicker back to the "not set" hint) and re-reads the file.
/// `autoDispose` frees the cached bytes once nothing is watching this
/// anymore (e.g. after leaving the finished/done screen), rather than
/// holding them in memory for the app's remaining lifetime.
/// `DriverQrCapturePage._save` invalidates this after a successful save so
/// a freshly captured QR is reflected immediately once the driver pops back
/// to whichever screen shows [DriverQrDisplay], instead of that screen
/// continuing to show whatever was cached before the capture page opened.
final driverQrBytesProvider = FutureProvider.autoDispose<Uint8List?>(
  (ref) => ref.watch(driverQrStoreProvider).load(),
);
