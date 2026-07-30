// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/qr_card.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'payment_providers.dart';

/// Side of the preview plate. The same figure the picked image was already
/// drawn at, kept so the empty state occupies exactly the space the code
/// will fill -- nothing on the screen moves when an image arrives.
const _kQrPreviewSize = 240.0;

/// Size of the placeholder glyph inside the empty plate.
const _kPlaceholderGlyphSize = 64.0;

/// Lets the driver pick their own bank QR code image from the gallery and
/// save it locally (spec §8) — gallery only for this MVP, no camera
/// permission needed.
///
/// That back button is deliberately left unguarded (no `ConfirmLeaveScope`,
/// unlike a running trip or meter): the most an accidental back costs here
/// is picking the image again -- nothing is in flight, nothing published,
/// and the previously saved QR is untouched until `_save` succeeds.
///
/// The empty state used to be one sentence floating in the vertical centre
/// of an otherwise blank screen: it read as a screen that had failed to load
/// rather than as one waiting for input, and it said nothing about what the
/// code is eventually *for*. It is now a plate the size of the code itself,
/// so the layout does not move when an image arrives, under a heading that
/// says a rider will scan this to pay at the end of a trip.
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
    // Narrowly caught: `FileDriverQrStore.save` writes through `dart:io`
    // and can fail for ordinary environmental reasons (disk full,
    // permission denied) that are not programming bugs -- those get a
    // user-facing SnackBar instead of crashing the page. Anything else
    // (a genuine bug) still propagates.
    FileSystemException? saveError;
    try {
      await ref.read(driverQrStoreProvider).save(bytes);
    } on FileSystemException catch (e) {
      saveError = e;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    if (saveError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.qrSaveError)));
      return;
    }
    // Without this, `DriverQrDisplay` (whichever screen underneath this one
    // pushed it) would keep showing whatever it had cached before this page
    // opened -- popping back alone does not rebuild it, so the freshly
    // saved QR would only appear after some unrelated rebuild happened to
    // occur (see `driverQrBytesProvider`'s doc comment).
    ref.invalidate(driverQrBytesProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.qrSavedConfirmation)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final bytes = _pickedBytes;

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
                      title: l.qrCaptureTitle,
                      subtitle: l.qrCaptureSubtitle,
                    ),
                    const SizedBox(height: TakhiSpace.xl),
                    Center(child: _QrPreview(bytes: bytes)),
                  ],
                ),
              ),
            ),
            TakhiSheet(
              showHandle: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    label: l.qrSaveAction,
                    loading: _saving,
                    onPressed: bytes == null ? null : () => unawaited(_save()),
                  ),
                  const SizedBox(height: TakhiSpace.xs),
                  _PickButton(label: l.qrCaptureAction, onPressed: _pickImage),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The plate the code sits on, in both of its states.
///
/// Deliberately the same size either way. An empty state that is smaller
/// than the thing it stands in for makes every control below it jump the
/// moment an image is chosen -- on a screen whose next tap is "save", that
/// is a tap landing somewhere the driver did not aim.
class _QrPreview extends StatelessWidget {
  final Uint8List? bytes;

  const _QrPreview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final picked = bytes;

    if (picked != null) {
      return QrCard(
        child: Image.memory(
          picked,
          width: _kQrPreviewSize,
          height: _kQrPreviewSize,
        ),
      );
    }

    // Not a [QrCard]: that plate is white in both brightnesses because a
    // camera needs a light quiet zone, and a white square with nothing on
    // it would read as a code that failed to load rather than as a slot
    // waiting to be filled.
    return Container(
      width: _kQrPreviewSize,
      height: _kQrPreviewSize,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(TakhiSpace.md),
      decoration: BoxDecoration(
        color: surfaces.field,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.qr_code_2,
            size: _kPlaceholderGlyphSize,
            color: surfaces.muted,
          ),
          const SizedBox(height: TakhiSpace.sm),
          Text(
            l.qrNotSetHint,
            textAlign: TextAlign.center,
            style: TakhiType.support.copyWith(color: surfaces.muted),
          ),
        ],
      ),
    );
  }
}

/// "Choose an image" -- the step before the primary action, so it is quieter
/// than it, but it is still the only way to make the primary action
/// possible, so it keeps a visible edge rather than becoming plain text.
class _PickButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PickButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: surfaces.onSheet,
        side: BorderSide(color: surfaces.muted),
        minimumSize: const Size.fromHeight(TakhiTouch.minTarget),
        shape: const RoundedRectangleBorder(borderRadius: TakhiRadius.pillAll),
        textStyle: takhiButtonTextStyle(context, TakhiType.title),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
