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
      onPressed: () => _openSheet(context, ref),
    );
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
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
                  _sendLocationSms(contactPhone, l);
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
  /// unavailable (e.g. tracking has not yet produced a fix), the body
  /// falls back to [AppLocalizations.locationUnavailableHint] instead of
  /// a bogus Plus Code/coordinate pair -- see this task's plan Step 7.
  void _sendLocationSms(String contactPhone, AppLocalizations l) {
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
}
