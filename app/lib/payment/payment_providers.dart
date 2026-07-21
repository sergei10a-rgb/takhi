// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'driver_qr_store.dart';

final driverQrStoreProvider = Provider<DriverQrStore>(
  (ref) => FileDriverQrStore(
    () async => (await getApplicationDocumentsDirectory()).path,
  ),
);
