// SPDX-License-Identifier: AGPL-3.0-or-later

/// Where a driver writes down what went wrong.
///
/// The whole screen is one idea: make the report worth reading, and leave
/// the sending to the driver. There is nowhere for it to go automatically —
/// nobody runs this app — so the honest design is to fill in the facts a
/// person always forgets, show the finished text, and put a copy button and
/// a share button under it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_version.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/notice_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_heading.dart';
import 'bug_report.dart';

class BugReportPage extends StatefulWidget {
  /// The screen the driver came from, named the way they would name it.
  final String screen;

  const BugReportPage({super.key, required this.screen});

  @override
  State<BugReportPage> createState() => _BugReportPageState();
}

class _BugReportPageState extends State<BugReportPage> {
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Rebuilds the preview as they type, so the thing they are about to
    // hand over is the thing they can see.
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  String get _report => composeBugReport(
    BugReportContext(
      appVersion: kAppVersion,
      screen: widget.screen,
      platform: Platform.operatingSystem,
      description: _description.text,
    ),
  );

  Future<void> _copy() async {
    final l = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: _report));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.bugReportCopiedConfirmation)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return Scaffold(
      backgroundColor: surfaces.canvas,
      appBar: AppBar(
        backgroundColor: surfaces.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l.bugReportTitle,
          style: TakhiType.title.copyWith(color: surfaces.onSheet),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(TakhiSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NoticeCard(
                      icon: Icons.outbox_outlined,
                      text: l.bugReportExplainer,
                      accent: TakhiAccent.sky,
                    ),
                    const SizedBox(height: TakhiSpace.lg),
                    SectionHeading(
                      compact: true,
                      title: l.bugReportDescriptionLabel,
                    ),
                    const SizedBox(height: TakhiSpace.xs),
                    TextField(
                      controller: _description,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: l.bugReportDescriptionHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: TakhiSpace.lg),
                    // The finished text, shown rather than described. A
                    // driver being asked to hand something over should be
                    // able to read all of it first.
                    SelectableText(_report, style: TakhiType.mono),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(TakhiSpace.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    label: l.bugReportShareAction,
                    onPressed: () => unawaited(Share.share(_report)),
                  ),
                  const SizedBox(height: TakhiSpace.xs),
                  SecondaryButton(
                    label: l.bugReportCopyAction,
                    onPressed: () => unawaited(_copy()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
