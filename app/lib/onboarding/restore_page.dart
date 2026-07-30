// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/info_chip.dart';
import '../widgets/labeled_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';

/// How many words a valid BIP-39 phrase has here. Not a layout measurement:
/// it is the length the counter compares against, and the same number the
/// copy in `restoreWordCountLabel` spells out.
const _kPhraseWordCount = 12;

/// Lets a returning rider paste their 12-word recovery phrase back in.
/// `privateKeyFromMnemonic` throws [ArgumentError] for anything that fails
/// BIP-39 validation (wrong words, bad checksum) — that's ordinary,
/// expected user-input feedback here, not a programming bug, so it is
/// caught narrowly and surfaced as an inline error instead of crashing.
///
/// The field is, and always was, a **single multi-line box** rather than
/// twelve separate ones, so the whole phrase can be pasted in one go from
/// wherever the rider keeps it — nobody is going to fill in twelve inputs
/// on a phone. What the screen did not do was *say* so, or give any sign of
/// progress while typing: a rider who mistyped a space had no way to tell
/// eleven words from twelve until the button rejected the lot. The live
/// count ([AppLocalizations.restoreWordCountLabel]) is that missing signal,
/// and it turns green only at [_kPhraseWordCount].
///
/// The count deliberately does **not** gate the button. Word count is not
/// validity — a twelve-word phrase can still fail its checksum, and an
/// eleven-word one is worth attempting rather than silently refusing — so
/// the counter informs and `privateKeyFromMnemonic` still decides.
class RestorePage extends ConsumerStatefulWidget {
  const RestorePage({super.key});

  @override
  ConsumerState<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends ConsumerState<RestorePage> {
  final _controller = TextEditingController();
  bool _restoring = false;
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Words typed so far — whitespace-separated, empties dropped, so a
  /// trailing space does not read as a thirteenth word.
  int get _wordCount {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  Future<void> _restore() async {
    final mnemonic = _controller.text.trim();
    if (mnemonic.isEmpty || _restoring) return;
    setState(() {
      _restoring = true;
      _showError = false;
    });
    try {
      await ref.read(identityServiceProvider).restore(mnemonic);
      if (!mounted) return;
      context.go('/home');
    } on ArgumentError {
      if (!mounted) return;
      setState(() => _showError = true);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final count = _wordCount;
    final complete = count == _kPhraseWordCount;

    return Scaffold(
      backgroundColor: surfaces.canvas,
      // Carries the back arrow and nothing else: the screen's own name is
      // the SectionHeading below, and repeating it in the bar would put the
      // same word on screen three times over.
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
                      title: l.restoreIdentity,
                      subtitle: l.restoreSubtitle,
                    ),
                    const SizedBox(height: TakhiSpace.xl),
                    LabeledField(
                      label: l.restoreHint,
                      icon: Icons.key,
                      controller: _controller,
                      maxLines: 3,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      errorText: _showError ? l.restoreError : null,
                    ),
                    const SizedBox(height: TakhiSpace.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InfoChip(
                        label: l.restoreWordCountLabel(count),
                        icon: complete
                            ? Icons.check_circle_outline
                            : Icons.edit_outlined,
                        // Green only once the phrase is the right length --
                        // the one moment the chip has good news to give.
                        accent: complete
                            ? TakhiAccent.steppe
                            : TakhiAccent.neutral,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TakhiSheet(
              showHandle: false,
              child: PrimaryButton(
                label: l.restoreIdentity,
                loading: _restoring,
                onPressed: _restore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
