// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/notice_card.dart';
import '../widgets/qr_card.dart';
import 'ebarimt_receipt.dart';

/// Side of the eBarimt QR. Smaller than the bank QR it sits beside on the
/// finished screen: this code is scanned to *verify* a receipt, not to move
/// money, so it does not need to win the passenger's first glance.
const _kEbarimtQrSize = 200.0;

/// The eBarimt (И-Баримт) receipt a driver shows a passenger at trip end
/// (roadmap #9): the QR the passenger scans to verify it and enter the VAT
/// lottery, the lottery code beneath it, and — when the receipt came from the
/// demo issuer rather than a real PosAPI — an unmissable warning that it is
/// not filed.
///
/// [isDemo] is part of the card, not a caption the caller adds beside it,
/// precisely because a receipt-shaped card that could pass for a filed one is
/// the single thing this feature must never produce. It defaults to the safe
/// direction, and only the demo issuer's call site ever sets it true.
class EbarimtReceiptCard extends StatelessWidget {
  final EbarimtReceipt receipt;
  final bool isDemo;

  const EbarimtReceiptCard({
    super.key,
    required this.receipt,
    this.isDemo = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.ebarimtReceiptTitle,
          style: TakhiType.title.copyWith(color: surfaces.onSheet),
        ),
        const SizedBox(height: TakhiSpace.sm),
        if (isDemo) ...[
          NoticeCard(
            icon: Icons.science_outlined,
            text: l.ebarimtDemoNotice,
            accent: TakhiAccent.clay,
          ),
          const SizedBox(height: TakhiSpace.md),
        ],
        // QrImageView paints black modules by default; the plate is white in
        // both themes (see QrCard), so the code stays scannable in the dark
        // theme where every app surface is otherwise near-black.
        QrCard(child: QrImageView(data: receipt.qrData, size: _kEbarimtQrSize)),
        const SizedBox(height: TakhiSpace.xs),
        Text(
          l.ebarimtLotteryLabel(receipt.lottery),
          style: TakhiType.support.copyWith(color: surfaces.muted),
        ),
      ],
    );
  }
}
