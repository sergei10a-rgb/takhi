// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../nostr/relay_pool.dart';
import '../nostr/relay_pool_provider.dart';
import '../theme/takhi_theme.dart';
import '../widgets/info_chip.dart';
import '../widgets/notice_card.dart';
import '../widgets/secondary_button.dart';
import 'relay_status_sheet.dart';

/// Leading characters of an `npub` kept when abbreviating it. Ten covers
/// the fixed `npub1` prefix plus five characters that actually differ
/// between keys.
const _kNpubHeadLength = 10;

/// Trailing characters kept. Head and tail together are what people
/// actually compare when checking a key by eye.
const _kNpubTailLength = 6;

/// [npub] with its middle elided -- `npub1abcde…xyz123`.
///
/// A bech32 public key is 63 characters. Printed in full on the home sheet
/// it is a wall of noise that pushes everything else down and still cannot
/// be read; printed as head and tail it stays *identifiable* (which is the
/// only thing anyone uses it for at a glance) in a single chip. The whole
/// value is never lost -- [HomeStatusRow]'s chip copies it in full.
///
/// Keys shorter than the elision would be are returned unchanged, so a
/// malformed or test-shortened key is shown as-is rather than gaining a
/// misleading ellipsis.
String shortenNpub(String npub) {
  if (npub.length <= _kNpubHeadLength + _kNpubTailLength + 1) return npub;
  return '${npub.substring(0, _kNpubHeadLength)}…'
      '${npub.substring(npub.length - _kNpubTailLength)}';
}

/// The foot of the home sheet: whether the app can reach the relay network
/// at all, and which identity it is on it as.
///
/// Normally two chips. They are status, not instruction -- a rider never
/// *acts* on them, they only glance at them when something feels wrong --
/// so they get the smallest, softest treatment the design system has and sit
/// below everything that is actually a control.
///
/// **Except when nothing is reachable**, which is not a status at all but a
/// fact the rider has to act on before doing anything else. Тахь has no
/// server: with every relay down, tapping through to a ride still accepts
/// the request, still mines its proof-of-work, and still moves on to
/// "waiting for offers" -- for a request no driver was ever sent. That case
/// gets a notice and a reconnect button above the chips, on the one screen
/// the rider passes through before entering the flow, because a chip is not
/// where you tell someone their next action cannot work.
///
/// A [Wrap] rather than a [Row] for the chips: the relay chip's label grows
/// with the connected count and the key chip's with the text scale, and a
/// status line is the last thing that should ever throw an overflow.
class HomeStatusRow extends ConsumerWidget {
  const HomeStatusRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider);
    final npub = identity.hasValue ? identity.value?.npub : null;
    final status = watchRelayStatus(ref);
    final connection = ref.watch(relayConnectionProvider);

    // Only once a connect attempt has actually finished. Before that
    // everything is legitimately unconnected for a moment, and opening the
    // app with a red warning that clears itself a frame later teaches
    // riders to ignore the warning that matters.
    final attempted = connection.hasValue || connection.hasError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (attempted && status.isOffline) ...[
          const _RelayOfflineWarning(),
          const SizedBox(height: TakhiSpace.md),
        ],
        Wrap(
          spacing: TakhiSpace.xs,
          runSpacing: TakhiSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _RelayStatusChip(status: status, connecting: connection.isLoading),
            if (npub != null) _NpubChip(npub: npub),
          ],
        ),
      ],
    );
  }
}

/// The one thing on home that says an action will not work, and offers the
/// fix next to it.
///
/// Deliberately a notice plus a button rather than a louder chip. The chip
/// above states a *reading*; this states a *consequence* ("publishing now
/// reaches nobody") and the only move that changes it. The button is the
/// quiet secondary style, not the gold primary: the rider still came here to
/// take a ride, and a control that outshouts the trip block would be reading
/// the emergency as more important than the errand.
class _RelayOfflineWarning extends ConsumerWidget {
  const _RelayOfflineWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final reconnecting = ref.watch(relayConnectionProvider).isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoticeCard(
          icon: Icons.cloud_off_outlined,
          text: l.relayPublishOfflineWarning,
          accent: TakhiAccent.clay,
        ),
        const SizedBox(height: TakhiSpace.xs),
        SecondaryButton(
          label: reconnecting
              ? l.relayReconnectingLabel
              : l.relayReconnectAction,
          onPressed: reconnecting ? null : () => reconnectRelays(ref),
        ),
      ],
    );
  }
}

/// How much of the relay network the app is actually on, and a way into the
/// detail.
///
/// Three states, and the middle one is the whole point of this widget:
///
/// * a connect attempt in flight -- `connecting…`;
/// * **nothing reachable** -- named as such. This used to render as
///   `Холбогдлоо (0)`, i.e. "Connected (0)", which is not a bad label but a
///   false statement, and a failed connect rendered as `connecting…`
///   forever on the strength of a comment claiming the pool retried. It does
///   not retry by itself; [reconnectRelays] is what retries;
/// * some relays up -- the count *and the total*, because "2" is unreadable
///   without knowing there are four.
///
/// Tappable, unlike a plain [InfoChip]: a count answers "how many", and the
/// next question every time is "which one is down". The gesture, the
/// semantics and the [TakhiTouch.minTarget] floor are added here rather than
/// inside the chip, exactly as [_NpubChip] does it.
class _RelayStatusChip extends StatelessWidget {
  final RelayStatus status;
  final bool connecting;

  const _RelayStatusChip({required this.status, required this.connecting});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (label, icon, accent) = switch ((connecting, status.isOffline)) {
      (true, _) => (
        l.connecting,
        Icons.cloud_queue_outlined,
        TakhiAccent.neutral,
      ),
      (false, true) => (
        l.relayOfflineChipLabel,
        Icons.cloud_off_outlined,
        TakhiAccent.clay,
      ),
      (false, false) => (
        l.relayConnectedCountLabel(status.connectedCount, status.total),
        Icons.cloud_done_outlined,
        TakhiAccent.steppe,
      ),
    };

    return Semantics(
      button: true,
      label: l.relayStatusOpenAction,
      child: Tooltip(
        message: l.relayStatusOpenAction,
        child: Material(
          color: Colors.transparent,
          borderRadius: TakhiRadius.pillAll,
          child: InkWell(
            onTap: () => showRelayStatusSheet(context),
            borderRadius: TakhiRadius.pillAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TakhiTouch.minTarget,
              ),
              // As in [_NpubChip]: without `widthFactor: 1` the box would
              // stretch to the whole sheet width and the pill would stop
              // looking like a chip.
              child: Center(
                widthFactor: 1,
                child: InfoChip(label: label, icon: icon, accent: accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The abbreviated public key, tappable to copy the whole thing.
///
/// [InfoChip] is deliberately not a control -- it takes no tap handler and
/// makes no touch-target promise -- so the gesture, the semantics and the
/// [TakhiTouch.minTarget] floor are added here around it rather than being
/// smuggled into the chip for one call site.
class _NpubChip extends StatelessWidget {
  final String npub;

  const _NpubChip({required this.npub});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Semantics(
      button: true,
      label: l.copyPublicKeyAction,
      child: Tooltip(
        message: l.copyPublicKeyAction,
        child: Material(
          color: Colors.transparent,
          borderRadius: TakhiRadius.pillAll,
          child: InkWell(
            onTap: () => _copy(context),
            borderRadius: TakhiRadius.pillAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TakhiTouch.minTarget,
              ),
              // `widthFactor: 1` keeps the chip hugging its text -- without
              // it the box would stretch to the whole sheet width and the
              // pill would stop looking like a chip.
              child: Center(
                widthFactor: 1,
                child: InfoChip(
                  label: shortenNpub(npub),
                  icon: Icons.key_outlined,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    // Both resolved before the await: the clipboard write is asynchronous,
    // and reading an inherited widget out of `context` afterwards is the
    // classic use-after-dispose in a Flutter callback.
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: npub));
    messenger.showSnackBar(
      SnackBar(content: Text(l.publicKeyCopiedConfirmation)),
    );
  }
}
