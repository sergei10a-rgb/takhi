// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'safety_providers.dart';

/// Lets the user save the phone number the SOS sheet (`sos_button.dart`)
/// texts their last known location to.
///
/// Reachable from `SettingsPage` as well as from the SOS sheet's own empty
/// state. It used to be reachable *only* from that empty state, which
/// vanishes the moment a number is saved -- so a rider whose emergency
/// contact changed their phone had no way back to this field at all.
///
/// The one line under the heading is doing real work: SOS is the least
/// rehearsed surface in the app, and someone typing a number here has to
/// know that it is the number a message will be addressed to later, not one
/// this app will ever ring by itself.
class EmergencyContactSettingsPage extends ConsumerStatefulWidget {
  const EmergencyContactSettingsPage({super.key});

  @override
  ConsumerState<EmergencyContactSettingsPage> createState() =>
      _EmergencyContactSettingsPageState();
}

class _EmergencyContactSettingsPageState
    extends ConsumerState<EmergencyContactSettingsPage> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref.read(emergencyContactStoreProvider).loadPhone().then((phone) {
      if (phone != null && mounted) _controller.text = phone;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(emergencyContactStoreProvider)
        .savePhone(_controller.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return Scaffold(
      backgroundColor: surfaces.canvas,
      appBar: AppBar(
        backgroundColor: surfaces.canvas,
        foregroundColor: surfaces.onSheet,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  TakhiSpace.md,
                  TakhiSpace.lg,
                  TakhiSpace.md,
                  TakhiSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeading(
                      title: l.settingsEmergencyContactMenuLabel,
                      subtitle: l.emergencyContactSubtitle,
                    ),
                    const SizedBox(height: TakhiSpace.xl),
                    LabeledField(
                      label: l.emergencyContactPhoneFieldLabel,
                      icon: Icons.emergency_share,
                      accent: TakhiAccent.clay,
                      controller: _controller,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
            TakhiSheet(
              showHandle: false,
              child: PrimaryButton(
                label: l.saveEmergencyContactAction,
                onPressed: _controller.text.trim().isEmpty ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
