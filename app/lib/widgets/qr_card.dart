// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';

/// The plate a scannable code sits on.
///
/// Every other surface in this app moves with the theme. This one does not,
/// and the exception is functional rather than stylistic: a QR code is read
/// by a camera, and a camera needs dark modules on a light quiet zone. In
/// the dark theme every surface the ladder offers is near-black, so a code
/// painted on one of them is not "low contrast" -- it is unreadable, and the
/// passenger standing beside the car simply cannot pay.
///
/// So the fill is white in both brightnesses. Only the edge and the shadow
/// follow the theme, which is enough to keep the plate from looking pasted
/// onto a dark screen.
class QrCard extends StatelessWidget {
  /// The code itself -- a rendered [Image] of the driver's saved bank QR, or
  /// a generated one.
  final Widget child;

  const QrCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
        boxShadow: surfaces.floatShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.sm),
        child: child,
      ),
    );
  }
}
