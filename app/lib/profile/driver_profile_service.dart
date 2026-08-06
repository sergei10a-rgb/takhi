// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:takhi_protocol/takhi_protocol.dart';

import '../nostr/relay_pool.dart';
import 'driver_profile_store.dart';

/// How long [DriverProfileService.fetchPublishedProfile] listens for the
/// driver's own published profile before giving up.
///
/// Short on purpose. The caller is a driver staring at a blank registration
/// form the instant after restoring their seed on a new phone, and a fetch
/// that takes ten seconds is one they have already given up on and started
/// retyping over. Mirrors `kTariffSurveyWindow`'s reasoning
/// (`tariff_survey_service.dart`), one second longer because getting a
/// driver's own car and rates back is worth a moment more than glancing at
/// what other drivers charge.
const Duration kPublishedProfileWindow = Duration(seconds: 4);

/// Builds, signs, and publishes the driver's public kind-0 profile (spec
/// §6/§7.2), and keeps a local copy so `DriverProfilePage` and the §7.2
/// pricing-mode flow can read it without a relay round trip. Mirrors
/// `TripReceiptRepository.publish`'s build-sign-publish shape.
class DriverProfileService {
  final RelayPool _pool;
  final DriverProfileStore _store;
  DriverProfileService(this._pool, this._store);

  /// Publishes the vehicle-and-price half to every connected relay, and
  /// saves the whole profile -- names included -- locally.
  ///
  /// The asymmetry is the point, not an oversight. [familyName] and
  /// [givenName] are written to [_store] and go no further: a kind-0 event
  /// is world-readable and replicated forever, so a name published there is
  /// a name anyone can harvest against a pubkey that also carries this
  /// driver's plate number and, while they are working, a live geohash. The
  /// name reaches a passenger through the NIP-17 gift-wrapped offer
  /// instead, one passenger at a time, and only after that passenger asked
  /// for a ride the driver chose to answer.
  ///
  /// `buildDriverProfile` has no `name:` parameter at all, so this is
  /// enforced by the protocol layer rather than by remembering not to pass
  /// one here.
  Future<void> publishAndSave({
    required String privHex,
    required int now,
    required String car,
    required String color,
    required String plate,
    required int kmTariffMnt,
    String? familyName,
    String? givenName,
    int waitTariffMntPerMinute = 0,
    int durationTariffMntPerMinute = 0,
  }) async {
    final pubHex = pubkeyFromPrivate(privHex);
    final unsigned = buildDriverProfile(
      pubkey: pubHex,
      now: now,
      car: car,
      color: color,
      plate: plate,
      kmTariffMnt: kmTariffMnt,
      waitTariffMntPerMinute: waitTariffMntPerMinute,
      durationTariffMntPerMinute: durationTariffMntPerMinute,
    );
    final signed = signEvent(unsigned, privHex);
    await _pool.publish(signed);
    await _store.save(
      DriverProfile(
        familyName: familyName,
        givenName: givenName,
        car: car,
        color: color,
        plate: plate,
        kmTariffMnt: kmTariffMnt,
        waitTariffMntPerMinute: waitTariffMntPerMinute,
        durationTariffMntPerMinute: durationTariffMntPerMinute,
      ),
    );
  }

  /// Reads whatever profile was last saved locally -- either by this
  /// device's own `publishAndSave`, or pre-seeded for tests.
  Future<DriverProfile?> loadLocalProfile() => _store.load();

  /// Fetches the vehicle-and-tariff half of [pubHex]'s own profile back off
  /// the relays, or `null` if none arrives within [timeout].
  ///
  /// This is the other side of [publishAndSave]'s asymmetry. The local store
  /// is keyed to the install, not to the seed, so a driver who restores their
  /// 12-word seed on a fresh phone has no cached profile at all -- but the
  /// car, colour, plate and rates were published under their own pubkey as a
  /// kind-0 event, and those come back here to prefill the registration form.
  /// The returned [DriverProfile] therefore always has `familyName` and
  /// `givenName` null: the name was never on a relay to fetch, and returns
  /// only when the driver retypes it. `parseDriverProfile` enforces that --
  /// it does not even read a `name` the content might carry.
  ///
  /// Mirrors `TariffSurveyService.survey`: one short subscription, dropped
  /// the moment it answers, never a standing feed.
  Future<DriverProfile?> fetchPublishedProfile(
    String pubHex, {
    Duration timeout = kPublishedProfileWindow,
    Future<void>? abort,
  }) async {
    // Nothing to fetch with no relay attached, and -- just as important -- no
    // four-second timer left running for an answer that cannot arrive. A
    // timer outliving the blank form it was opened for is a leak on the phone
    // and a hung test in `flutter test`.
    if (_pool.status.connectedCount == 0) return null;

    DriverProfile? newest;
    int? newestCreatedAt;
    final done = Completer<void>();
    late final StreamSubscription<NostrEvent> subscription;

    subscription = _pool
        .subscribe(
          RelayFilter(
            kinds: const [kKindProfile],
            authors: [pubHex],
            limit: 1,
          ),
        )
        .listen(
          (event) {
            // The `authors` filter is the relay's job; a misbehaving one can
            // forward anybody's kind-0, so a profile that is not this
            // driver's own is not theirs to prefill from.
            if (event.pubkey != pubHex) return;
            try {
              final profile = parseDriverProfile(event);
              // A kind-0 is replaceable, so each relay holds one version, but
              // several relays can disagree on which is latest. Keep the one
              // the driver published most recently, not whichever frame
              // happened to land last.
              final createdAt = event.createdAt;
              if (newestCreatedAt == null || createdAt > newestCreatedAt!) {
                newest = profile;
                newestCreatedAt = createdAt;
              }
            } on FormatException {
              // A kind-0 that is not one of ours (a plain NIP-01 profile with
              // no takhi extension, say). The relays carry everybody's, so
              // this is expected, not an error worth recording.
            }
          },
          onError: (Object _) {},
        );

    final timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete();
    });
    // A driver who closes the registration form before the window is up is
    // not waiting for an answer; [abort] lets the page drop the timer and
    // subscription the moment it is disposed rather than leave them running
    // for the rest of the window. Same handle shape as `TariffSurveyService`.
    unawaited(
      abort?.then((_) {
        if (!done.isCompleted) done.complete();
      }),
    );

    try {
      await done.future;
    } finally {
      timer.cancel();
      // Fire-and-forget. By the time the window closes the answer is already
      // decided, so the caller -- a driver watching a blank form -- should
      // not wait on the relay CLOSE round-trip before it fills. The
      // subscription still tears down and its CLOSE still goes out as it
      // cancels; the result simply is not blocked on that.
      unawaited(subscription.cancel());
    }
    return newest;
  }

  /// Starts a [fetchPublishedProfile] and hands back the way to stop it, for
  /// a caller -- `DriverProfilePage` -- that must abandon the fetch when its
  /// screen goes away. Mirrors `TariffSurveyService.start`.
  DriverProfileFetchHandle startFetchPublishedProfile(
    String pubHex, {
    Duration timeout = kPublishedProfileWindow,
  }) {
    final abort = Completer<void>();
    return DriverProfileFetchHandle(
      result: fetchPublishedProfile(
        pubHex,
        timeout: timeout,
        abort: abort.future,
      ),
      cancel: () {
        if (!abort.isCompleted) abort.complete();
      },
    );
  }
}

/// A published-profile fetch in flight, and the way to abandon it. Exists for
/// the same reason `TariffSurveyHandle` does: the fetch holds a timer and a
/// relay subscription, and one that outlives the screen that opened it is a
/// leak on the phone and a hung test in `flutter test`.
class DriverProfileFetchHandle {
  final Future<DriverProfile?> result;
  final void Function() cancel;

  const DriverProfileFetchHandle({required this.result, required this.cancel});
}
