// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'profile_providers.dart';

/// Lets a driver fill in and publish their public takhi profile (spec §6):
/// name, car, color, plate, and the two halves of a metered price -- the
/// km-tariff and the §7.4 waiting rate. Saving both publishes the signed
/// kind-0 event to every connected relay *and* caches it locally
/// (`DriverProfileService.publishAndSave`) so both rates are available
/// instantly to the §7.2 GPS-taximeter offer flow without a relay round
/// trip. They travel together everywhere downstream: a trip can never end
/// up running on this driver's distance rate and nobody's waiting rate.
/// Reached from `SettingsPage`, which pushes it -- so the `AppBar` carries
/// the usual back arrow.
///
/// That back is deliberately left unguarded (no `ConfirmLeaveScope`,
/// unlike a running trip or meter): leaving with a half-filled form costs
/// only re-typing it, since nothing is published or cached until
/// `publishAndSave` runs, and the previously saved profile stays intact.
///
/// The form is in two named parts, and that is the point of the redesign
/// rather than decoration. Six identical outlined boxes with floating labels
/// gave no clue that the first four describe a car a rider has to recognise
/// at the kerb and the last two are a price, and Material's floating labels
/// slid away the moment a field was filled -- so a driver checking whether
/// `1500` was the per-kilometre or the per-minute rate had to clear the box
/// to find out. Standing labels and two headings answer both at a glance.
class DriverProfilePage extends ConsumerStatefulWidget {
  const DriverProfilePage({super.key});

  @override
  ConsumerState<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends ConsumerState<DriverProfilePage> {
  final _name = TextEditingController();
  final _car = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  final _kmTariff = TextEditingController();

  /// The §7.4 waiting rate. Deliberately *not* part of [_canSave]: a driver
  /// who never fills it in is saying waiting is free, which is a complete
  /// price, not an incomplete form -- and is exactly how every profile
  /// saved before this field existed already reads.
  final _waitTariff = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(driverProfileServiceProvider).loadLocalProfile().then((profile) {
      if (profile == null || !mounted) return;
      _name.text = profile.name;
      _car.text = profile.car;
      _color.text = profile.color;
      _plate.text = profile.plate;
      _kmTariff.text = profile.kmTariffMnt.toString();
      _waitTariff.text = profile.waitTariffMntPerMinute.toString();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _car.dispose();
    _color.dispose();
    _plate.dispose();
    _kmTariff.dispose();
    _waitTariff.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _car.text.trim().isNotEmpty &&
      _color.text.trim().isNotEmpty &&
      _plate.text.trim().isNotEmpty &&
      int.tryParse(_kmTariff.text.trim()) != null;

  Future<void> _save() async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    final kmTariffMnt = int.tryParse(_kmTariff.text.trim());
    if (identity == null || kmTariffMnt == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(driverProfileServiceProvider)
          .publishAndSave(
            privHex: identity.privHex,
            now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            name: _name.text.trim(),
            car: _car.text.trim(),
            color: _color.text.trim(),
            plate: _plate.text.trim(),
            kmTariffMnt: kmTariffMnt,
            // Blank or unparseable reads as zero -- "waiting is free" --
            // rather than blocking the save. Unlike the km-tariff, which a
            // metered offer cannot be built without, a missing waiting rate
            // still describes a complete price.
            waitTariffMntPerMinute: int.tryParse(_waitTariff.text.trim()) ?? 0,
          );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.driverProfileSavedConfirmation)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    // `initState` already awaits the local store read to pre-fill the
    // fields; watching here just keeps this widget subscribed for
    // rebuilds if identity state ever changes later, matching every other
    // identity-dependent page's convention (e.g. `PassengerRidePage`).
    ref.watch(currentIdentityProvider);

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
                      title: l.driverProfileTitle,
                      subtitle: l.driverProfileSubtitle,
                    ),
                    const SizedBox(height: TakhiSpace.xl),
                    SectionHeading(
                      title: l.driverProfileVehicleSectionTitle,
                      compact: true,
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileNameField'),
                      label: l.driverProfileNameFieldLabel,
                      icon: Icons.person,
                      accent: TakhiAccent.steppe,
                      controller: _name,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileCarField'),
                      label: l.driverProfileCarFieldLabel,
                      icon: Icons.directions_car,
                      accent: TakhiAccent.steppe,
                      controller: _car,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileColorField'),
                      label: l.driverProfileColorFieldLabel,
                      icon: Icons.palette,
                      accent: TakhiAccent.steppe,
                      controller: _color,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfilePlateField'),
                      label: l.driverProfilePlateFieldLabel,
                      icon: Icons.confirmation_number,
                      accent: TakhiAccent.steppe,
                      controller: _plate,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.xl),
                    SectionHeading(
                      title: l.driverProfilePriceSectionTitle,
                      compact: true,
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileKmTariffField'),
                      label: l.driverProfileKmTariffFieldLabel,
                      icon: Icons.payments,
                      controller: _kmTariff,
                      keyboardType: TextInputType.number,
                      // What the number actually decides. Without it the
                      // rate reads as a suggestion rather than as the
                      // figure a metered trip is billed on.
                      hint: l.driverProfileKmTariffHint,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileWaitTariffField'),
                      label: l.driverProfileWaitTariffFieldLabel,
                      icon: Icons.hourglass_bottom,
                      controller: _waitTariff,
                      keyboardType: TextInputType.number,
                      // A driver pricing a jam should not have to guess
                      // whether an empty box means "free" or "not set yet".
                      hint: l.driverProfileWaitTariffHint,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
            TakhiSheet(
              showHandle: false,
              child: PrimaryButton(
                label: l.saveDriverProfileAction,
                loading: _saving,
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
