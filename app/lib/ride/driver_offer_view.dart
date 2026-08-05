// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../home/home_status_row.dart' show shortenNpub;
import '../l10n/app_localizations.dart';
import '../meter/money_format.dart';
import '../theme/takhi_theme.dart';
import '../widgets/driver_portrait.dart';
import '../widgets/info_chip.dart';
import '../widgets/notice_card.dart';
import '../widgets/person_row.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/summary_row.dart';
import '../widgets/takhi_sheet.dart';
import 'metered_tariff_label.dart';
import 'offer_ranking.dart';
import 'ride_dm_payload.dart';

/// How many characters of a driver's `npub` the fallback avatar mark
/// carries when there is no name to cut one from.
///
/// Two, and they are the *first two of the key itself* rather than the first
/// two of the string: every npub begins `npub1`, so a mark taken off the
/// front would read "NP" for every driver on the list. Taken from after the
/// prefix it varies per driver and matches the head of the key printed on
/// their page, which is what makes it checkable rather than decorative.
const _kDriverMarkLength = 2;

/// Where the human-readable part of a bech32 `npub` starts: past the `npub`
/// prefix and its `1` separator.
const _kNpubDataOffset = 5;

/// Diameter of the portrait at the top of [DriverOfferPage].
///
/// Face-sized rather than avatar-sized, and comfortably past
/// [TakhiTouch.minTarget] so it can carry the "open it full screen" tap that
/// a row avatar cannot. Chosen against the job it does: this is the picture a
/// rider holds up against the person walking towards their car, and at row
/// size that comparison is guesswork.
const _kHeroPortraitSize = 96.0;

/// The two characters an avatar shows when there is no photograph.
///
/// Both halves of the name when there is a whole name -- «Б. Батбаяр» gives
/// «ББ» -- so two drivers who share a given name do not share a mark. With no
/// name (only possible from a client older than the field), the key's own
/// first two characters, which is the same string the driver's page prints.
String driverAvatarMark({
  required RideOfferPayload payload,
  required String npub,
}) {
  if (payload.driverFullName != null) {
    final family = _firstCharacter(payload.driverFamilyName);
    final given = _firstCharacter(payload.driverGivenName);
    if (family.isNotEmpty && given.isNotEmpty) return '$family$given';
  }
  if (npub.length < _kNpubDataOffset + _kDriverMarkLength) {
    return npub.toUpperCase();
  }
  return npub
      .substring(_kNpubDataOffset, _kNpubDataOffset + _kDriverMarkLength)
      .toUpperCase();
}

/// The first *rune* of [text], uppercased -- never `text[0]`, which would
/// slice a surrogate pair in half and render as a replacement glyph.
String _firstCharacter(String? text) {
  final trimmed = text?.trim() ?? '';
  return trimmed.isEmpty ? '' : trimmed.characters.first.toUpperCase();
}

/// What a driver's reputation is called on screen.
///
/// Stated as trips *and the people behind them*, never as the score the offer
/// list sorts by. `trustWeight` is a damped, web-of-trust-weighted figure
/// (spec §9) that means nothing to a rider standing on a kerb; "eleven trips
/// both sides signed off on, with seven different people" is what it is
/// computed from, and the one they can actually weigh.
///
/// Both halves, because the trip count alone is the half that is cheapest to
/// inflate: one pubkey rating the same driver eleven times reads identically
/// to eleven riders doing it once. `trustWeight` already damps that (see
/// `computeReputation`), but a rider cannot see damping -- they can see two
/// numbers that do not match.
///
/// A driver with no history is *named as new* rather than reported as
/// lacking something. The wording is not politeness: every driver on this
/// network starts at zero, and a list where newcomers read as suspects has
/// no second driver on it.
String driverReputationLabel(
  AppLocalizations l,
  Reputation reputation, {
  bool viewerTrusts = false,
}) =>
    switch (reputationTier(reputation, viewerTrusts: viewerTrusts)) {
      // A deliberate vouch is the one standing that outranks the trip
      // summary: a returning rider should read "someone you trust" before
      // they read a count they no longer need.
      ReputationTier.trusted => l.driverTrustedByYouLabel,
      ReputationTier.none => l.driverNewLabel,
      ReputationTier.newcomer ||
      ReputationTier.established =>
        l.driverReputationSummaryLabel(
          reputation.pairedTripCount,
          reputation.distinctCounterpartyCount,
        ),
    };

/// Who is offering, as a row: their face, their name, and what standing they
/// have.
///
/// The name is the driver's own овог and нэр, which arrive inside the
/// gift-wrapped offer and nowhere else (see
/// `RideOfferPayload.driverFamilyName`). This row used to lead with the
/// shortened npub, which is a true statement about a key and a useless one
/// about a person: nobody remembers `npub1q7f…k2m9`, and a rider comparing
/// two offers was comparing two strings of noise. The key has not been
/// thrown away -- it moved to [DriverOfferPage], where a careful rider can
/// still read it.
///
/// The portrait degrades to an initials mark rather than to a blank, and a
/// name that never arrived is *named* as missing rather than quietly
/// replaced by the key: "this driver's app sent no name" is itself a fact
/// worth having.
class DriverIdentityRow extends StatelessWidget {
  final RankedRideOffer ranked;
  final Widget? trailing;

  /// Whether the viewer has personally vouched for this driver (the "I trust
  /// this driver" tick, stored locally). When true the standing line reads
  /// "a driver you trust" instead of the trip summary — the one fact a
  /// returning rider wants first and cannot get from a count.
  final bool viewerTrusts;

  /// Opens the driver's page. Null makes the row a plain statement -- which
  /// is what it is on that page itself, and on the "driver on the way"
  /// summary, where there is nothing further to open.
  final VoidCallback? onTap;

  const DriverIdentityRow({
    super.key,
    required this.ranked,
    this.trailing,
    this.viewerTrusts = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final reputation = ranked.reputation;
    final trips = reputation.pairedTripCount;
    final payload = ranked.offer.payload;
    final npub = hexToNpub(ranked.offer.driverPubkey);
    final photo = payload.driverPhotoBytes;

    return PersonRow(
      name: payload.driverFullName ?? l.offerDriverNameUnknown,
      initials: driverAvatarMark(payload: payload, npub: npub),
      avatar: photo == null ? null : MemoryImage(photo),
      rating: trips == 0 ? null : reputation.averageRating,
      subtitle: driverReputationLabel(l, reputation, viewerTrusts: viewerTrusts),
      // Colour carries the same fact the words do: gold is this app's trust
      // colour, so a driver the rider has vouched for wears it; steppe is the
      // "confirmed, established" family; neutral says a driver has no history
      // yet rather than a bad one.
      accent: viewerTrusts
          ? TakhiAccent.gold
          : trips == 0
          ? TakhiAccent.neutral
          : TakhiAccent.steppe,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// What the offer costs and what turns up for it.
///
/// The fare is the one large figure because it is the number being compared
/// down the list; everything qualifying it -- how soon, which car, what the
/// meter charges -- is a chip, which is how this app writes metadata
/// everywhere else.
class OfferTerms extends StatelessWidget {
  final RideOfferPayload payload;

  /// Whether to repeat the vehicle here. False where the screen has already
  /// named it in its heading: printing "мөнгөлөг Toyota Alphard" twice on
  /// one short screen reads as a fault, not as emphasis.
  final bool showVehicle;

  const OfferTerms({super.key, required this.payload, this.showVehicle = true});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final kmTariffMnt = payload.kmTariffMnt;
    final durationTariffLabel = meteredDurationTariffLabel(
      l,
      payload.durationTariffMntPerMinute,
    );

    // Spec §7.2/§7.4: a metered offer is not one price but two rates, and
    // the offer list is where the rider chooses between drivers. Both rates
    // therefore sit on the card itself -- never behind the confirm dialog,
    // never derived after the trip. `null` is a plain fixed-price offer,
    // which stays the single figure it has always been: quoting rates
    // beside it would describe charges that never apply.
    final qualifiers = <Widget>[
      if (showVehicle)
        InfoChip(
          icon: Icons.directions_car_filled_outlined,
          label: payload.vehicleDescription,
        ),
      if (kmTariffMnt != null)
        InfoChip(
          icon: Icons.speed_outlined,
          label: meteredTariffLabel(
            l,
            kmTariffMnt: kmTariffMnt,
            waitTariffMntPerMinute: payload.waitTariffMntPerMinute,
          ),
          accent: TakhiAccent.gold,
        ),
      // The third rate as its own chip rather than a third clause in the one
      // above. All three in a single label overran the card's width and
      // ellipsed, and what a chip drops off its right-hand end is the last
      // rate's name -- leaving a bare figure the rider cannot attribute. The
      // `Wrap` below puts this on its own line instead, which is what the
      // taximeter's tariff pills already do for the same reason. Absent
      // whenever the trip's duration is free, which is nearly every offer.
      if (kmTariffMnt != null && durationTariffLabel != null)
        InfoChip(
          icon: Icons.timer_outlined,
          label: durationTariffLabel,
          accent: TakhiAccent.gold,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.meterFareLabel(groupedMnt(payload.priceMnt)),
                style: TakhiType.numeric.copyWith(color: surfaces.onSheet),
              ),
            ),
            InfoChip(
              icon: Icons.schedule_outlined,
              label: l.offerEtaLabel(payload.etaMinutes),
              accent: TakhiAccent.steppe,
            ),
          ],
        ),
        if (qualifiers.isNotEmpty) ...[
          const SizedBox(height: TakhiSpace.xs),
          Wrap(
            spacing: TakhiSpace.xs,
            runSpacing: TakhiSpace.xs,
            children: qualifiers,
          ),
        ],
      ],
    );
  }
}

/// The driver, at the size a rider decides at.
///
/// Opened by tapping an offer, and it exists because the tap used to go
/// straight to "send this stranger your exact address, yes/no". The list
/// row can hold a face the size of a thumbnail and one line of standing;
/// this page holds the face at face size, the whole name, the car, both
/// tariffs, the key, and -- the part no other screen can carry -- the plain
/// statement of what the portrait does and does not prove.
///
/// It answers with `true` for "I choose this driver" and with nothing at all
/// for every other way out, including the system back gesture. The
/// irreversible step is deliberately *not* here: the caller still raises the
/// existing confirmation before an exact pickup point leaves the device, so
/// a stray tap on this page's own button costs a dialog rather than an
/// address.
class DriverOfferPage extends StatelessWidget {
  final RankedRideOffer ranked;

  const DriverOfferPage({super.key, required this.ranked});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final payload = ranked.offer.payload;
    final photo = payload.driverPhotoBytes;

    return Scaffold(
      backgroundColor: surfaces.canvas,
      appBar: AppBar(
        // Flat in both senses, matching every other page in the ride flow:
        // no tint, and no colour change when content scrolls under it.
        backgroundColor: surfaces.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        // The action sheet at the foot adds the system gesture inset
        // itself; consuming it here as well would pad it twice.
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  TakhiSpace.md,
                  0,
                  TakhiSpace.md,
                  TakhiSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DriverHero(ranked: ranked),
                    const SizedBox(height: TakhiSpace.lg),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: surfaces.field,
                        borderRadius: TakhiRadius.cardAll,
                        border: Border.all(color: surfaces.hairline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(TakhiSpace.md),
                        child: OfferTerms(payload: payload),
                      ),
                    ),
                    const SizedBox(height: TakhiSpace.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      // Outlined rather than tinted: the key is the quietest
                      // fact on the page, and the only one a rider reads
                      // when something has already gone wrong.
                      child: InfoChip(
                        icon: Icons.key_outlined,
                        label: shortenNpub(
                          hexToNpub(ranked.offer.driverPubkey),
                        ),
                        tinted: false,
                      ),
                    ),
                    const SizedBox(height: TakhiSpace.lg),
                    // After the terms and the key, before the caveat about
                    // the photograph. The order is the argument the page
                    // makes: here is who and what it costs, here is the
                    // evidence for the who, and here is what that evidence
                    // does *not* cover.
                    _ReputationBreakdown(reputation: ranked.reputation),
                    if (photo != null) ...[
                      const SizedBox(height: TakhiSpace.lg),
                      // The whole reason this page exists. Said as a notice
                      // rather than as a footnote, because a rider who
                      // trusts a verification that does not exist is worse
                      // off than one who knows the picture is unchecked.
                      NoticeCard(
                        icon: Icons.info_outline,
                        text: l.driverPhotoUnverifiedHint,
                        accent: TakhiAccent.clay,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            TakhiSheet(
              showHandle: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    label: l.offerDriverSelectAction,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: TakhiSpace.xs),
                  SecondaryButton(
                    label: l.backAction,
                    // Pops with nothing rather than with `false`: "did not
                    // choose" is one answer however it was reached, and the
                    // caller reads anything that is not `true` as such.
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How many milliseconds a receipt's `created_at` second is worth. Named
/// because `* 1000` beside a timestamp is the kind of arithmetic that is
/// silently wrong by three orders of magnitude.
const _kMillisecondsPerSecond = 1000;

/// What the driver's standing is actually made of, taken apart.
///
/// The offer card can only afford one line, and one line has to be a summary.
/// This is the screen with room to answer the follow-up questions a summary
/// raises -- how many trips, from how many *different* people, accumulating
/// since when -- and, in one sentence, why any of it is trustworthy at all.
///
/// That sentence is the whole point of the block. Every other app's star
/// rating is a number a company asserts; this one is a count of receipts two
/// people separately signed. A rider who does not know that difference has no
/// reason to weigh these numbers any differently from the ones they have
/// learned to ignore.
///
/// A driver with no history gets the same block with the opposite sentence.
/// The alternative -- hiding it -- would leave the one screen that explains
/// the reputation system invisible to exactly the riders being asked to take
/// a chance on somebody without one.
class _ReputationBreakdown extends StatelessWidget {
  final Reputation reputation;

  const _ReputationBreakdown({required this.reputation});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final trips = reputation.pairedTripCount;
    final since = reputation.firstPairedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(compact: true, title: l.driverReputationHeading),
        const SizedBox(height: TakhiSpace.sm),
        if (trips > 0) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: surfaces.field,
              borderRadius: TakhiRadius.cardAll,
              border: Border.all(color: surfaces.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(TakhiSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SummaryRow(
                    label: l.driverReputationTripsRow,
                    value: '$trips',
                  ),
                  const SizedBox(height: TakhiSpace.xs),
                  SummaryRow(
                    label: l.driverReputationPeopleRow,
                    value: '${reputation.distinctCounterpartyCount}',
                  ),
                  // A sentence under the column rather than a third
                  // [SummaryRow]. That component sets its value in
                  // [TakhiType.numeric] -- the 20pt tabular face built for
                  // amounts -- and a whole date phrase in it came out
                  // shouting over the two figures it was meant to qualify.
                  // Dropped entirely, not shown as a dash, when the receipts
                  // carry no usable timestamp: a placeholder value teaches a
                  // reader to skip the line.
                  if (since != null) ...[
                    const SizedBox(height: TakhiSpace.xs),
                    Text(
                      _sinceLabel(l, since),
                      style: TakhiType.support.copyWith(color: surfaces.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: TakhiSpace.sm),
          NoticeCard(
            icon: Icons.handshake_outlined,
            text: l.driverPairedReceiptExplanation,
            accent: TakhiAccent.steppe,
          ),
        ] else
          NoticeCard(
            icon: Icons.eco_outlined,
            // Sky, not clay: a driver with no history yet is a plain fact
            // about the network's age, not a caveat about this person.
            text: l.driverNewExplanation,
            accent: TakhiAccent.sky,
          ),
      ],
    );
  }

  /// The month the oldest paired receipt was signed in, as a sentence.
  ///
  /// A month rather than a day, and deliberately: "building up since July
  /// 2023" is the resolution at which "how long has this been going on" is a
  /// real question, and a to-the-day date invites a rider to compute an age
  /// nobody was asking them for.
  static String _sinceLabel(AppLocalizations l, int unixSeconds) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * _kMillisecondsPerSecond,
    );
    return l.driverReputationSinceLine(at.year, at.month);
  }
}

/// The face, the name, and the two chips that qualify them.
class _DriverHero extends StatelessWidget {
  final RankedRideOffer ranked;

  const _DriverHero({required this.ranked});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final payload = ranked.offer.payload;
    final reputation = ranked.reputation;
    final trips = reputation.pairedTripCount;
    final photo = payload.driverPhotoBytes;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DriverPortrait(
          jpegBytes: photo,
          initials: driverAvatarMark(
            payload: payload,
            npub: hexToNpub(ranked.offer.driverPubkey),
          ),
          size: _kHeroPortraitSize,
          accent: trips == 0 ? TakhiAccent.neutral : TakhiAccent.steppe,
          enlargeable: true,
        ),
        const SizedBox(width: TakhiSpace.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payload.driverFullName ?? l.offerDriverNameUnknown,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TakhiType.heading.copyWith(color: surfaces.onSheet),
              ),
              const SizedBox(height: TakhiSpace.xxs),
              Text(
                driverReputationLabel(l, reputation),
                style: TakhiType.support.copyWith(color: surfaces.muted),
              ),
              const SizedBox(height: TakhiSpace.xs),
              Wrap(
                spacing: TakhiSpace.xs,
                runSpacing: TakhiSpace.xxs,
                children: [
                  if (trips > 0)
                    InfoChip(
                      icon: Icons.star_rounded,
                      label: reputation.averageRating.toStringAsFixed(1),
                      accent: TakhiAccent.gold,
                    ),
                  // Clay for "attention without alarm" when there is a photo
                  // to caveat; neutral when there is none, because "no
                  // picture arrived" is a plain absence rather than a
                  // warning about what did arrive.
                  if (photo == null)
                    InfoChip(
                      icon: Icons.no_photography_outlined,
                      label: l.driverPhotoMissingLabel,
                    )
                  else
                    InfoChip(
                      icon: Icons.info_outline,
                      label: l.driverPhotoUnverifiedBadge,
                      accent: TakhiAccent.clay,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
