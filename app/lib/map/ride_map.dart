// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

/// The bare OSM-tiled map every ride screen builds on (spec §12 `map/`,
/// §5: "OSM pin + Plus Code + чөлөөт текст"; open tiles, no paid/closed
/// geocoding API). Takes no city-specific default -- callers always pass
/// [initialCenter] -- so this widget carries no hardcoded city (spec §11
/// "кодонд УБ hardcode 0"); the concrete Ulaanbaatar default lives at the
/// ride-screen call site (Task 9) until a real city-config seam exists.
class RideMap extends StatelessWidget {
  final ll.LatLng initialCenter;
  final double initialZoom;
  final MapController? controller;
  final ValueChanged<ll.LatLng>? onCenterChanged;
  final List<Widget> layers;

  /// Fires once the map is laid out and its [controller] is attached.
  ///
  /// The only safe moment to start driving the camera from outside:
  /// `MapController.move`/`fitCamera` throw before the map's state exists,
  /// so a caller that wants to follow a growing track has to wait to be
  /// told. Callers that never move the camera leave this null.
  final VoidCallback? onMapReady;

  const RideMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15,
    this.controller,
    this.onCenterChanged,
    this.onMapReady,
    this.layers = const [],
  });

  @override
  Widget build(BuildContext context) => FlutterMap(
    mapController: controller,
    options: MapOptions(
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      onMapReady: onMapReady,
      onPositionChanged: (position, hasGesture) {
        if (!hasGesture) return;
        final center = position.center;
        onCenterChanged?.call(center);
      },
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'mn.takhi.takhi',
      ),
      const RichAttributionWidget(
        attributions: [TextSourceAttribution('OpenStreetMap contributors')],
      ),
      ...layers,
    ],
  );
}
