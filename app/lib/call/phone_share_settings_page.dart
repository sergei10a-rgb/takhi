// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/menu_row.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'call_providers.dart';

/// Lets the user save the phone number that goes out on the passenger ->
/// driver handoff DM once sharing is enabled (spec §7.3-②), and toggle
/// sharing itself. Without this screen, `PhoneShareSettingsStore
/// .saveOwnPhone`/`.setEnabled` were never called anywhere in production
/// -- `PassengerRidePage._select` already reads `loadOwnPhone`/`isEnabled`
/// correctly, but with no way for a user to ever *write* either value,
/// `RideHandoffPayload.phone` was always `null` and `CallStateFallbackPhone`
/// could never fire (Plan 5 review CRITICAL-2).
///
/// This screen asks for the one piece of personally identifying data the app
/// ever collects, so the two things it has to answer -- *why does it want my
/// number*, and *who ends up with it* -- are now on screen instead of left
/// to the user's imagination. A bare `TextField` labelled "Таны утасны
/// дугаар" above an unexplained switch was, reasonably, read as an app
/// harvesting phone numbers.
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
                      title: l.phoneShareSettingsTitle,
                      subtitle: l.phoneShareSubtitle,
                    ),
                    const SizedBox(height: TakhiSpace.xl),
                    LabeledField(
                      label: l.phoneShareOwnPhoneFieldLabel,
                      icon: Icons.phone,
                      accent: TakhiAccent.sky,
                      controller: _controller,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.lg),
                    // The switch sits inside the row's own target rather
                    // than beside it: `IgnorePointer` stops the thumb from
                    // handling the tap itself, so the whole card toggles
                    // once instead of the row and the switch both firing.
                    MenuRow(
                      icon: Icons.ios_share,
                      label: l.phoneShareEnabledToggleLabel,
                      subtitle: l.phoneShareEnabledToggleHint,
                      accent: TakhiAccent.sky,
                      onTap: () => setState(() => _enabled = !_enabled),
                      trailing: IgnorePointer(
                        child: Switch(
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TakhiSheet(
              showHandle: false,
              child: PrimaryButton(
                label: l.savePhoneShareSettingsAction,
                onPressed: _controller.text.trim().isEmpty ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
