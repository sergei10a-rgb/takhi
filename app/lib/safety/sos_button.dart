// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:takhi_protocol/takhi_protocol.dart';
import 'package:url_launcher/url_launcher.dart';

import '../geo/gps_fix.dart';
import '../l10n/app_localizations.dart';
import 'safety_providers.dart';
import 'sos_service.dart';

/// The always-visible SOS entry point wired into `ActiveTripView`'s
/// tracking step (Task 9's own final wiring step). Everything this
/// widget does is exactly one `url_launcher` call per action -- see
/// Global Constraints: SOS never requests `CALL_PHONE`/`SEND_SMS`, it
/// only builds `tel:`/`sms:` URIs (`sos_service.dart`) and hands them to
/// the OS, so the user's own finger presses the final send/call button
/// on their own device's own native app.
class SosButton extends ConsumerWidget {
  final GpsFix? lastFix;

  const SosButton({super.key, this.lastFix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return IconButton(
      icon: const Icon(Icons.emergency, color: Colors.red),
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
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.local_police, color: Colors.red),
            title: Text(l.sosCallPoliceAction),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(launchUrl(buildEmergencyDialUri(kPoliceNumber)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_hospital, color: Colors.red),
            title: Text(l.sosCallAmbulanceAction),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(launchUrl(buildEmergencyDialUri(kAmbulanceNumber)));
            },
          ),
          if (contactPhone != null && contactPhone.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.sms, color: Colors.red),
              title: Text(l.sosSendLocationSmsAction),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _sendLocationSms(contactPhone, l, lastFix);
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.person_add_alt, color: Colors.red),
              title: Text(l.sosNoContactHint),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  // `pop` is synchronous and this button lives inside the
                  // sheet, not the page, so `context` (the page's) is
                  // still mounted here today. Checked anyway: the guard
                  // costs nothing and stops a future refactor -- e.g.
                  // awaiting a confirmation before navigating -- from
                  // turning this into a use-after-dispose.
                  if (context.mounted) {
                    context.push('/settings/emergency-contact');
                  }
                },
                child: Text(l.sosAddContactAction),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Builds and launches the emergency `sms:` intent. When [lastFix] is
/// unavailable (e.g. tracking has not yet produced a fix, or the caller is
/// a screen that does not track at all), the body falls back to
/// [AppLocalizations.locationUnavailableHint] instead of a bogus Plus
/// Code/coordinate pair -- see Task 9's plan Step 7.
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
