// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../config/city_config.dart';
import '../geo/geo_providers.dart';
import '../geo/gps_fix.dart';
import '../l10n/app_localizations.dart';
import '../map/ride_map.dart';
import '../safety/sos_button.dart';
import '../theme/takhi_theme.dart';
import '../widgets/address_row.dart';
import '../widgets/category_tile.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/pill_field.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'home_status_row.dart';
import 'home_top_bar.dart';

/// Zoom the map settles at once the rider's own position is known. Closer
/// than the city-wide default: a located rider wants to see their street,
/// not their district.
const _kLocatedZoom = 16.0;

/// Ceiling on the sheet's *content*, as a fraction of the screen.
///
/// The sheet hugs its content, and its content is a fixed list of rows, so
/// at the default text scale it never comes near this. At 1.5x-2x scale it
/// would otherwise grow past the top of the screen and take the map with
/// it; past this fraction the content scrolls inside the sheet instead,
/// which is the bounded-scrollable shape [TakhiSheet] documents.
const _kSheetContentMaxFraction = 0.72;

/// The app's home: a full-bleed map with everything else floating on it.
///
/// The structure is the one decision worth stating. Home is not a menu of
/// screens, it is a *map with a sheet on it* -- the same shape the rest of
/// the ride flow uses -- so arriving at a ride screen feels like the sheet
/// changed rather than like the app did. Three planes, back to front:
///
/// 1. the map, edge to edge, never boxed into a card;
/// 2. the floating controls -- brand, city, settings, recentre -- each its
///    own small capsule so the gaps between them stay see-through;
/// 3. the sheet, anchored to the bottom, holding everything the rider
///    operates.
///
/// The four service tiles replace what used to be a passenger/driver
/// segmented toggle plus one call-to-action underneath it. The toggle cost
/// a tap and, worse, hid half the app: the meter was invisible until you
/// had switched to driver mode. Every destination is now one tap from a
/// cold start, and each keeps its own accent colour so it is found by
/// colour rather than by reading four captions.
///
/// Location is asked for on demand, never on arrival. Home is the first
/// screen after onboarding, and a permission dialog fired at a rider who
/// has not yet asked for anything is both rude and easy to refuse
/// permanently -- so the map opens on the configured city and moves to the
/// rider only once they tap [AppLocalizations.homeLocateAction] (or the
/// pickup row, which is the same action with a bigger target).
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _mapController = MapController();

  /// Held so the one-shot locate can be cancelled: [LocationSource.watch]
  /// is a *continuous* stream, and dropping the reference after the first
  /// fix would leave the GPS radio running behind a screen nobody is
  /// looking at.
  StreamSubscription<GpsFix>? _fixSubscription;

  /// The rider's own position, once they have asked for it. Null until
  /// then -- and the pickup row says exactly that rather than implying a
  /// location the app does not have.
  GpsFix? _pickupFix;

  /// True once a locate attempt came back without permission. Kept apart
  /// from "no fix yet" because the two want different words: one is a
  /// prompt, the other is a refusal the rider has to resolve in system
  /// settings.
  bool _locationDenied = false;

  @override
  void dispose() {
    _fixSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Asks for location permission, then centres the map on the first fix
  /// that arrives and adopts it as the pickup point.
  Future<void> _locate() async {
    bool granted;
    try {
      granted = await ref.read(locationPermissionCheckProvider)();
    } on Exception {
      // The permission check reaches a platform channel, which is absent
      // under `flutter_test` and can fail on a device whose location
      // services are in a bad state. Neither is worth crashing home over:
      // treat it exactly like a refusal, which is what it amounts to.
      granted = false;
    }
    if (!mounted) return;
    if (!granted) {
      setState(() => _locationDenied = true);
      return;
    }

    await _fixSubscription?.cancel();
    _fixSubscription = ref.read(locationSourceProvider).watch().listen((fix) {
      unawaited(_fixSubscription?.cancel());
      _fixSubscription = null;
      if (!mounted) return;
      setState(() {
        _pickupFix = fix;
        _locationDenied = false;
      });
      _mapController.move(ll.LatLng(fix.lat, fix.lon), _kLocatedZoom);
    });
  }

  /// What the pickup row states right now: the Plus Code of the fix once
  /// there is one, the refusal once there has been one, and otherwise the
  /// invitation to go and get one.
  String _pickupValue(AppLocalizations l) {
    final fix = _pickupFix;
    if (fix != null) return plusCodeEncode(fix.lat, fix.lon);
    return _locationDenied
        ? l.homeLocationDeniedHint
        : l.homePickupUnknownValue;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return Scaffold(
      backgroundColor: surfaces.canvas,
      body: Stack(
        children: [
          Positioned.fill(
            child: RideMap(
              controller: _mapController,
              initialCenter: ll.LatLng(
                defaultCityConfig.centerLat,
                defaultCityConfig.centerLon,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(TakhiSpace.md),
                child: HomeTopBar(
                  appName: l.appName,
                  cityName: defaultCityConfig.name,
                  settingsLabel: l.settingsAction,
                  // `push`, not `go`: settings is a detour from home, and
                  // replacing the stack would leave it with no way back.
                  onSettings: () => context.push('/settings'),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    right: TakhiSpace.md,
                    bottom: TakhiSpace.sm,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: CircleIconButton(
                      icon: Icons.my_location,
                      semanticLabel: l.homeLocateAction,
                      onPressed: _locate,
                    ),
                  ),
                ),
                _HomeSheet(
                  pickupValue: _pickupValue(l),
                  onLocate: _locate,
                  onDestination: () => context.push('/ride/passenger'),
                  onSos: () => showSosActions(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom sheet: where the rider is, where they are going, what else
/// this app can do, and how it is doing.
class _HomeSheet extends StatelessWidget {
  final String pickupValue;
  final VoidCallback onLocate;
  final VoidCallback onDestination;
  final VoidCallback onSos;

  const _HomeSheet({
    required this.pickupValue,
    required this.onLocate,
    required this.onDestination,
    required this.onSos,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final maxContentHeight =
        MediaQuery.sizeOf(context).height * _kSheetContentMaxFraction;

    // Opaque so a drag that starts on the sheet stays on the sheet. A
    // painted surface is transparent to hit-testing in Flutter, so without
    // this every swipe across the sheet would pan the map underneath it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: TakhiSheet(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxContentHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(
                  title: l.homeSheetTitle,
                  subtitle: l.homeSheetSubtitle,
                ),
                const SizedBox(height: TakhiSpace.md),
                AddressRow(
                  icon: Icons.trip_origin,
                  label: l.homePickupLabel,
                  value: pickupValue,
                  accent: TakhiAccent.steppe,
                  onTap: onLocate,
                ),
                const SizedBox(height: TakhiSpace.xs),
                PillField(
                  icon: Icons.search,
                  placeholder: l.homeDestinationPlaceholder,
                  semanticsLabel: l.homeDestinationSemanticLabel,
                  onTap: onDestination,
                ),
                const SizedBox(height: TakhiSpace.lg),
                _ServiceRow(onRide: onDestination, onSos: onSos),
                const SizedBox(height: TakhiSpace.md),
                const HomeStatusRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The four things this app does, side by side and equally weighted.
///
/// Each tile owns a stable accent: gold is the rider's own default action,
/// steppe is working as a driver, sky is the driver's tool, clay is the
/// emergency. Only the first three navigate; SOS opens its sheet in place,
/// because leaving the map is the last thing anyone wants from an SOS
/// button.
class _ServiceRow extends StatelessWidget {
  final VoidCallback onRide;
  final VoidCallback onSos;

  const _ServiceRow({required this.onRide, required this.onSos});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Row(
      children: [
        Expanded(
          child: CategoryTile(
            icon: Icons.hail,
            label: l.startAsPassengerAction,
            onTap: onRide,
          ),
        ),
        Expanded(
          child: CategoryTile(
            icon: Icons.local_taxi,
            label: l.startAsDriverAction,
            accent: TakhiAccent.steppe,
            // `push` throughout, matching the settings entry above: every
            // one of these is a screen the rider comes back from.
            onTap: () => context.push('/ride/driver'),
          ),
        ),
        Expanded(
          child: CategoryTile(
            icon: Icons.speed,
            label: l.startAsMeterAction,
            accent: TakhiAccent.sky,
            onTap: () => context.push('/meter'),
          ),
        ),
        Expanded(
          child: CategoryTile(
            icon: Icons.emergency,
            label: l.sosAction,
            accent: TakhiAccent.clay,
            onTap: onSos,
          ),
        ),
      ],
    );
  }
}
