// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/primary_button.dart';
import 'profile_providers.dart';

/// Lets a driver fill in and publish their public takhi profile (spec §6):
/// name, car, color, plate, and the two halves of a metered price -- the
/// km-tariff and the §7.4 waiting rate. Saving both publishes the signed
/// kind-0 event to every connected relay *and* caches it locally
/// (`DriverProfileService.publishAndSave`) so both rates are available
/// instantly to the §7.2 GPS-taximeter offer flow without a relay round
/// trip. They travel together everywhere downstream: a trip can never end
/// up running on this driver's distance rate and nobody's waiting rate.
/// Reached from `SettingsPage` (spec: "HomePage settings-ээс орох цэг"),
/// which pushes it -- so the `AppBar` carries the usual back arrow.
///
/// That back is deliberately left unguarded (no `ConfirmLeaveScope`,
/// unlike a running trip or meter): leaving with a half-filled form costs
/// only re-typing it, since nothing is published or cached until
/// `publishAndSave` runs, and the previously saved profile stays intact.
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
    final scheme = Theme.of(context).colorScheme;
    // `initState` already awaits the local store read to pre-fill the
    // fields; watching here just keeps this widget subscribed for
    // rebuilds if identity state ever changes later, matching every other
    // identity-dependent page's convention (e.g. `PassengerRidePage`).
    ref.watch(currentIdentityProvider);
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: Text(l.driverProfileTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TakhiSpace.md),
          child: Column(
            children: [
              TextField(
                key: const Key('driverProfileNameField'),
                controller: _name,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l.driverProfileNameFieldLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: TakhiSpace.sm),
              TextField(
                key: const Key('driverProfileCarField'),
                controller: _car,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l.driverProfileCarFieldLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: TakhiSpace.sm),
              TextField(
                key: const Key('driverProfileColorField'),
                controller: _color,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l.driverProfileColorFieldLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: TakhiSpace.sm),
              TextField(
                key: const Key('driverProfilePlateField'),
                controller: _plate,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l.driverProfilePlateFieldLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: TakhiSpace.sm),
              TextField(
                key: const Key('driverProfileKmTariffField'),
                controller: _kmTariff,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l.driverProfileKmTariffFieldLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: TakhiSpace.sm),
              TextField(
                key: const Key('driverProfileWaitTariffField'),
                controller: _waitTariff,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l.driverProfileWaitTariffFieldLabel,
                  // One line, under the field: what the rate buys and what
                  // leaving it blank means. A driver pricing a jam should
                  // not have to guess whether an empty box means "free" or
                  // "not set yet".
                  helperText: l.driverProfileWaitTariffHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: TakhiSpace.md),
              PrimaryButton(
                label: l.saveDriverProfileAction,
                loading: _saving,
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
