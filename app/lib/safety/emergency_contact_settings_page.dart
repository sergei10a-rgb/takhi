// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../widgets/primary_button.dart';
import 'safety_providers.dart';

/// Lets the user save the phone number the SOS sheet (`sos_button.dart`)
/// SMSes their last known location to. Reuses the single-field-and-button
/// layout already established twice in this codebase (`_PriceStep` in
/// `passenger_ride_page.dart`, the tariff-entry step in `TaximeterPage`).
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: Text(l.sosAction),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l.emergencyContactPhoneFieldLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: l.saveEmergencyContactAction,
                onPressed: _controller.text.trim().isEmpty ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
