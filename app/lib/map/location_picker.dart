// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import 'ride_map.dart';

/// A point the rider picked: exact coordinates, the Plus Code derived
/// from them (spec §5 geocoding decision), and an optional free-text
/// landmark description they typed themselves.
class PickedLocation {
  final double lat;
  final double lon;
  final String landmarkText;
  const PickedLocation({
    required this.lat,
    required this.lon,
    this.landmarkText = '',
  });

  String get plusCode => plusCodeEncode(lat, lon);
}

/// Center-pin map picker + landmark text field (spec §5/§12): the rider
/// pans the map under a fixed center pin rather than dragging the pin
/// itself -- the standard, thumb-friendly picking pattern for a
/// full-width map. Every pan and keystroke calls [onChanged] with the
/// current [PickedLocation], so callers always have a live value rather
/// than only on an explicit "confirm".
class LocationPickerField extends StatefulWidget {
  final ll.LatLng initialCenter;

  /// Landmark to start the text field with. Callers that let the rider
  /// step back to a point they already picked pass the text back in, so
  /// returning to that step shows what they typed instead of a blank
  /// field that the next map pan would overwrite with an empty string.
  final String initialLandmarkText;

  final ValueChanged<PickedLocation> onChanged;

  const LocationPickerField({
    super.key,
    required this.initialCenter,
    this.initialLandmarkText = '',
    required this.onChanged,
  });

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  late ll.LatLng _center = widget.initialCenter;
  late final _landmarkController = TextEditingController(
    text: widget.initialLandmarkText,
  );
  late String _landmarkText = widget.initialLandmarkText;

  @override
  void dispose() {
    _landmarkController.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(
    PickedLocation(
      lat: _center.latitude,
      lon: _center.longitude,
      landmarkText: _landmarkText,
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RideMap(
              initialCenter: _center,
              onCenterChanged: (c) => setState(() {
                _center = c;
                _emit();
              }),
            ),
            const IgnorePointer(
              child: Icon(
                Icons.location_pin,
                color: TakhiColors.gold,
                size: 40,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _landmarkController,
        onChanged: (text) => setState(() {
          _landmarkText = text;
          _emit();
        }),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: AppLocalizations.of(context)!.landmarkHint,
        ),
      ),
    ],
  );
}
