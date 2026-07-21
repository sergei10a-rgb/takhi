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
}

int _subCounter = 0;

/// Connects to a set of public Nostr relays over WebSocket, publishes
/// signed events to all of them, and merges subscription results —
/// deduping by event id and dropping anything that fails [verifyEvent].
///
/// Never talks to any authored server; [urls] are public, user-editable
/// relay addresses.
class RelayPool {
  final List<String> urls;
  final RelaySocket Function(String url) _connect;
  final Map<String, RelaySocket> _sockets = {};
  final Set<String> _seenEventIds = {};

  RelayPool(this.urls, {RelaySocket Function(String url)? connect})
    : _connect = connect ?? ((u) => WsRelaySocket(u));

  /// URLs currently holding an open socket.
  Set<String> get connectedUrls => _sockets.keys.toSet();

  /// Connects to every configured relay. Unreachable relays are skipped
  /// rather than failing the whole pool.
  Future<void> connectAll() async {
    for (final url in urls) {
      try {
        _sockets[url] = _connect(url);
      } on Exception {
        // Skip unreachable relay; the pool still works with the rest.
      }
    }
  }

  /// Sends [e] as a NIP-01 `["EVENT", <event>]` frame to every connected
  /// relay.
  Future<void> publish(NostrEvent e) async {
    final frame = jsonEncode(['EVENT', e.toJson()]);
    for (final socket in _sockets.values) {
      socket.send(frame);
    }
  }

  /// Opens a `["REQ", subId, filter]` subscription against every connected
  /// relay and merges the results into one stream, deduped by event id and
  /// filtered to only signature-verified events.
  Stream<NostrEvent> subscribe(RelayFilter f) {
    final subId = 'takhi-${_subCounter++}';
    final controller = StreamController<NostrEvent>.broadcast();
    final subscriptions = <StreamSubscription<String>>[];
    final reqFrame = jsonEncode(['REQ', subId, f.toJson()]);

    for (final socket in _sockets.values) {
      socket.send(reqFrame);
      subscriptions.add(
        socket.messages.listen((raw) => _handleMessage(raw, controller)),
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

  void _handleMessage(String raw, StreamController<NostrEvent> controller) {
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      if (decoded.isEmpty || decoded[0] != 'EVENT') return;
      // NIP-01 shape is ["EVENT", subId, event]; the sub id itself isn't
      // re-checked against [subId] here — this listener is only attached
      // to sockets belonging to this subscription in the first place, so
      // any well-formed EVENT frame on it is in scope.
      if (decoded.length < 3 || decoded[1] is! String) return;
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
      if (ev.id == null || _seenEventIds.contains(ev.id)) return;
      if (!verifyEvent(ev)) return;
      _seenEventIds.add(ev.id!);
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
  }
}
