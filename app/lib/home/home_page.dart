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
import '../map/device_location_layer.dart';
import '../map/ride_map.dart';
import '../safety/sos_button.dart';
import '../theme/takhi_theme.dart';
import '../widgets/address_row.dart';
import '../widgets/category_tile.dart';
import '../widgets/circle_icon_button.dart';
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

/// Diameter of one dot in the rail that runs between the pickup marker and
/// the destination marker. Small enough that three of them read as a
/// dotted line rather than as three more markers.
const _kRailDotSize = 3.0;

/// How many of them. Three is the fewest that reads as "continues" rather
/// than as a decoration.
const _kRailDotCount = 3;

/// How much of [TakhiSurfaces.muted] the rail keeps. The rail is a hint
/// that two rows belong together, not a divider anyone should read.
const _kRailDotOpacity = 0.45;

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

  /// The name the pickup row leads with.
  ///
  /// Never a Plus Code. The app cannot ask what is standing at a set of
  /// coordinates -- a geocoding request would hand the rider's exact
  /// position to a third-party server, which is the one thing the privacy
  /// design rules out (spec §6) -- so the honest readable answer once a fix
  /// exists is that this *is* where the rider is. The code itself is not
  /// thrown away; it moves to [_pickupDetail].
  ///
  /// A name the rider gave the point themselves would outrank this, and
  /// [AddressRow.value] is where such a name goes -- that is the tier the
  /// ride flow's `LocationPickerField` landmark feeds. Home has no landmark
  /// of its own to show: nothing on this screen publishes a ride, so a name
  /// typed here would reach no driver, and a field that quietly discards
  /// what it collects is worse than no field.
  String _pickupName(AppLocalizations l) {
    if (_pickupFix != null) return l.homeCurrentLocationValue;
    return _locationDenied
        ? l.homeLocationDeniedHint
        : l.homePickupUnknownValue;
  }

  /// The Plus Code under the name, once there is a fix to encode.
  ///
  /// Kept rather than dropped because it is the only *exact* form of the
  /// point the app has, and it is the form SOS messages and shared trips
  /// actually carry -- a rider comparing what their phone shows against
  /// what their contact received needs to be able to see it.
  String? _pickupDetail() {
    final fix = _pickupFix;
    return fix == null ? null : plusCodeEncode(fix.lat, fix.lon);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final fix = _pickupFix;

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
              layers: [
                // The answer to "so where am I?". Recentring the camera on
                // a fix -- which is all this screen used to do -- moves the
                // whole city under a rider without ever marking the one
                // point they were looking for, and the moment they pan, it
                // is lost again.
                if (fix != null)
                  DeviceLocationLayer(
                    position: ll.LatLng(fix.lat, fix.lon),
                    accuracyMeters: fix.accuracyMeters,
                  ),
              ],
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
                  pickupName: _pickupName(l),
                  pickupDetail: _pickupDetail(),
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
  final String pickupName;
  final String? pickupDetail;
  final VoidCallback onLocate;
  final VoidCallback onDestination;
  final VoidCallback onSos;

  const _HomeSheet({
    required this.pickupName,
    required this.pickupDetail,
    required this.onLocate,
    required this.onDestination,
    required this.onSos,
  });

  @override
  Widget build(BuildContext context) {
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
                _TripBlock(
                  pickupName: pickupName,
                  pickupDetail: pickupDetail,
                  onPickup: onLocate,
                  onDestination: onDestination,
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

/// Where the rider is and where they are going, as one object.
///
/// The two rows used to be a heading, a row and a search capsule stacked
/// loosely on the sheet, under a display-size "Хаашаа явах вэ?" that asked
/// exactly what the capsule beneath it already asked. The headline is gone
/// -- the question now lives once, in the row where the answer is typed --
/// and the sheet is that much shorter, which is map the rider gets back.
///
/// What replaces the heading as the sheet's structure is this block: one
/// sunken well, two rows of the same component, and a dotted rail joining
/// their markers. A trip is one thing with two ends, and this is the shape
/// riders already know it by from every other app on their phone.
class _TripBlock extends StatelessWidget {
  final String pickupName;
  final String? pickupDetail;
  final VoidCallback onPickup;
  final VoidCallback onDestination;

  const _TripBlock({
    required this.pickupName,
    required this.pickupDetail,
    required this.onPickup,
    required this.onDestination,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        // The field surface, not the sheet's: this is the one place on home
        // the rider fills in, and the app says "fill me in" by recessing a
        // well into the sheet rather than by drawing a box around a label.
        color: surfaces.field,
        borderRadius: TakhiRadius.cardAll,
        border: Border.all(color: surfaces.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TakhiSpace.md,
          vertical: TakhiSpace.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AddressRow(
              icon: Icons.trip_origin,
              label: l.homePickupLabel,
              value: pickupName,
              detail: pickupDetail,
              accent: TakhiAccent.steppe,
              onTap: onPickup,
              semanticsLabel: l.homeLocateAction,
            ),
            const _RouteRail(),
            AddressRow(
              icon: Icons.place,
              label: l.homeDestinationPlaceholder,
              // The row states the question until it can state an address.
              value: l.homeSheetTitle,
              onTap: onDestination,
              semanticsLabel: l.homeDestinationSemanticLabel,
              // A plain row is a statement; the chevron is what says this
              // one opens something.
              trailing: Icon(Icons.chevron_right, color: surfaces.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dotted line between the two markers.
///
/// Sized and centred on [AddressRow.dotSize] rather than on a number of its
/// own, so it stays on the markers' axis if that diameter ever changes.
class _RouteRail extends StatelessWidget {
  const _RouteRail();

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final dot = Container(
      width: _kRailDotSize,
      height: _kRailDotSize,
      decoration: BoxDecoration(
        color: surfaces.muted.withValues(alpha: _kRailDotOpacity),
        shape: BoxShape.circle,
      ),
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: AddressRow.dotSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _kRailDotCount; i++) ...[
              if (i > 0) const SizedBox(height: TakhiSpace.xxs),
              dot,
            ],
          ],
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
