// SPDX-License-Identifier: AGPL-3.0-or-later

/// Shows the run's GPS diagnostic and lets the driver send it.
///
/// A whole screen rather than a dialog because the report is meant to be
/// read, not acknowledged — and because the one thing worse than a driver
/// not finding this is a driver finding it and having no way to get the
/// numbers off the phone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_version.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/primary_button.dart';
import 'meter_diagnostic_recorder.dart';
import 'meter_diagnostics_report.dart';

class MeterDiagnosticsPage extends StatelessWidget {
  final MeterDiagnosticRecorder recorder;

  const MeterDiagnosticsPage({super.key, required this.recorder});

  /// Summary plus rows, in that order.
  ///
  /// One share rather than two: the summary alone cannot be re-checked and
  /// the rows alone cannot be read, so sending either half on its own wastes
  /// the trip to the driver.
  Future<void> _share() async {
    final summary = formatMeterDiagnosticReport(
      recorder.log,
      appVersion: kAppVersion,
    );
    final rows = await recorder.readRows();
    await Share.share(rows == null ? summary : '$summary\n$rows');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final report = formatMeterDiagnosticReport(
      recorder.log,
      appVersion: kAppVersion,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.meterDiagnosticsTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(TakhiSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.meterDiagnosticsExplainer,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (recorder.lastWriteError != null) ...[
                      const SizedBox(height: TakhiSpace.sm),
                      Text(
                        l.meterDiagnosticsWriteFailedNotice,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: TakhiSpace.lg),
                    // Selectable, and monospaced, because the columns only
                    // line up in a fixed pitch and because a driver whose
                    // share sheet has nothing useful in it can still copy.
                    SelectableText(report, style: TakhiType.mono),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(TakhiSpace.md),
              child: PrimaryButton(
                label: l.meterDiagnosticsShareAction,
                onPressed: () => unawaited(_share()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
