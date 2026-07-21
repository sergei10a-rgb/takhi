// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'driver_qr_capture_page.dart';
import 'payment_providers.dart';

/// Renders the driver's saved bank QR image, or a "not set" hint linking to
/// [DriverQrCapturePage] when none has been saved yet. Only ever
/// instantiated when the current role is driver (Task 7/8 gate on `role`)
/// -- a passenger never renders their own QR-shaped hole, they see
/// `l.payWithQrOrCashHint` text instead.
///
/// Reads [driverQrBytesProvider] instead of calling `.load()` directly
/// inside a `FutureBuilder` (see that provider's doc comment for why): a
/// rebuild of this widget reuses the already-resolved bytes rather than
/// creating a fresh `Future` and flickering back to the "not set" hint.
class DriverQrDisplay extends ConsumerWidget {
  const DriverQrDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final bytes = ref.watch(driverQrBytesProvider).valueOrNull;
    if (bytes == null) {
      return Column(
        children: [
          Text(l.qrNotSetHint),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DriverQrCapturePage()),
            ),
            child: Text(l.qrCaptureAction),
          ),
        ],
      );
    }
    return Image.memory(bytes, width: 220, height: 220);
  }
}
