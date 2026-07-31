// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../nostr/relay_pool_provider.dart';
import '../theme/takhi_theme.dart';
import '../widgets/info_chip.dart';
import '../widgets/menu_row.dart';
import '../widgets/notice_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';

/// Ceiling on the sheet's content, as a fraction of the screen. Matches the
/// SOS sheet's: four relay rows and a button never come near it at the
/// default text scale, and past it the list scrolls inside the sheet rather
/// than pushing the button off the bottom.
const _kSheetContentMaxFraction = 0.72;

/// Opens the relay list over whatever screen asked for it.
///
/// A sheet rather than a route on purpose. This is a *reading* -- "how much
/// of the network can I reach right now" -- that a rider takes while
/// standing on the screen they were already using, and a route would push
/// home away, take over the back gesture, and need its own place in the
/// screenshot table for a panel that is four rows and a button.
Future<void> showRelayStatusSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      // The sheet paints itself -- [TakhiSheet] carries the fill, the
      // rounded top, the hairline and the bottom inset.
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      builder: (sheetContext) => TakhiSheet(
        showHandle: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(sheetContext).height *
                _kSheetContentMaxFraction,
          ),
          child: const SingleChildScrollView(child: RelayStatusView()),
        ),
      ),
    );

/// What the app can and cannot reach, named relay by relay.
///
/// Тахь has no server of its own, so this list *is* the app's delivery
/// network: a request, an offer, a receipt and every DM exist only because
/// one of these carried them. The whole panel exists because the failure it
/// describes is otherwise completely silent -- with every relay down the app
/// still accepts a ride request, still mines its proof-of-work, still moves
/// on to "waiting for offers", and the rider waits for something that was
/// never sent anywhere.
///
/// So it answers three questions in order: is anything reachable, which ones
/// are not, and what can I do about it.
///
/// Public (and a widget rather than a private half of [showRelayStatusSheet])
/// so a test can pump the panel on its own, and so a later screen that needs
/// the same reading can host it without reopening a sheet.
class RelayStatusView extends ConsumerWidget {
  const RelayStatusView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final status = watchRelayStatus(ref);
    final reconnecting = ref.watch(relayConnectionProvider).isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          // The headline states the situation rather than the topic when
          // the situation is the problem: a rider who opened this because
          // nothing is working should not have to read a list to find out.
          title: status.isOffline
              ? l.relayNoneConnectedTitle
              : l.relayStatusTitle,
          subtitle: l.relayStatusSubtitle,
          compact: true,
        ),
        const SizedBox(height: TakhiSpace.md),
        if (status.isOffline)
          NoticeCard(
            icon: Icons.cloud_off_outlined,
            text: l.relayNoneConnectedMessage,
            accent: TakhiAccent.clay,
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: InfoChip(
              label: l.relayConnectedCountLabel(
                status.connectedCount,
                status.total,
              ),
              icon: Icons.cloud_done_outlined,
              accent: TakhiAccent.steppe,
            ),
          ),
        const SizedBox(height: TakhiSpace.md),
        for (final url in status.urls)
          _RelayRow(url: url, connected: status.connectedUrls.contains(url)),
        const SizedBox(height: TakhiSpace.md),
        PrimaryButton(
          label: reconnecting
              ? l.relayReconnectingLabel
              : l.relayReconnectAction,
          // Disabled rather than swapped for a spinner: `PrimaryButton`'s
          // spinner animates forever, which would make `pumpAndSettle` hang
          // in every test that opens this sheet -- and the label already
          // says what is happening.
          onPressed: reconnecting ? null : () => reconnectRelays(ref),
        ),
      ],
    );
  }
}

/// One relay, and whether it is carrying anything.
///
/// A [MenuRow] with no tap handler: it is a statement, not a control. The
/// address is shown in full rather than as a hostname because the address
/// is what a user would have to change to fix it, and half of one is not
/// something anyone can act on.
class _RelayRow extends StatelessWidget {
  final String url;
  final bool connected;

  const _RelayRow({required this.url, required this.connected});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(bottom: TakhiSpace.xxs),
      child: MenuRow(
        icon: connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        label: url,
        accent: connected ? TakhiAccent.steppe : TakhiAccent.clay,
        trailing: InfoChip(
          label: connected
              ? l.relayRowConnectedLabel
              : l.relayRowUnreachableLabel,
          accent: connected ? TakhiAccent.steppe : TakhiAccent.clay,
        ),
      ),
    );
  }
}
