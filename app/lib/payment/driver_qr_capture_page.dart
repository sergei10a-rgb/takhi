// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../widgets/primary_button.dart';
import 'payment_providers.dart';

/// Lets the driver pick their own bank QR code image from the gallery and
/// save it locally (spec §8) — gallery only for this MVP, no camera
/// permission needed. Mirrors `SeedBackupPage`'s single-purpose-page shape
/// (`app/lib/onboarding/seed_backup_page.dart`): a title, one primary
/// action, no navigation chrome beyond the default back button.
class DriverQrCapturePage extends ConsumerStatefulWidget {
  const DriverQrCapturePage({super.key});

  @override
  ConsumerState<DriverQrCapturePage> createState() =>
      _DriverQrCapturePageState();
}

class _DriverQrCapturePageState extends ConsumerState<DriverQrCapturePage> {
  Uint8List? _pickedBytes;
  bool _saving = false;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _pickedBytes = bytes);
  }

  Future<void> _save() async {
    final bytes = _pickedBytes;
    if (bytes == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(driverQrStoreProvider).save(bytes);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.qrSavedConfirmation)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final bytes = _pickedBytes;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: Text(l.qrCaptureTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: bytes == null
                      ? Text(l.qrNotSetHint, textAlign: TextAlign.center)
                      : Image.memory(bytes, width: 240, height: 240),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _pickImage,
                child: Text(l.qrCaptureAction),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: l.qrSavedConfirmation,
                loading: _saving,
                onPressed: bytes == null ? () {} : () => unawaited(_save()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
