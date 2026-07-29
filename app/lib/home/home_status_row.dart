// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../nostr/relay_pool_provider.dart';
import '../theme/takhi_theme.dart';
import '../widgets/info_chip.dart';

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

/// The quiet line of facts at the foot of the home sheet: whether the app
/// is live on the relay network, and which identity it is live as.
///
/// Both are chips rather than sentences. They are status, not instruction --
/// a rider never *acts* on them, they only glance at them when something
/// feels wrong -- so they get the smallest, softest treatment the design
/// system has and sit below everything that is actually a control.
///
/// A [Wrap] rather than a [Row]: the relay chip's label grows with the
/// connected count and the key chip's with the text scale, and a status line
/// is the last thing that should ever throw an overflow.
class HomeStatusRow extends ConsumerWidget {
  const HomeStatusRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider);
    final npub = identity.hasValue ? identity.value?.npub : null;

    return Wrap(
      spacing: TakhiSpace.xs,
      runSpacing: TakhiSpace.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const _RelayStatusChip(),
        if (npub != null) _NpubChip(npub: npub),
      ],
    );
  }
}

/// The app's live connection state to the public relay network (Plan 2 §5):
/// `connecting…` while [relayConnectionProvider] is still awaiting
/// [RelayPool.connectAll], then `connected` with a live count of relays
/// actually holding an open socket once it resolves.
///
/// A failed connect shows `connecting…` too, deliberately: the pool retries,
/// and a rider has no action to take either way -- the honest summary of
/// both states is "not on the network yet".
class _RelayStatusChip extends ConsumerWidget {
  const _RelayStatusChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final connection = ref.watch(relayConnectionProvider);

    return connection.when(
      data: (pool) => InfoChip(
        label: '${l.connected} (${pool.connectedUrls.length})',
        icon: Icons.cloud_done_outlined,
        accent: TakhiAccent.steppe,
      ),
      loading: () => _connecting(l),
      error: (error, stack) => _connecting(l),
    );
  }

  InfoChip _connecting(AppLocalizations l) =>
      InfoChip(label: l.connecting, icon: Icons.cloud_queue_outlined);
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
