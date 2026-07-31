// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The failure these cover is the one nothing else could see: with every
// relay down, Тахь has no server left to talk to, so a ride request is
// mined, signed, "published" and answered by nobody -- while the home sheet
// said «Холбогдлоо (0)», i.e. "Connected (0)". Every assertion here is
// about the app saying so out loud, in words a rider can act on.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/home/home_status_row.dart';
import 'package:takhi/home/relay_status_sheet.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/theme/takhi_theme.dart';

import 'support/fake_relay_socket.dart';

/// Every relay down, for good.
RelayPool _deadPool() =>
    RelayPool(defaultRelayUrls, connect: (u) => UnreachableRelaySocket());

/// Every relay up.
RelayPool _livePool(Map<String, FakeRelaySocket> sockets) =>
    RelayPool(defaultRelayUrls, connect: (u) => sockets[u] = FakeRelaySocket());

/// A pool that fails every dial until [comeUp] is called.
class _FlakyRelays {
  final Map<String, FakeRelaySocket> sockets = {};
  bool _up = false;

  void comeUp() => _up = true;

  RelayPool pool() => RelayPool(
    defaultRelayUrls,
    connect: (u) =>
        _up ? (sockets[u] = FakeRelaySocket()) : UnreachableRelaySocket(),
  );
}

Widget _harness(RelayPool pool, {KeyStore? keyStore}) => ProviderScope(
  overrides: [
    relayPoolProvider.overrideWithValue(pool),
    keyStoreProvider.overrideWithValue(keyStore ?? InMemoryKeyStore()),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('mn'),
    theme: takhiTheme(Brightness.light),
    // A Scaffold so `showModalBottomSheet` has somewhere to open.
    home: const Scaffold(body: SingleChildScrollView(child: HomeStatusRow())),
  ),
);

const _kOfflineWarning =
    'Сүлжээнд холбогдоогүй байна. Одоо нийтэлбэл дуудлага хэнд ч очихгүй.';
const _kOfflineChip = 'Сүлжээнд холбогдоогүй';
const _kReconnect = 'Дахин холбогдох';
const _kNoneConnectedTitle = 'Ямар ч реле холбогдоогүй';
const _kConnecting = 'Холбогдож байна…';

void main() {
  group('with every relay down', () {
    testWidgets('says publishing now reaches nobody, in those words', (
      t,
    ) async {
      await t.pumpWidget(_harness(_deadPool()));
      await t.pumpAndSettle();

      expect(find.text(_kOfflineWarning), findsOneWidget);
    });

    testWidgets('names the state instead of claiming a connection -- the '
        'chip never says «Холбогдлоо» with nothing connected', (t) async {
      await t.pumpWidget(_harness(_deadPool()));
      await t.pumpAndSettle();

      expect(find.text(_kOfflineChip), findsOneWidget);
      expect(find.textContaining('Холбогдлоо'), findsNothing);
      // Nor does a failed connect sit on «Холбогдож байна…» forever, which
      // is what it used to do on the strength of a comment claiming the
      // pool retried by itself. It does not.
      expect(find.text(_kConnecting), findsNothing);
    });

    testWidgets('offers a reconnect button', (t) async {
      await t.pumpWidget(_harness(_deadPool()));
      await t.pumpAndSettle();

      expect(find.widgetWithText(TextButton, _kReconnect), findsOneWidget);
    });

    testWidgets('reconnecting for real clears the warning and the chip '
        'starts counting again', (t) async {
      final relays = _FlakyRelays();
      await t.pumpWidget(_harness(relays.pool()));
      await t.pumpAndSettle();
      expect(find.text(_kOfflineWarning), findsOneWidget);

      relays.comeUp();
      await t.tap(find.text(_kReconnect));
      await t.pumpAndSettle();

      expect(find.text(_kOfflineWarning), findsNothing);
      expect(find.text(_kOfflineChip), findsNothing);
      expect(
        find.text(
          '${defaultRelayUrls.length} / ${defaultRelayUrls.length} '
          'реле холбогдсон',
        ),
        findsOneWidget,
      );
    });
  });

  group('with relays up', () {
    testWidgets('shows the count against the total, and no warning at all', (
      t,
    ) async {
      final sockets = <String, FakeRelaySocket>{};
      await t.pumpWidget(_harness(_livePool(sockets)));
      await t.pumpAndSettle();

      expect(
        find.text(
          '${defaultRelayUrls.length} / ${defaultRelayUrls.length} '
          'реле холбогдсон',
        ),
        findsOneWidget,
      );
      expect(find.text(_kOfflineWarning), findsNothing);
      expect(find.widgetWithText(TextButton, _kReconnect), findsNothing);
    });

    testWidgets('the last relay dying while the rider watches flips home to '
        'the warning -- no tap, no navigation, nothing else would have '
        'prompted a rebuild', (t) async {
      final sockets = <String, FakeRelaySocket>{};
      await t.pumpWidget(_harness(_livePool(sockets)));
      await t.pumpAndSettle();
      expect(find.text(_kOfflineWarning), findsNothing);

      for (final socket in sockets.values) {
        socket.dropFromTheOtherEnd();
      }
      await t.pumpAndSettle();

      expect(find.text(_kOfflineWarning), findsOneWidget);
      expect(find.text(_kOfflineChip), findsOneWidget);
    });
  });

  group('the relay list', () {
    testWidgets('opens from the chip and names every configured relay, '
        'marking the ones that are down', (t) async {
      await t.pumpWidget(_harness(_deadPool()));
      await t.pumpAndSettle();

      await t.tap(find.text(_kOfflineChip));
      await t.pumpAndSettle();

      expect(find.text(_kNoneConnectedTitle), findsOneWidget);
      for (final url in defaultRelayUrls) {
        expect(find.text(url), findsOneWidget);
      }
      expect(
        find.text('Холбогдсонгүй'),
        findsNWidgets(defaultRelayUrls.length),
      );
    });

    testWidgets('marks each relay by its own state, not by the pool as a '
        'whole', (t) async {
      // One relay up, the rest down: the panel has to be able to say which.
      final live = defaultRelayUrls.first;
      final pool = RelayPool(
        defaultRelayUrls,
        connect: (u) =>
            u == live ? FakeRelaySocket() : UnreachableRelaySocket(),
      );

      await t.pumpWidget(_harness(pool));
      await t.pumpAndSettle();

      await t.tap(find.text('1 / ${defaultRelayUrls.length} реле холбогдсон'));
      await t.pumpAndSettle();

      expect(find.text('Холбогдсон'), findsOneWidget);
      expect(
        find.text('Холбогдсонгүй'),
        findsNWidgets(defaultRelayUrls.length - 1),
      );
      // Not the alarm headline: something *is* getting through.
      expect(find.text(_kNoneConnectedTitle), findsNothing);
      expect(find.text('Реле холболт'), findsOneWidget);
    });

    testWidgets('reconnects from inside the sheet too', (t) async {
      final relays = _FlakyRelays();
      await t.pumpWidget(_harness(relays.pool()));
      await t.pumpAndSettle();

      await t.tap(find.text(_kOfflineChip));
      await t.pumpAndSettle();

      relays.comeUp();
      final reconnect = find.widgetWithText(FilledButton, _kReconnect);
      // The sheet scrolls on a small surface; the button is real but below
      // the fold.
      await t.ensureVisible(reconnect);
      await t.pumpAndSettle();
      await t.tap(reconnect);
      await t.pumpAndSettle();

      expect(find.text(_kNoneConnectedTitle), findsNothing);
      expect(find.text('Холбогдсон'), findsNWidgets(defaultRelayUrls.length));
    });
  });

  testWidgets('the relay chip clears the touch floor -- it became a control '
      'and nothing else measures it', (t) async {
    await t.pumpWidget(_harness(_deadPool()));
    await t.pumpAndSettle();

    final target = find.ancestor(
      of: find.text(_kOfflineChip),
      matching: find.byType(InkWell),
    );
    expect(target, findsOneWidget);
    expect(
      t.getSize(target).height,
      greaterThanOrEqualTo(TakhiTouch.minTarget),
    );
  });

  testWidgets('RelayStatusView can be pumped on its own', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [relayPoolProvider.overrideWithValue(_deadPool())],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          theme: takhiTheme(Brightness.light),
          home: const Scaffold(
            body: SingleChildScrollView(child: RelayStatusView()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text(_kNoneConnectedTitle), findsOneWidget);
  });
}
