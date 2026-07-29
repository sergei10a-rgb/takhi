// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/qr_card.dart';
import 'driver_qr_capture_page.dart';
import 'payment_providers.dart';

/// Side of the rendered QR image. Deliberately large: this code is scanned
/// by a passenger holding their own phone at arm's length, often through a
/// gap between seats, and a code that has to be leaned into is a code that
/// gets waved away in favour of cash.
const _kQrSize = 240.0;

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
    final surfaces = TakhiSurfaces.of(context);
    final bytes = ref.watch(driverQrBytesProvider).valueOrNull;
    if (bytes == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.qrNotSetHint,
            textAlign: TextAlign.center,
            style: TakhiType.support.copyWith(color: surfaces.muted),
          ),
          const SizedBox(height: TakhiSpace.xs),
          TextButton(
            // Never the Material default foreground here: that resolves to
            // `colorScheme.primary`, and brand gold on the light sheet is
            // 2.28:1 (see `dialogActionColors`' own note).
            style: TextButton.styleFrom(
              foregroundColor: surfaces.onSheet,
              minimumSize: const Size.fromHeight(TakhiTouch.minTarget),
              shape: const RoundedRectangleBorder(
                borderRadius: TakhiRadius.pillAll,
              ),
              textStyle: TakhiType.title,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DriverQrCapturePage()),
            ),
            child: Text(l.qrCaptureAction),
          ),
        ],
      );
    }
    return QrCard(
      child: Image.memory(bytes, width: _kQrSize, height: _kQrSize),
    );
  }
}
