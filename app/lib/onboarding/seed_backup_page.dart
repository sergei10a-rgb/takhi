// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/dialog_action_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';

/// Size of the warning banner's glyph. Matched to the heading beside it
/// rather than to the body text under it: the triangle is the first thing
/// seen on this screen and reads as a sign, not as punctuation.
const _kWarningGlyphSize = 22.0;

/// How much of the error colour the banner's fill keeps. A wash, not a
/// block: the words inside it have to stay the loudest thing in the box.
const _kWarningFillOpacity = 0.08;

/// Shown once, immediately after a fresh identity is created. Displays the
/// 12-word BIP-39 recovery phrase and a hard warning that it is the only way
/// back in — Тахь has no server-side account recovery. The phrase never
/// touches disk or network from this screen; it only lives in navigation
/// state for the duration of this route.
///
/// Because of that, this is the single most destructive back gesture in the
/// app: `OnboardingPage` arrives here with `context.go('/seed')`, so a stray
/// hardware back or edge swipe would leave the only screen that will ever
/// show these words, with no way to bring them back. [_confirmLeave] gates
/// it, in the same spirit as `ConfirmLeaveScope` guards the running meter
/// and an active trip.
///
/// The forward exit is gated too, and for the same reason. "Хадгаллаа" used
/// to be live from the first frame, so the most irreversible screen in the
/// app was also the one with the least friction on it -- a rider could tap
/// straight past twelve words they had not read, and nothing afterwards can
/// undo that. It now waits on an explicit acknowledgement
/// ([AppLocalizations.seedBackupConfirmLabel]), which is a deliberate second
/// action rather than a reflex.
///
/// What this screen deliberately does **not** offer is a copy-to-clipboard
/// button. The Android clipboard is readable by other applications, and a
/// private key is the one value in this app that must never be put somewhere
/// a third party can read (spec §6). Transcription to paper is slower on
/// purpose.
class SeedBackupPage extends StatefulWidget {
  final String mnemonic;

  const SeedBackupPage({super.key, required this.mnemonic});

  @override
  State<SeedBackupPage> createState() => _SeedBackupPageState();
}

class _SeedBackupPageState extends State<SeedBackupPage> {
  /// Mirrors `ConfirmLeaveScope`'s own guard: a second back press racing
  /// the dialog's entry animation would otherwise stack a second identical
  /// copy that then needs dismissing twice.
  bool _asking = false;

  /// Whether the rider has said, in as many words, that the phrase is
  /// written down. Gates the forward exit only -- the back gesture keeps
  /// its own dialog, because a rider who has *not* ticked this is exactly
  /// the one that dialog exists for.
  bool _acknowledged = false;

  /// Deliberately *not* [ConfirmLeaveScope], despite the identical shape:
  /// that widget finishes by calling `Navigator.pop()`, and `go('/seed')`
  /// replaced the stack, so this route is its only entry and `canPop()` is
  /// false -- confirming would do nothing at all and trap the user in the
  /// dialog. Leaving this screen means going on to `/home`, not popping.
  Future<void> _confirmLeave() async {
    final l = AppLocalizations.of(context)!;
    _asking = true;
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l.leaveSeedBackupTitle),
          content: Text(l.leaveSeedBackupMessage),
          actions: [
            // Same emphasis rule as `ConfirmLeaveScope`: leaving is the
            // reflex this dialog exists to interrupt, and here it costs
            // the only sight of the recovery words the user will ever
            // get -- so staying is the loud answer.
            DialogActionBar(
              dismiss: DialogAction(
                label: l.stayAction,
                tone: DialogActionTone.primary,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              proceed: DialogAction(
                label: l.backToHomeAction,
                tone: DialogActionTone.caution,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        ),
      );
    } finally {
      _asking = false;
    }
    // `null` is a barrier tap or a back press on the dialog itself --
    // treated as "stay", the safe answer on this screen above all others.
    if (confirmed != true || !mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final words = widget.mnemonic.trim().split(RegExp(r'\s+'));
    final surfaces = TakhiSurfaces.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _asking) return;
        unawaited(_confirmLeave());
      },
      child: Scaffold(
        backgroundColor: surfaces.canvas,
        body: SafeArea(
          // The same two-part shape every other step-shaped screen in the
          // app uses: something to read, scrolling, above one action
          // anchored on a sheet so it can never scroll out of reach.
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
                        title: l.seedBackupTitle,
                        subtitle: l.seedBackupSubtitle,
                      ),
                      const SizedBox(height: TakhiSpace.md),
                      _WarningBanner(text: l.seedBackupWarning),
                      const SizedBox(height: TakhiSpace.lg),
                      _WordGrid(words: words),
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
                    _AcknowledgeRow(
                      label: l.seedBackupConfirmLabel,
                      value: _acknowledged,
                      onChanged: (v) => setState(() => _acknowledged = v),
                    ),
                    const SizedBox(height: TakhiSpace.sm),
                    PrimaryButton(
                      label: l.iSavedIt,
                      onPressed: _acknowledged
                          ? () => context.go('/home')
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "These words are the only way back in." The one place in the app that
/// uses the error colour for something that has not gone wrong yet.
class _WarningBanner extends StatelessWidget {
  final String text;

  const _WarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    // `colorScheme.error` and never a fixed red: the light theme's deep red
    // clears 2.34:1 on the dark surface, which is below the floor even for
    // large text.
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(TakhiSpace.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _kWarningFillOpacity),
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: color,
            size: _kWarningGlyphSize,
          ),
          const SizedBox(width: TakhiSpace.sm),
          Expanded(
            child: Text(
              text,
              style: TakhiType.support.copyWith(color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The twelve words, two to a row.
///
/// Rows of [Expanded] tiles rather than a `GridView` with a fixed
/// `childAspectRatio`: an aspect ratio pins the tile height to its width,
/// so at a large system text scale the word inside it is clipped. Here the
/// row grows instead. On this screen a clipped word is not a cosmetic
/// defect -- it is an identity the rider can never recover.
class _WordGrid extends StatelessWidget {
  final List<String> words;

  const _WordGrid({required this.words});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < words.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: TakhiSpace.xs));
      rows.add(
        Row(
          // Never `stretch`: this row sits in a column of unbounded height,
          // and stretching a child into that is an infinite constraint. The
          // two tiles hold the same single line of text, so they come out
          // the same height on their own.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _WordTile(number: i + 1, word: words[i]),
            ),
            const SizedBox(width: TakhiSpace.xs),
            Expanded(
              child: i + 1 < words.length
                  ? _WordTile(number: i + 2, word: words[i + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

/// One numbered word.
///
/// Both colours come from the theme rather than from fixed palette
/// constants. The tiles used to be `TakhiColors.sand` with `TakhiColors.ink`
/// on them in *both* brightnesses, which put twelve pale parchment blocks on
/// a near-black dark-theme screen -- readable, but a hole punched through
/// the surface ladder every other screen obeys. On the recessed field
/// surface they read as wells cut into the page, in either brightness.
class _WordTile extends StatelessWidget {
  final int number;
  final String word;

  const _WordTile({required this.number, required this.word});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final gold = takhiAccentColors(
      TakhiAccent.gold,
      Theme.of(context).brightness,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.field,
        borderRadius: TakhiRadius.tileAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TakhiSpace.sm,
          vertical: TakhiSpace.sm,
        ),
        // One `Text.rich` rather than two `Text`s in a `Row`: eleven of the
        // twelve words in a BIP-39 test vector can be the same word, so a
        // test that wants to prove "position 7 reads `acoustic`" can only
        // do it against the ordinal and the word as a single string.
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$number. ',
                style: TakhiType.label.copyWith(
                  color: gold.onTint,
                  // Tabular, so the one- and two-digit ordinals in the two
                  // columns start their words at the same x.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: word,
                style: TakhiType.title.copyWith(color: surfaces.onSheet),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tick that unlocks the way forward.
///
/// A whole-row target rather than the checkbox alone: the box itself is
/// 18dp of paint, and this is not a control anyone should have to aim at.
class _AcknowledgeRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AcknowledgeRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      checked: value,
      child: Material(
        color: Colors.transparent,
        borderRadius: TakhiRadius.cardAll,
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: TakhiRadius.cardAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: TakhiTouch.minTarget),
            child: Row(
              children: [
                // `ExcludeSemantics` so the row publishes one node carrying
                // both the label and the toggle, rather than a labelled
                // wrapper around an anonymous checkbox.
                ExcludeSemantics(
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    activeColor: scheme.primary,
                    checkColor: scheme.onPrimary,
                    side: BorderSide(color: surfaces.muted),
                  ),
                ),
                const SizedBox(width: TakhiSpace.xs),
                Expanded(
                  child: Text(
                    label,
                    style: TakhiType.body.copyWith(color: surfaces.onSheet),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
