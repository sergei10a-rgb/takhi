// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi_protocol/takhi_protocol.dart';
import 'package:url_launcher/url_launcher.dart';

import '../geo/gps_fix.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/menu_row.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'safety_providers.dart';
import 'sos_service.dart';

/// Ceiling on the sheet's content, as a fraction of the screen. At the
/// default text scale the four rows never come near it; at 2x they would
/// otherwise run off the top, and this is the one surface in the app where
/// a row scrolled out of sight is a row somebody needed.
const _kSheetContentMaxFraction = 0.8;

/// The always-visible SOS entry point wired into `ActiveTripView`'s
/// tracking step. Everything this widget does is exactly one `url_launcher`
/// call per action -- see Global Constraints: SOS never requests
/// `CALL_PHONE`/`SEND_SMS`, it only builds `tel:`/`sms:` URIs
/// (`sos_service.dart`) and hands them to the OS, so the user's own finger
/// presses the final send/call button on their own device's own native app.
class SosButton extends ConsumerWidget {
  final GpsFix? lastFix;

  const SosButton({super.key, this.lastFix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return IconButton(
      // `colorScheme.error` rather than a flat `Colors.red`: the app's own
      // red is per-brightness, and the raw one clears 2.34:1 against the
      // dark surface this control sits on during a night trip.
      icon: Icon(Icons.emergency, color: Theme.of(context).colorScheme.error),
      tooltip: l.sosAction,
      onPressed: () => showSosActions(context, ref, lastFix: lastFix),
    );
  }
}

/// Opens the emergency action sheet: police, ambulance, and an SMS to the
/// user's own emergency contact carrying [lastFix] when there is one.
///
/// A function rather than a method on [SosButton] because the same sheet is
/// reached from two shapes of control -- the trip screen's icon button and
/// the home sheet's SOS service tile -- and duplicating the actions per call
/// site is exactly how one of them ends up missing the ambulance entry.
///
/// [lastFix] is the most recent position known to the *caller*: this
/// function never starts a GPS subscription of its own, so a screen that is
/// not already tracking (home) simply passes null and the SMS falls back to
/// [AppLocalizations.locationUnavailableHint] instead of a fabricated
/// coordinate.
///
/// ## Why it looks the way it does
///
/// This is the least-rehearsed surface in the app and the only one opened
/// mid-emergency, and it was three bare `ListTile`s with flat red squares on
/// an unheaded sheet. Three problems, all of which only matter in the one
/// second somebody actually uses it:
///
/// * **nothing said what a tap would do.** Тахь does not dial and does not
///   send: it hands a `tel:`/`sms:` URI to the OS and the user presses the
///   final button themselves. Somebody tapping "102" while frightened and
///   then finding a dialler rather than a ringing line has lost that second.
///   The heading says it once and each row says it again;
/// * **there was no way out.** A sheet with three irreversible-looking rows
///   and no dismiss invites a panicked back-swipe. "Болих" is now a row of
///   its own;
/// * **the rows were equally weighted and equally red**, so the only way to
///   pick one was to read all three. Each keeps a tinted disc from the
///   emergency colour family instead -- loud enough to be found, calm enough
///   not to be hit by accident.
Future<void> showSosActions(
  BuildContext context,
  WidgetRef ref, {
  GpsFix? lastFix,
}) async {
  final contactPhone = await ref
      .read(emergencyContactStoreProvider)
      .loadPhone();
  if (!context.mounted) return;
  final l = AppLocalizations.of(context)!;
  final hasContact = contactPhone != null && contactPhone.isNotEmpty;

  await showModalBottomSheet<void>(
    context: context,
    // The sheet paints itself -- [TakhiSheet] carries the fill, the rounded
    // top, the hairline and the bottom inset, so Material's own container
    // would only add a second surface behind the first.
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(
                title: l.sosSheetTitle,
                subtitle: l.sosSheetSubtitle,
                compact: true,
              ),
              const SizedBox(height: TakhiSpace.md),
              MenuRow(
                icon: Icons.local_police,
                label: l.sosCallPoliceAction,
                subtitle: l.sosDialHint,
                accent: TakhiAccent.clay,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(launchUrl(buildEmergencyDialUri(kPoliceNumber)));
                },
              ),
              const SizedBox(height: TakhiSpace.xs),
              MenuRow(
                icon: Icons.local_hospital,
                label: l.sosCallAmbulanceAction,
                subtitle: l.sosDialHint,
                accent: TakhiAccent.clay,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(launchUrl(buildEmergencyDialUri(kAmbulanceNumber)));
                },
              ),
              const SizedBox(height: TakhiSpace.xs),
              if (hasContact)
                MenuRow(
                  icon: Icons.sms,
                  label: l.sosSendLocationSmsAction,
                  subtitle: l.sosSmsHint,
                  accent: TakhiAccent.clay,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _sendLocationSms(contactPhone, l, lastFix);
                  },
                )
              else
                // Sky, not clay: this row is a detour into settings, not a
                // third way to call for help, and colouring it like one
                // would put a settings link in the emergency family. Not
                // neutral either -- that tint is the row's own fill, so the
                // disc would vanish and this row would be the only one on
                // the sheet without a mark.
                MenuRow(
                  icon: Icons.person_add_alt,
                  label: l.sosAddContactAction,
                  subtitle: l.sosNoContactHint,
                  accent: TakhiAccent.sky,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    // `pop` is synchronous and this row lives inside the
                    // sheet, not the page, so `context` (the page's) is
                    // still mounted here today. Checked anyway: the guard
                    // costs nothing and stops a future refactor -- e.g.
                    // awaiting a confirmation before navigating -- from
                    // turning this into a use-after-dispose.
                    if (context.mounted) {
                      context.push('/settings/emergency-contact');
                    }
                  },
                ),
              const SizedBox(height: TakhiSpace.sm),
              SecondaryButton(
                label: l.sosCancelAction,
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Builds and launches the emergency `sms:` intent. When [lastFix] is
/// unavailable (e.g. tracking has not yet produced a fix, or the caller is
/// a screen that does not track at all), the body falls back to
/// [AppLocalizations.locationUnavailableHint] instead of a bogus Plus
/// Code/coordinate pair.
void _sendLocationSms(
  String contactPhone,
  AppLocalizations l,
  GpsFix? lastFix,
) {
  final fix = lastFix;
  final uri = fix == null
      ? Uri(
          scheme: 'sms',
          path: contactPhone,
          queryParameters: {'body': 'SOS. ${l.locationUnavailableHint}'},
        )
      : buildEmergencySmsUri(
          contactPhone: contactPhone,
          plusCode: plusCodeEncode(fix.lat, fix.lon),
          lat: fix.lat,
          lon: fix.lon,
        );
  unawaited(launchUrl(uri));
}
