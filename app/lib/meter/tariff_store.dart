// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shared_preferences/shared_preferences.dart';

/// Suggested starting values, offered when a driver has never set a price.
///
/// **These are a starting point, not a claim.** Nothing in the app may
/// describe them as the market rate, the correct rate, or the recommended
/// rate. The moment it does, two things follow: a passenger can point at
/// the app to argue a driver down once the market has moved past it, and
/// somebody becomes responsible for keeping the number current — which an
/// ownerless app cannot have. The number belongs to the driver who confirms
/// it, and the wording around it says exactly that.
///
/// Chosen to match what a working driver was measurably earning in
/// Ulaanbaatar in August 2026, reconstructed from a commercial meter's own
/// fare breakdown: 1,500₮ base + ~1,520₮/km + 150₮/min.
const int kSuggestedMntPerKm = 1500;
const int kSuggestedDurationMntPerMinute = 150;
const int kSuggestedWaitMntPerMinute = 150;

/// What a booked ride charges before it moves, covering the drive to the
/// passenger. That drive really happens, so the fee is honest.
const int kSuggestedBookingBaseMnt = 1500;

/// What a street hail charges before it moves. Zero, because there was no
/// drive to the passenger — they were already standing there.
///
/// A driver who wants a flag-fall adds one; traditional taxis have always
/// had one, and it is what stops an 800-metre trip from being not worth
/// stopping for. But charging for an approach that did not happen would be
/// a lie, so the app does not do it on anybody's behalf.
const int kSuggestedBoardingMnt = 0;

/// What the driver charges.
///
/// Five numbers, all theirs. The app fills the boxes in and never says the
/// figures are right.
class DriverTariff {
  final int mntPerKm;

  /// Charged for every minute the driver spends *waiting for the
  /// passenger* — not for sitting in traffic.
  ///
  /// Traffic is covered by [durationMntPerMinute], because a jam is part of
  /// the trip's duration. Waiting is a different thing: the meter is on, the
  /// passenger is not in the car yet or has asked the driver to hold, and
  /// the driver is earning nothing else. The two never run at once — see
  /// `MeterSession`.
  final int mntPerMinute;

  /// Charged for every minute of the trip itself, moving or stopped.
  ///
  /// This is the rate that was missing. It defaulted to zero and no screen
  /// ever mentioned it, so a driver ran a nineteen-minute ride and lost
  /// 2,850₮ without knowing the field existed. The zero was not the bug;
  /// the invisibility was.
  final int durationMntPerMinute;

  /// Flag-fall for a street hail, charged once when the meter starts.
  final int boardingMnt;

  /// Base fare for a booked ride, covering the drive to the passenger.
  final int bookingBaseMnt;

  /// The least the driver will run the meter for: a floor the whole fare is
  /// lifted to when the metered charges fall short of it.
  ///
  /// Zero — the default — means no floor, and a tariff saved before this
  /// rate existed keeps behaving exactly as it did. When set, it is applied
  /// as a visible top-up row (`MeterSession.minimumFareTopUpMnt`) rather
  /// than by silently flooring the total, so the fare's rows still add up to
  /// the number paid.
  final int minFareMnt;

  /// Distance included in the base fare before the km-tariff bills, in
  /// metres. Zero — the default — bills from the first metre, exactly as
  /// every tariff saved before this existed.
  ///
  /// It buys two things. A short hop is the base fare, not the base plus a
  /// few tögrög of awkward change. And the metre or two of GPS drift a
  /// parked car accretes before it pulls away never lands on the passenger
  /// as a charge. It does not add a row — it shrinks the distance the
  /// km-tariff is charged on (`fare_calc.computeFareMnt`), so the breakdown
  /// still sums to the total. A driver who wants neither leaves it at zero.
  final int freeDistanceMeters;

  /// Time included in the base fare before the duration-tariff bills, in
  /// seconds. Zero — the default — bills from the first second.
  ///
  /// The time counterpart of [freeDistanceMeters]: a minute of settling in
  /// at the kerb, or a short hold at a light, does not turn a base fare into
  /// base-plus-loose-change. Shrinks the duration share rather than adding a
  /// row. Opt-in like the rest.
  final int freeDurationSeconds;

  const DriverTariff({
    required this.mntPerKm,
    this.mntPerMinute = 0,
    this.durationMntPerMinute = 0,
    this.boardingMnt = 0,
    this.bookingBaseMnt = 0,
    this.minFareMnt = 0,
    this.freeDistanceMeters = 0,
    this.freeDurationSeconds = 0,
  });

  /// The values a driver is shown the first time, before they change any.
  static const suggested = DriverTariff(
    mntPerKm: kSuggestedMntPerKm,
    mntPerMinute: kSuggestedWaitMntPerMinute,
    durationMntPerMinute: kSuggestedDurationMntPerMinute,
    boardingMnt: kSuggestedBoardingMnt,
    bookingBaseMnt: kSuggestedBookingBaseMnt,
  );

  DriverTariff copyWith({
    int? mntPerKm,
    int? mntPerMinute,
    int? durationMntPerMinute,
    int? boardingMnt,
    int? bookingBaseMnt,
    int? minFareMnt,
    int? freeDistanceMeters,
    int? freeDurationSeconds,
  }) => DriverTariff(
    mntPerKm: mntPerKm ?? this.mntPerKm,
    mntPerMinute: mntPerMinute ?? this.mntPerMinute,
    durationMntPerMinute: durationMntPerMinute ?? this.durationMntPerMinute,
    boardingMnt: boardingMnt ?? this.boardingMnt,
    bookingBaseMnt: bookingBaseMnt ?? this.bookingBaseMnt,
    minFareMnt: minFareMnt ?? this.minFareMnt,
    freeDistanceMeters: freeDistanceMeters ?? this.freeDistanceMeters,
    freeDurationSeconds: freeDurationSeconds ?? this.freeDurationSeconds,
  );

  /// Compared by value: this is held in screen state and diffed against a
  /// freshly loaded copy, where identity comparison would silently report
  /// every load as a change.
  @override
  bool operator ==(Object other) =>
      other is DriverTariff &&
      other.mntPerKm == mntPerKm &&
      other.mntPerMinute == mntPerMinute &&
      other.durationMntPerMinute == durationMntPerMinute &&
      other.boardingMnt == boardingMnt &&
      other.bookingBaseMnt == bookingBaseMnt &&
      other.minFareMnt == minFareMnt &&
      other.freeDistanceMeters == freeDistanceMeters &&
      other.freeDurationSeconds == freeDurationSeconds;

  @override
  int get hashCode => Object.hash(
    mntPerKm,
    mntPerMinute,
    durationMntPerMinute,
    boardingMnt,
    bookingBaseMnt,
    minFareMnt,
    freeDistanceMeters,
    freeDurationSeconds,
  );

  @override
  String toString() =>
      'DriverTariff($mntPerKm₮/км, $mntPerMinute₮/мин хүлээлгэ, '
      '$durationMntPerMinute₮/мин хугацаа, $boardingMnt₮ суулт, '
      '$bookingBaseMnt₮ дуудлагын суурь, $minFareMnt₮ доод хязгаар, '
      '$freeDistanceMeters м үнэгүй зай, $freeDurationSeconds с үнэгүй хугацаа)';
}

/// The driver's own tariff, local-only. Plan 3 (spec §16, own
/// Self-Review open question #4) explicitly deferred the public kind-0
/// profile extension (car/plate/km-tariff) as not yet built — this store
/// is the taximeter's local-only stand-in for those fields, never published,
/// never part of any Nostr event.
abstract interface class TariffStore {
  Future<void> save(DriverTariff tariff);

  /// The saved tariff, or `null` when the driver has not set one yet — the
  /// state `TaximeterPage` shows its "set your rate" step for.
  Future<DriverTariff?> load();

  /// Whether the saved tariff predates a charge this version knows about,
  /// i.e. was written by a build that could not have asked about it.
  ///
  /// Separate from [load] because the two answer different questions. A
  /// missing charge reads back as zero either way; only this says whether
  /// the driver ever *chose* that zero. They must be asked once, because
  /// the alternative is what already happened — a rate nobody knew existed,
  /// quietly set to nothing, for 2,850₮ a ride.
  Future<bool> hasUnseenCharges();

  /// Records that the driver has now seen every charge this build has.
  Future<void> markChargesSeen();
}

class SharedPreferencesTariffStore implements TariffStore {
  /// Unchanged from when this store held nothing but a km-tariff, so an
  /// existing install keeps the rate its driver already typed.
  static const _kmKey = 'takhi_driver_tariff_mnt_per_km';
  static const _minuteKey = 'takhi_driver_tariff_mnt_per_minute';
  static const _durationMinuteKey =
      'takhi_driver_tariff_duration_mnt_per_minute';
  static const _boardingKey = 'takhi_driver_tariff_boarding_mnt';
  static const _bookingBaseKey = 'takhi_driver_tariff_booking_base_mnt';
  static const _minFareKey = 'takhi_driver_tariff_min_fare_mnt';
  static const _freeDistanceKey = 'takhi_driver_tariff_free_distance_meters';
  static const _freeDurationKey = 'takhi_driver_tariff_free_duration_seconds';

  /// How many charges the driver has confirmed seeing.
  ///
  /// A count rather than a boolean so the next charge added to this class
  /// re-opens the question by itself. A boolean would be set once, in a
  /// build that knew about three rates, and would go on claiming the driver
  /// had seen five.
  static const _seenChargeCountKey = 'takhi_driver_tariff_seen_charges';

  /// How many charges whose *silent zero is a trap* this build has — the
  /// ones where a driver who never knew the field existed loses money
  /// without a screen ever saying so. That was the duration rate: it
  /// defaulted to zero, no screen mentioned it, and a real ride lost 2,850₮.
  /// The five are km, waiting, duration, boarding and booking-base.
  ///
  /// Deliberately NOT bumped by the minimum-fare or the free-distance/
  /// free-duration boxes, even though each has its own field and its own
  /// row. Their zero is not a trap — it is the traditional meter: no floor,
  /// and billed from the first metre and second, which is exactly what a
  /// driver who ignores them expects. Re-opening the "unseen charges" review
  /// for a safe default would be noise, so a driver is asked about it only
  /// when a genuinely-missable charge is added.
  static const _chargeCount = 5;

  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesTariffStore(this._prefs);

  @override
  Future<void> save(DriverTariff tariff) async {
    final prefs = await _prefs();
    await prefs.setInt(_kmKey, tariff.mntPerKm);
    await prefs.setInt(_minuteKey, tariff.mntPerMinute);
    await prefs.setInt(_durationMinuteKey, tariff.durationMntPerMinute);
    await prefs.setInt(_boardingKey, tariff.boardingMnt);
    await prefs.setInt(_bookingBaseKey, tariff.bookingBaseMnt);
    await prefs.setInt(_minFareKey, tariff.minFareMnt);
    await prefs.setInt(_freeDistanceKey, tariff.freeDistanceMeters);
    await prefs.setInt(_freeDurationKey, tariff.freeDurationSeconds);
  }

  @override
  Future<DriverTariff?> load() async {
    final prefs = await _prefs();
    final mntPerKm = prefs.getInt(_kmKey);
    // The km-tariff alone decides whether a tariff exists at all: it is the
    // one a run cannot be metered without, and the only one every version
    // of the app has written.
    if (mntPerKm == null) return null;
    return DriverTariff(
      mntPerKm: mntPerKm,
      mntPerMinute: prefs.getInt(_minuteKey) ?? 0,
      durationMntPerMinute: prefs.getInt(_durationMinuteKey) ?? 0,
      boardingMnt: prefs.getInt(_boardingKey) ?? 0,
      bookingBaseMnt: prefs.getInt(_bookingBaseKey) ?? 0,
      minFareMnt: prefs.getInt(_minFareKey) ?? 0,
      freeDistanceMeters: prefs.getInt(_freeDistanceKey) ?? 0,
      freeDurationSeconds: prefs.getInt(_freeDurationKey) ?? 0,
    );
  }

  @override
  Future<bool> hasUnseenCharges() async {
    final prefs = await _prefs();
    if (prefs.getInt(_kmKey) == null) return false; // nothing saved yet
    return (prefs.getInt(_seenChargeCountKey) ?? 0) < _chargeCount;
  }

  @override
  Future<void> markChargesSeen() async {
    final prefs = await _prefs();
    await prefs.setInt(_seenChargeCountKey, _chargeCount);
  }
}

/// Test double, mirrors `InMemoryKeyStore` (`identity/identity_service.dart`).
class InMemoryTariffStore implements TariffStore {
  DriverTariff? _value;
  bool _seen = false;

  @override
  Future<void> save(DriverTariff tariff) async => _value = tariff;

  @override
  Future<DriverTariff?> load() async => _value;

  @override
  Future<bool> hasUnseenCharges() async => _value != null && !_seen;

  @override
  Future<void> markChargesSeen() async => _seen = true;
}
