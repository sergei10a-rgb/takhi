// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';

/// Folds a live stream of helper announcements into "latest-per-helperId,
/// still not expired" -- a small, explicitly mutable accumulator over a
/// live stream, the same documented-exception shape `GpsTrackAccumulator`
/// (Plan 4) and `RelayPool._sockets`/`_seenEventIds` (Plan 2) already
/// established for this codebase (Global Constraints).
class HelperDirectory {
  final Map<String, HelperAnnouncement> _byId = {};

  void add(HelperAnnouncement h) => _byId[h.helperId] = h;

  List<HelperAnnouncement> current({int Function() now = _systemNow}) =>
      _byId.values.where((h) => h.expiration > now()).toList();
}

/// Subscribes to every kind-30178 helper announcement currently visible on
/// the configured relays (spec §6 "Туслагч-зарлал") -- a live
/// subscription, not a one-shot snapshot, so a volunteer's relay coming
/// online (or an existing one's `expiration`, NIP-40, lapsing) is
/// reflected without restarting the app. A malformed or foreign kind-30178
/// event is silently dropped, matching every other `RelayPool.subscribe`
/// consumer's policy (`RideDmChannel.inbox`, `LiveLocationChannel.watch`)
/// of never surfacing untrusted-input parse failures as errors.
class HelperDirectoryService {
  final RelayPool _pool;
  HelperDirectoryService(this._pool);

  Stream<HelperAnnouncement> watchHelpers({int Function() now = _systemNow}) {
    final filter = RelayFilter(kinds: [kKindHelper]);
    return _pool.subscribe(filter).asyncExpand((event) async* {
      try {
        final helper = parseHelperAnnouncement(event);
        if (helper.expiration <= now()) return;
        yield helper;
      } on FormatException {
        // Malformed/foreign kind-30178 event; drop rather than surface.
      }
    });
  }
}

int _systemNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
