// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../widgets/primary_button.dart';
import 'call_providers.dart';

/// Lets the user save the phone number that goes out on the passenger ->
/// driver handoff DM once sharing is enabled (spec §7.3-②), and toggle
/// sharing itself. Without this screen, `PhoneShareSettingsStore
/// .saveOwnPhone`/`.setEnabled` were never called anywhere in production
/// -- `PassengerRidePage._select` already reads `loadOwnPhone`/`isEnabled`
/// correctly, but with no way for a user to ever *write* either value,
/// `RideHandoffPayload.phone` was always `null` and `CallStateFallbackPhone`
/// could never fire (Plan 5 review CRITICAL-2). Reuses the single-field-
/// and-button layout already established for exactly this shape of
/// settings screen (`EmergencyContactSettingsPage`, `_PriceStep` in
/// `passenger_ride_page.dart`, the tariff-entry step in `TaximeterPage`).
class PhoneShareSettingsPage extends ConsumerStatefulWidget {
  const PhoneShareSettingsPage({super.key});

  @override
  ConsumerState<PhoneShareSettingsPage> createState() =>
      _PhoneShareSettingsPageState();
}

class _PhoneShareSettingsPageState
    extends ConsumerState<PhoneShareSettingsPage> {
  final _controller = TextEditingController();

  /// Defaults to `true` even before the store's own async default resolves
  /// -- matches `PhoneShareSettingsStore.isEnabled()`'s documented default
  /// (spec §7.3-②: "toggle (default: асаалттай)") so the switch never
  /// visibly flips from an incorrect initial value once the real value
  /// loads.
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final store = ref.read(phoneShareSettingsStoreProvider);
    store.loadOwnPhone().then((phone) {
      if (phone != null && mounted) _controller.text = phone;
    });
    store.isEnabled().then((enabled) {
      if (mounted) setState(() => _enabled = enabled);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(phoneShareSettingsStoreProvider);
    await store.saveOwnPhone(_controller.text.trim());
    await store.setEnabled(_enabled);
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
        title: Text(l.phoneShareSettingsTitle),
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
                  labelText: l.phoneShareOwnPhoneFieldLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: Text(l.phoneShareEnabledToggleLabel),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: l.savePhoneShareSettingsAction,
                onPressed: _controller.text.trim().isEmpty ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
