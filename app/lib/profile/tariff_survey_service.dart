// SPDX-License-Identifier: AGPL-3.0-or-later

/// Reads other drivers' published tariffs off the relays.
///
/// One short subscription, taken when a driver opens their own tariff form
/// and dropped as soon as it answers. Not a standing feed: the figure is
/// read once, while somebody is deciding what to charge, and a background
/// subscription that ran all shift would cost battery for a number nobody
/// is looking at.
library;

import 'dart:async';

import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';
import 'tariff_survey.dart';

/// How long to listen before answering with whatever arrived.
///
/// Short. The caller is a driver looking at a form, and a survey that takes
/// ten seconds to appear is a survey they have already scrolled past.
const Duration kTariffSurveyWindow = Duration(seconds: 3);

/// How many profiles to ask each relay for.
const int kTariffSurveyLimit = 200;

/// A survey in flight, and the way to abandon it.
///
/// The handle exists because the survey holds a three-second timer, and a
/// timer that outlives the screen that wanted it is a leak on a phone and a
/// hung test in `flutter test`. A driver who closes the tariff form after
/// half a second is not waiting for an answer, so nothing should still be
/// waiting to give them one.
class TariffSurveyHandle {
  final Future<TariffSurvey?> result;
  final void Function() cancel;

  const TariffSurveyHandle({required this.result, required this.cancel});
}

class TariffSurveyService {
  final RelayPool _pool;

  const TariffSurveyService(this._pool);

  /// Starts a survey and hands back the way to stop it.
  TariffSurveyHandle start({String? excludePubkey}) {
    final abort = Completer<void>();
    return TariffSurveyHandle(
      result: survey(excludePubkey: excludePubkey, abort: abort.future),
      cancel: () {
        if (!abort.isCompleted) abort.complete();
      },
    );
  }

  /// Surveys published driver profiles, or returns `null` when too few
  /// arrived to say anything — see [summariseTariffs].
  ///
  /// [excludePubkey] is the driver doing the asking: a survey that included
  /// their own rate would move towards whatever they last typed and quietly
  /// tell them they were right.
  Future<TariffSurvey?> survey({
    String? excludePubkey,
    Future<void>? abort,
  }) async {
    // Nothing to survey with no relay attached, and — just as important —
    // no three-second timer left running for an answer that cannot arrive.
    // A timer outliving the screen that wanted it is a leak on a phone and
    // a hung test in `flutter test`, and this is a courtesy on a form that
    // works perfectly without it.
    if (_pool.status.connectedCount == 0) return null;

    final tariffs = <String, int>{};
    final done = Completer<void>();
    late final StreamSubscription<NostrEvent> subscription;

    subscription = _pool
        .subscribe(
          const RelayFilter(kinds: [0], limit: kTariffSurveyLimit),
        )
        .listen((event) {
          if (event.pubkey == excludePubkey) return;
          try {
            final profile = parseDriverProfile(event);
            // Keyed by author, so a driver who republished their profile
            // five times counts once. Without this a single busy driver
            // could carry the median on their own.
            tariffs[event.pubkey] = profile.kmTariffMnt;
          } on FormatException {
            // A kind-0 event that is not one of ours. The relays carry
            // everybody's profiles, so this is the common case, not an
            // error worth recording.
          }
        }, onError: (Object _) {});

    final timer = Timer(kTariffSurveyWindow, () {
      if (!done.isCompleted) done.complete();
    });
    unawaited(
      abort?.then((_) {
        if (!done.isCompleted) done.complete();
      }),
    );

    try {
      await done.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
    return summariseTariffs(tariffs.values);
  }
}
