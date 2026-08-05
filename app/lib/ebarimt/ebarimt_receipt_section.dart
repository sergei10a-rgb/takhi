// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/secondary_button.dart';
import 'demo_ebarimt_issuer.dart';
import 'ebarimt_issuer.dart';
import 'ebarimt_receipt.dart';
import 'ebarimt_receipt_card.dart';

/// Default clock. A top-level tearoff so the widget stays const-constructible;
/// it only stamps [EbarimtReceipt.issuedAt], which the card never shows, so
/// tests do not need to control it.
int _defaultNowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// The eBarimt block on the driver's finished screen (roadmap #9).
///
/// Starts as a single action rather than a second QR code: a driver taking
/// cash should not have to scroll past a receipt nobody asked for to reach the
/// "next passenger" button. Tapping it issues a receipt through [issuer] — the
/// [DemoEbarimtIssuer] until a real PosAPI is wired — and shows an
/// [EbarimtReceiptCard] for the passenger to scan.
///
/// [isDemo] rides straight onto the card and defaults true alongside the demo
/// issuer, so the presentation that warns "not a filed receipt" is the one you
/// get without having to remember to ask for it. When a real PosAPI issuer is
/// injected, the call site passes `isDemo: false`.
class EbarimtReceiptSection extends StatefulWidget {
  /// The fare the receipt is for — the same total the screen shows above.
  final int fareMnt;

  final EbarimtIssuer issuer;
  final bool isDemo;
  final int Function() nowSeconds;

  const EbarimtReceiptSection({
    super.key,
    required this.fareMnt,
    this.issuer = const DemoEbarimtIssuer(),
    this.isDemo = true,
    this.nowSeconds = _defaultNowSeconds,
  });

  @override
  State<EbarimtReceiptSection> createState() => _EbarimtReceiptSectionState();
}

class _EbarimtReceiptSectionState extends State<EbarimtReceiptSection> {
  EbarimtReceipt? _receipt;
  bool _issuing = false;

  Future<void> _issue() async {
    setState(() => _issuing = true);
    final receipt = await widget.issuer.issue(
      grossMnt: widget.fareMnt,
      now: widget.nowSeconds(),
    );
    if (!mounted) return;
    setState(() {
      _receipt = receipt;
      _issuing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final receipt = _receipt;
    if (receipt != null) {
      return EbarimtReceiptCard(receipt: receipt, isDemo: widget.isDemo);
    }
    return SecondaryButton(
      label: l.ebarimtIssueAction,
      onPressed: _issuing ? null : _issue,
    );
  }
}
