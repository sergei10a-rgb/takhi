// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

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
class DriverQrDisplay extends ConsumerWidget {
  const DriverQrDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return FutureBuilder<Uint8List?>(
      future: ref.read(driverQrStoreProvider).load(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return Column(
            children: [
              Text(l.qrNotSetHint),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DriverQrCapturePage(),
                  ),
                ),
                child: Text(l.qrCaptureAction),
              ),
            ],
          );
        }
        return Image.memory(bytes, width: 220, height: 220);
      },
    );
  }
}
