// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';

import 'package:takhi_protocol/takhi_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'relay_filter.dart';

export 'relay_filter.dart';

/// Minimal duplex text-message socket abstraction so [RelayPool] can be
/// driven by a real WebSocket ([WsRelaySocket]) or a fake in tests.
abstract class RelaySocket {
  Stream<String> get messages;
  void send(String data);
  Future<void> close();

  /// Completes once the socket has actually connected, or completes with an
  /// error if the connection could not be established (DNS failure,
  /// connection refused, TLS failure, ...). Real sockets connect
  /// asynchronously, so [RelayPool.connectAll] awaits this before treating a
  /// relay as connected. Defaults to immediately-ready for fakes that don't
  /// model connection failure.
  Future<void> get ready => Future<void>.value();

  /// Completes when the connection is gone -- closed by either end, or lost
  /// with the network. [RelayPool] watches this so a relay that dies under
  /// the app stops being counted as connected; without it the app keeps
  /// reporting a connection it no longer has, which is the exact lie
  /// "published" used to be told on top of.
  ///
  /// Defaults to a future that never completes, for fakes that do not model
  /// a connection dying: such a socket is simply never dropped, which is
  /// the old behaviour.
  Future<void> get done => Completer<void>().future;
}

/// [RelaySocket] backed by a real WebSocket connection to a public relay.
class WsRelaySocket implements RelaySocket {
  final WebSocketChannel _channel;

  WsRelaySocket(String url)
    : _channel = WebSocketChannel.connect(Uri.parse(url));

  @override
  Stream<String> get messages => _channel.stream.map((e) => e as String);

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();

  @override
  Future<void> get ready => _channel.ready;

  @override
  Future<void> get done => _channel.sink.done;
}

int _subCounter = 0;

/// Connects to a set of public Nostr relays over WebSocket, publishes
/// signed events to all of them, and merges subscription results —
/// deduping by event id and dropping anything that fails [verifyEvent].
///
/// Never talks to any authored server; [urls] are public, user-editable
/// relay addresses.
/// Default cap for one subscription's deduplication set (see
/// [RelayPool.subscribe], which owns one per `REQ`) -- generous enough that
/// a normal session's live subscriptions never legitimately churn through
/// this many distinct event ids before their `RelayFilter`s naturally close
/// (a ride request, its handful of offers, a trip's location pings, etc.),
/// but bounded so a long-lived subscription cannot grow its set without
/// limit.
const kDefaultSeenEventIdsCap = 10000;

/// What the app knows about its own reach into the relay network, at one
/// instant.
///
/// Тахь has no server: a ride request, an offer, a receipt and every DM
/// exist only because some relay carried them. So "how many relays are we
/// on" is not a diagnostic detail, it is the difference between a request
/// that reaches drivers and one that reaches nobody -- and the UI has to be
/// able to say which, in those terms, without reaching into [RelayPool]'s
/// internals or recomputing set arithmetic at three call sites.
class RelayStatus {
  /// Every configured relay, in the order they are configured.
  final List<String> urls;

  /// The subset currently holding an open socket.
  final Set<String> connectedUrls;

  const RelayStatus({required this.urls, required this.connectedUrls});

  /// Configured relays with no open socket: unreachable, or dropped.
  Set<String> get unreachableUrls => urls.toSet().difference(connectedUrls);

  int get connectedCount => connectedUrls.length;

  int get total => urls.length;

  /// Nothing published now reaches anyone, and nothing can arrive.
  bool get isOffline => connectedUrls.isEmpty;
}

class RelayPool {
  final List<String> urls;
  final RelaySocket Function(String url) _connect;
  final Map<String, RelaySocket> _sockets = {};
  final int _seenEventIdsCap;

  RelayPool(
    this.urls, {
    RelaySocket Function(String url)? connect,
    int seenEventIdsCap = kDefaultSeenEventIdsCap,
  }) : _connect = connect ?? ((u) => WsRelaySocket(u)),
       _seenEventIdsCap = seenEventIdsCap {
    if (seenEventIdsCap <= 0) {
      throw ArgumentError.value(
        seenEventIdsCap,
        'seenEventIdsCap',
        'must be positive',
      );
    }
  }

  /// URLs currently holding an open socket.
  Set<String> get connectedUrls => _sockets.keys.toSet();

  /// Configured relays with no open socket right now.
  Set<String> get unreachableUrls => urls.toSet().difference(connectedUrls);

  /// True while not a single relay is reachable -- the state in which
  /// [publish] is a no-op and no event can arrive.
  bool get isOffline => _sockets.isEmpty;

  /// The current health of the pool, as one value the UI can render.
  RelayStatus get status =>
      RelayStatus(urls: List.unmodifiable(urls), connectedUrls: connectedUrls);

  /// [status] now, and again after every connect and every drop.
  ///
  /// A stream rather than a getter alone because the interesting change --
  /// the last relay going away while the user stares at the screen -- is
  /// one nothing else would ever prompt a rebuild for.
  ///
  /// Deliberately **not** an `async*` generator. A generator body does not
  /// begin running until a microtask after `listen`, and `connectAll` on a
  /// fast connection resolves inside exactly that gap -- the announcement
  /// lands on a broadcast stream with no subscriber yet, is dropped, and the
  /// only value the listener ever sees is the stale "nothing connected" one
  /// taken before the connect. That is the failure this whole change exists
  /// to remove, reintroduced one layer down. Subscribing to the upstream
  /// inside [StreamController.onListen], which runs synchronously, closes
  /// the window.
  Stream<RelayStatus> watchStatus() {
    late final StreamController<RelayStatus> controller;
    StreamSubscription<void>? upstream;
    controller = StreamController<RelayStatus>(
      onListen: () {
        controller.add(status);
        upstream = _statusChanges.stream.listen((_) => controller.add(status));
      },
      onCancel: () async => upstream?.cancel(),
    );
    return controller.stream;
  }

  final StreamController<void> _statusChanges =
      StreamController<void>.broadcast();

  void _announceStatus() {
    if (!_statusChanges.isClosed) _statusChanges.add(null);
  }

  /// Connects every configured relay that is not already connected.
  /// Unreachable relays are skipped rather than failing the whole pool.
  ///
  /// [RelaySocket.ready] is awaited (in parallel, across all relays) so a
  /// relay that connects synchronously but then fails to establish the
  /// underlying connection (DNS failure, connection refused, TLS failure,
  /// ...) is never added to [_sockets] / reported via [connectedUrls].
  ///
  /// **Safe to call again** -- which is what makes a "reconnect" button
  /// possible. Relays already holding a socket are left completely alone:
  /// re-dialling them would overwrite `_sockets[url]` with a second socket
  /// and leak the first, and every live [subscribe] listening on that first
  /// socket would go quiet without anything saying so. So a retry costs one
  /// dial per *down* relay and nothing at all for the ones that are fine.
  Future<void> connectAll() async {
    final pending = <String, RelaySocket>{};
    for (final url in urls) {
      if (_sockets.containsKey(url)) continue;
      try {
        pending[url] = _connect(url);
      } on Exception {
        // Skip unreachable relay; the pool still works with the rest.
      }
    }
    await Future.wait(
      pending.entries.map((entry) async {
        try {
          await entry.value.ready;
          _sockets[entry.key] = entry.value;
          unawaited(_dropWhenClosed(entry.key, entry.value));
        } on Exception {
          // Skip unreachable relay; the pool still works with the rest.
          unawaited(entry.value.close());
        }
      }),
    );
    _announceStatus();
  }

  /// Stops counting [url] as connected once [socket] is gone.
  ///
  /// Without this the pool reports a connection for the rest of the app's
  /// life after the phone loses its network -- and every publish onto it
  /// goes nowhere while the screen says "connected".
  Future<void> _dropWhenClosed(String url, RelaySocket socket) async {
    // `then` with an error handler rather than a try/catch: a socket that
    // closes *with* an error is closed all the same, and the error may not
    // be an `Exception` subtype, which an `on Exception` clause would let
    // escape into an unhandled async error.
    await socket.done.then<void>((_) {}, onError: (Object _) {});
    // Identity, not just presence: a later `connectAll` may already have
    // put a *new* socket under this url, and that one is still live.
    if (!identical(_sockets[url], socket)) return;
    _sockets.remove(url);
    _announceStatus();
  }

  /// Sends [e] as a NIP-01 `["EVENT", <event>]` frame to every connected
  /// relay, and returns **how many relays it was actually handed to**.
  ///
  /// Zero is the answer that matters: with no relay connected this call
  /// does nothing, and used to do nothing *silently* -- the passenger page
  /// mined proof-of-work, signed a ride request, "published" it and moved
  /// on to waiting for offers that could never arrive. The count is the
  /// minimum honesty this layer can offer; a caller that ignores it is
  /// choosing to, rather than being unable to tell.
  ///
  /// It deliberately does **not** throw. Publishing runs on paths that must
  /// not blow up mid-trip -- live location pings, trip status DMs, the
  /// end-of-ride receipt -- and turning a quiet no-op into an exception
  /// there would trade a misleading screen for a broken ride. Refusing to
  /// publish is a decision for the screen that has a user in front of it
  /// (see [RelayStatus.isOffline]), not for the transport.
  Future<int> publish(NostrEvent e) async {
    final frame = jsonEncode(['EVENT', e.toJson()]);
    final sockets = _sockets.values.toList();
    for (final socket in sockets) {
      socket.send(frame);
    }
    return sockets.length;
  }

  /// Opens a `["REQ", subId, filter]` subscription against every connected
  /// relay and merges the results into one stream, deduped by event id
  /// *within this subscription* and filtered to signature-verified events.
  ///
  /// The dedup set belongs to the subscription, never to the pool. What it
  /// exists for is one event arriving from four relays at once; what a
  /// pool-wide set did instead was let any two subscriptions starve each
  /// other. Two `RelayFilter`s can legitimately match the same event -- the
  /// driver inbox watches gift wraps for handoffs and, since spec §7.5,
  /// for cancellations -- and a relay answers each `REQ` separately, so the
  /// same event id arrives once per subscription by design. With one shared
  /// set the first frame marked the id seen and every later subscription's
  /// copy was dropped in silence: whichever `REQ` went out first received
  /// everything and the others received nothing, forever. That is not a
  /// duplicate being suppressed, it is a feature being switched off.
  ///
  /// Per-subscription is also the tighter bound on memory: the set dies
  /// with its subscription instead of accumulating for the app's lifetime.
  Stream<NostrEvent> subscribe(RelayFilter f) {
    final subId = 'takhi-${_subCounter++}';
    final controller = StreamController<NostrEvent>.broadcast();
    final subscriptions = <StreamSubscription<String>>[];
    final reqFrame = jsonEncode(['REQ', subId, f.toJson()]);
    // A plain `Set<String>` literal is a [LinkedHashSet] in Dart, which
    // preserves insertion order -- relied on in [_handleMessage] for FIFO
    // eviction (`.first` is always the oldest-inserted, still-present id).
    final seenEventIds = <String>{};

    for (final socket in _sockets.values) {
      socket.send(reqFrame);
      subscriptions.add(
        socket.messages.listen(
          (raw) => _handleMessage(raw, subId, controller, seenEventIds),
        ),
      );
    }

    controller.onCancel = () async {
      for (final socket in _sockets.values) {
        socket.send(jsonEncode(['CLOSE', subId]));
      }
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }

  void _handleMessage(
    String raw,
    String subId,
    StreamController<NostrEvent> controller,
    Set<String> seenEventIds,
  ) {
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      if (decoded.isEmpty || decoded[0] != 'EVENT') return;
      // NIP-01 shape is ["EVENT", subId, event]. Every RelaySocket is
      // shared across all concurrent subscribe() calls (same underlying
      // per-URL socket, one listener per subscription), so the sub id must
      // be checked here to route each frame to the subscription it was
      // actually sent for and ignore frames belonging to other
      // subscriptions on the same socket.
      if (decoded.length < 3 || decoded[1] != subId) return;
      final m = decoded[2] as Map<String, dynamic>;
      final ev = NostrEvent(
        id: m['id'] as String?,
        pubkey: m['pubkey'] as String,
        createdAt: m['created_at'] as int,
        kind: m['kind'] as int,
        tags: (m['tags'] as List<dynamic>)
            .map((t) => (t as List<dynamic>).map((x) => x as String).toList())
            .toList(),
        content: m['content'] as String,
        sig: m['sig'] as String?,
      );
      if (ev.id == null || seenEventIds.contains(ev.id)) return;
      if (!verifyEvent(ev)) return;
      seenEventIds.add(ev.id!);
      // Unbounded growth here would leak memory for the app's entire
      // lifetime (every event id ever seen, forever) -- once over the
      // cap, drop the single oldest-inserted id so the set never holds
      // more than `_seenEventIdsCap` entries. A dropped id can in theory
      // be re-delivered as a "new" event later, but only after this many
      // *other* distinct ids have been seen in between -- an acceptable
      // trade against unbounded memory growth.
      if (seenEventIds.length > _seenEventIdsCap) {
        seenEventIds.remove(seenEventIds.first);
      }
      controller.add(ev);
    } on FormatException {
      // Malformed frame; ignore.
    } on TypeError {
      // Unexpected/missing field shape; ignore.
    }
  }

  /// Closes every relay socket and clears connection state.
  void dispose() {
    for (final socket in _sockets.values) {
      unawaited(socket.close());
    }
    _sockets.clear();
    // Closed *after* the sockets so a `_dropWhenClosed` woken by the
    // closes above finds the controller already shut and stays quiet --
    // there is no one left to tell.
    unawaited(_statusChanges.close());
  }
}
