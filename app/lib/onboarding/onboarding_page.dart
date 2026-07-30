// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../identity/identity_service.dart';
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/accent_dot.dart';
import '../widgets/dialog_action_bar.dart';
import '../widgets/info_chip.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';

/// Diameter of the brand mark. Its own measurement rather than a spacing
/// token: this is artwork sized against the screen, not a gap in a rhythm.
const _kBrandmarkSize = 132.0;

/// Thickness of the gold ring around it.
const _kBrandmarkRing = 2.0;

/// Blur of the glow behind the ring, and how far it spreads past it.
const _kBrandmarkGlowBlur = 36.0;
const _kBrandmarkGlowSpread = 2.0;

/// How much of the brand gold the glow keeps.
const _kBrandmarkGlowOpacity = 0.28;

/// Size of the glyph in the legal card's leading disc.
const _kLegalDotSize = 28.0;

/// The two sides of a trip.
///
/// Retained as a public name although no production widget selects one any
/// more: `home_page_test` imports it to assert that home no longer carries
/// the passenger/driver segmented toggle it once did, and the four service
/// tiles on the home sheet are what replaced that choice. The labels
/// themselves still appear here, as a statement of what the app is rather
/// than as a question the rider has to answer before they have an identity.
enum TakhiMode { passenger, driver }

/// First screen a new install shows: the brand mark, what this app is, the
/// liability disclaimer, and the two entry points into identity — create a
/// fresh keypair or restore one from an existing 12-word phrase. No network
/// call happens here, so first paint is never blocked on connectivity.
///
/// Two things this screen used to get wrong, both of which only a rendered
/// picture could show:
///
/// * it opened with a **passenger/driver `SegmentedButton`** whose value was
///   read by nothing at all -- a decision demanded of someone who does not
///   yet have an identity, which then changed nothing. It also rendered as a
///   row of empty boxes (`▯▯▯▯▯▯`) in both brightnesses, because
///   `SegmentedButton.styleFrom(textStyle: ...)` *replaces* the inherited
///   style rather than merging onto it and so dropped the bundled Cyrillic
///   family, exactly as [takhiButtonTextStyle] documents. Both roles are now
///   stated as [InfoChip]s -- labels, not controls;
/// * the disclaimer and the secondary button were painted in
///   `TakhiColors.sand`, a pale parchment, while the surface under them is
///   theme-resolved. On the dark theme that is the pairing they were drawn
///   for; on the light theme, whose surface is the equally pale
///   `TakhiColors.paper`, it was pale-on-pale and all but invisible. Both
///   now read their colours off [TakhiSurfaces], which is per-brightness by
///   construction.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  // Two separate flags on purpose: [_busy] guards against a double tap
  // re-entering this whole flow (including the brief pre-check below, and
  // the modal confirmation dialog) without showing any spinner, while
  // [_creating] drives the button's spinner UI only for the actual
  // create-and-persist work. Showing the spinner across the confirmation
  // dialog would pointlessly animate for as long as the rider takes to
  // decide, and — since [CircularProgressIndicator] animates indefinitely —
  // would also never let `pumpAndSettle` settle in widget tests.
  bool _busy = false;
  bool _creating = false;
  bool _showError = false;

  /// Creates a fresh identity and hands the generated mnemonic to the seed
  /// backup screen. `createNewWithMnemonic` persists the new private key via
  /// [KeyStore.write], which throws [SecureStoreException] when the native
  /// secure-storage backend fails (locked keystore, denied access,
  /// unsupported platform, etc.) — that's an expected failure mode here, not
  /// a programming bug, so it's caught narrowly and surfaced as an inline
  /// error with the button re-enabled for a retry, instead of leaving the
  /// only entry point into the app permanently stuck mid-spinner.
  ///
  /// A router redirect normally keeps a rider who already has a stored
  /// identity away from this screen entirely (see `routerProvider`), but
  /// this is the only action in the app that can destroy a private key, so
  /// it re-checks and asks for confirmation itself too — belt and braces
  /// against any path (a timing gap before the redirect fires, a future
  /// entry point) that could otherwise reach this button with an identity
  /// already on disk and silently overwrite it.
  Future<void> _createIdentity() async {
    if (_busy) return;
    _busy = true;
    try {
      final service = ref.read(identityServiceProvider);
      final existing = await service.load();
      if (existing != null) {
        if (!mounted) return;
        final confirmed = await _confirmOverwrite(context);
        if (!confirmed) return;
      }
      if (!mounted) return;
      setState(() {
        _creating = true;
        _showError = false;
      });
      final (mnemonic, _) = await service.createNewWithMnemonic();
      if (!mounted) return;
      context.go('/seed', extra: mnemonic);
    } on SecureStoreException {
      if (!mounted) return;
      setState(() => _showError = true);
    } finally {
      _busy = false;
      if (mounted && _creating) setState(() => _creating = false);
    }
  }

  /// Asks the rider to confirm before an existing identity is overwritten.
  /// Returns `true` only if they explicitly chose to proceed.
  Future<bool> _confirmOverwrite(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.overwriteIdentityTitle),
        content: Text(l.overwriteIdentityMessage),
        actions: [
          // The only [DialogActionTone.destructive] in the app: confirming
          // discards a private key nothing can regenerate. Everything else
          // that looks dangerous -- leaving a trip, cancelling a request --
          // costs a repeatable action, and gets the quieter caution tone.
          DialogActionBar(
            dismiss: DialogAction(
              label: l.overwriteIdentityCancel,
              tone: DialogActionTone.neutral,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            proceed: DialogAction(
              label: l.overwriteIdentityConfirm,
              tone: DialogActionTone.destructive,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: surfaces.canvas,
      body: SafeArea(
        // Scrolls rather than using `Spacer`s: at a large system text scale
        // a fixed column with flexible gaps is the shape that overflows,
        // and this is the one screen a rider cannot get past if it does.
        // `minHeight` + `Center` gets the best of both -- the column is
        // centred in the viewport while it fits, and scrolls once it does
        // not, instead of hanging off the top with a hole underneath it.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: TakhiSpace.xl,
              vertical: TakhiSpace.xxl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - TakhiSpace.xxl * 2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: _Brandmark()),
                  const SizedBox(height: TakhiSpace.md),
                  Text(
                    l.appName,
                    textAlign: TextAlign.center,
                    style: TakhiType.hero.copyWith(color: TakhiColors.gold),
                  ),
                  const SizedBox(height: TakhiSpace.md),
                  const _RoleChips(),
                  const SizedBox(height: TakhiSpace.xs),
                  Text(
                    l.onboardingRoleHint,
                    textAlign: TextAlign.center,
                    style: TakhiType.support.copyWith(color: surfaces.muted),
                  ),
                  const SizedBox(height: TakhiSpace.xxl),
                  // Spec §4's legal/liability disclaimer -- shown here every
                  // time onboarding is reachable at all (a returning rider
                  // with a stored identity is redirected straight past this
                  // screen by `routerProvider`, so in practice this is always
                  // the rider's first encounter with the app). Always
                  // accessible again afterwards from `SettingsPage` ->
                  // `LegalNoticePage`.
                  const _LegalCard(),
                  const SizedBox(height: TakhiSpace.xxl),
                  if (_showError) ...[
                    Text(
                      l.createIdentityError,
                      textAlign: TextAlign.center,
                      style: TakhiType.support.copyWith(color: scheme.error),
                    ),
                    const SizedBox(height: TakhiSpace.sm),
                  ],
                  PrimaryButton(
                    label: l.createIdentity,
                    loading: _creating,
                    onPressed: _createIdentity,
                  ),
                  const SizedBox(height: TakhiSpace.xs),
                  // The shared component rather than a bespoke outline: this is
                  // the app's one "second answer under the primary" shape, and
                  // the pale-parchment button it replaces was invisible on the
                  // light theme's equally pale surface.
                  SecondaryButton(
                    label: l.restoreIdentity,
                    onPressed: () => context.push('/restore'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brandmark extends StatelessWidget {
  const _Brandmark();

  @override
  Widget build(BuildContext context) => Container(
    width: _kBrandmarkSize,
    height: _kBrandmarkSize,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: TakhiColors.gold, width: _kBrandmarkRing),
      boxShadow: [
        BoxShadow(
          color: TakhiColors.gold.withValues(alpha: _kBrandmarkGlowOpacity),
          blurRadius: _kBrandmarkGlowBlur,
          spreadRadius: _kBrandmarkGlowSpread,
        ),
      ],
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/icon.png',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) =>
            const ColoredBox(color: TakhiColors.goldDeep),
      ),
    ),
  );
}

/// The two roles, stated rather than asked.
///
/// [InfoChip] and not a segmented control on purpose: this is the one fact
/// about the app a first-time rider needs before they tap anything -- that
/// the same install drives and rides -- and a chip is documented as a label
/// that takes no tap handler, so it cannot be mistaken for a choice with
/// consequences.
class _RoleChips extends StatelessWidget {
  const _RoleChips();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: TakhiSpace.xs,
      runSpacing: TakhiSpace.xs,
      children: [
        InfoChip(
          label: l.passengerMode,
          icon: Icons.hail,
          accent: TakhiAccent.gold,
        ),
        InfoChip(
          label: l.driverMode,
          icon: Icons.local_taxi,
          accent: TakhiAccent.steppe,
        ),
      ],
    );
  }
}

/// The liability disclaimer, as a card rather than as loose grey text.
///
/// It is the one paragraph on this screen and the only warning a rider gets
/// before creating an identity, so it is given a surface of its own -- which
/// is also what stops it reading as decorative fine print set in whatever
/// colour happened to be nearby.
class _LegalCard extends StatelessWidget {
  const _LegalCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.sheet,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AccentDot(
              icon: Icons.gavel,
              accent: TakhiAccent.clay,
              size: _kLegalDotSize,
            ),
            const SizedBox(width: TakhiSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.legalNoticeTitle,
                    style: TakhiType.micro.copyWith(color: surfaces.muted),
                  ),
                  const SizedBox(height: TakhiSpace.xxs),
                  Text(
                    l.legalNoticeBody,
                    style: TakhiType.support.copyWith(
                      color: surfaces.onSheet,
                      // Looser than the role's own leading: legal wording is
                      // read sentence by sentence rather than scanned.
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
