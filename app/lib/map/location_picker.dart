// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:takhi_protocol/takhi_protocol.dart';

import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/pill_field.dart';
import 'ride_map.dart';

/// Height of the map window.
///
/// Map geometry rather than layout spacing, so it is a named constant here
/// and not a [TakhiSpace] step: it is chosen against how much of a city
/// block has to be visible at once for a rider to recognise where they are,
/// and would be wrong at whatever the spacing scale happened to say. Deep
/// enough for a couple of streets around the pin, short enough that the
/// heading above it and the action below it stay on screen together.
const _kMapHeight = 260.0;

/// Height of the centre pin glyph.
const _kPinSize = 40.0;

/// Diameter of the dot marking the exact point the pin claims.
///
/// The pin is a *sign*, its tip is the *measurement*, and a glyph alone
/// leaves a rider guessing which pixel of it counts. Small enough not to
/// read as a second marker.
const _kAnchorDotSize = 6.0;

/// Zoom the map jumps to when it adopts a GPS fix.
///
/// Street level, and the same value home recentres at, so a rider who
/// located themselves on home and then opened this flow does not get two
/// different scales of the same neighbourhood.
const _kLocatedZoom = 16.0;

/// Size of the "you are here" marker. Deliberately smaller than
/// [_kPinSize]: the pin is the thing being *set* and must stay the loudest
/// mark on the map; this one is a reference point.
const _kDeviceMarkerSize = 22.0;

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

/// Center-pin map picker + landmark capsule (spec §5/§12): the rider pans
/// the map under a fixed center pin rather than dragging the pin itself --
/// the standard, thumb-friendly picking pattern for a full-width map. Every
/// pan and keystroke calls [onChanged] with the current [PickedLocation],
/// so callers always have a live value rather than only on an explicit
/// "confirm".
///
/// The map is drawn as a *card* -- rounded, hairlined, clipped -- rather
/// than as a bare rectangle bleeding into the page. This widget is never
/// the whole screen: it sits inside a page or a sheet that owns the
/// heading and the action, so it has to read as one object on that page,
/// which is the same rule every other row and block in this app follows.
///
/// Its two halves are one control and stay that way: the pin says *where*,
/// the capsule under it says *what is standing there*. Splitting them
/// across a page would let a rider fill in one and forget the other, and
/// the landmark is the only part of a pickup a driver can actually read
/// (a Plus Code is not a place, spec §6).
class LocationPickerField extends StatefulWidget {
  /// Where the map opens, and -- while the rider has not panned it
  /// themselves -- where it *moves to* if this changes.
  ///
  /// That second half is what lets a GPS fix arriving a second after the
  /// screen opened land on the map instead of being ignored. The guard is
  /// the point: a fix that arrives after a rider has already set their
  /// corner must not drag the map away from it, so a pan of any size makes
  /// this widget stop listening to its caller's centre for good.
  final ll.LatLng initialCenter;

  /// Landmark to start the text field with. Callers that let the rider
  /// step back to a point they already picked pass the text back in, so
  /// returning to that step shows what they typed instead of a blank
  /// field that the next map pan would overwrite with an empty string.
  final String initialLandmarkText;

  /// Where the device itself says it is, once a fix exists. Drawn as its
  /// own small marker, distinct from the centre pin.
  ///
  /// Two different facts, and conflating them was the old bug: the pin says
  /// *what the rider is asking a driver to come to*, this says *where the
  /// phone thinks it is standing*. They start out identical and part company
  /// the moment the rider pans -- and it is exactly then that a rider needs
  /// to be able to find their way back, or to see that the point they have
  /// dragged to is three blocks from where they are.
  ///
  /// Null until a fix arrives, or forever if location was refused. Nothing
  /// is drawn in that case: a marker for a position the app does not have
  /// would be a claim it cannot back.
  final ll.LatLng? devicePosition;

  final ValueChanged<PickedLocation> onChanged;

  const LocationPickerField({
    super.key,
    required this.initialCenter,
    this.initialLandmarkText = '',
    this.devicePosition,
    required this.onChanged,
  });

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  final _mapController = MapController();
  late ll.LatLng _center = widget.initialCenter;
  late final _landmarkController = TextEditingController(
    text: widget.initialLandmarkText,
  );
  late String _landmarkText = widget.initialLandmarkText;

  /// True from the rider's first pan onwards. Never reset: once they have
  /// said where they are standing, nothing arriving later gets to disagree.
  bool _riderMovedMap = false;

  /// `MapController.move` throws until the map has been laid out and the
  /// controller attached, so a centre that changes before then is held here
  /// and applied from `onMapReady`.
  bool _mapReady = false;
  ll.LatLng? _pendingRecenter;

  @override
  void didUpdateWidget(covariant LocationPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCenter == oldWidget.initialCenter) return;
    if (_riderMovedMap) return;
    _recenter(widget.initialCenter);
  }

  @override
  void dispose() {
    _landmarkController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Moves the camera to [target] and adopts it as the picked point.
  ///
  /// Both halves are needed. `RideMap` only reports a centre for gestures
  /// (`onPositionChanged`'s `hasGesture`), which is what keeps a programmatic
  /// move from being mistaken for a rider's pan -- so a move made here has to
  /// state the new point itself, or the caller would be shown a map centred
  /// on one place while holding coordinates for another.
  void _recenter(ll.LatLng target) {
    if (!_mapReady) {
      _pendingRecenter = target;
      return;
    }
    _pendingRecenter = null;
    _center = target;
    _mapController.move(target, _kLocatedZoom);
    _emit();
  }

  void _onMapReady() {
    _mapReady = true;
    final pending = _pendingRecenter;
    if (pending != null) _recenter(pending);
  }

  void _emit() => widget.onChanged(
    PickedLocation(
      lat: _center.latitude,
      lon: _center.longitude,
      landmarkText: _landmarkText,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final device = widget.devicePosition;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          // Painted over the clipped map rather than behind it: a border on
          // an ancestor of a `ClipRRect` is covered by the tiles it clips.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: TakhiRadius.cardAll,
            border: Border.all(color: surfaces.hairline),
          ),
          child: ClipRRect(
            borderRadius: TakhiRadius.cardAll,
            child: SizedBox(
              height: _kMapHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RideMap(
                    controller: _mapController,
                    initialCenter: _center,
                    onMapReady: _onMapReady,
                    onCenterChanged: (c) => setState(() {
                      _riderMovedMap = true;
                      _center = c;
                      _emit();
                    }),
                    layers: [
                      if (device != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: device,
                              width: _kDeviceMarkerSize,
                              height: _kDeviceMarkerSize,
                              child: const Icon(
                                Icons.my_location,
                                size: _kDeviceMarkerSize,
                                // Steppe rather than gold: the brand colour
                                // belongs to the pin being set, and two gold
                                // marks on one map is two things claiming to
                                // be the answer.
                                color: TakhiColors.steppe,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const IgnorePointer(child: _CenterPin()),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: TakhiSpace.sm),
        PillField(
          icon: Icons.push_pin_outlined,
          controller: _landmarkController,
          placeholder: AppLocalizations.of(context)!.landmarkHint,
          onChanged: (text) => setState(() {
            _landmarkText = text;
            _emit();
          }),
        ),
      ],
    );
  }
}

/// The marker at the middle of the map: a pin standing *on* the point,
/// plus the point itself.
///
/// The pin is lifted by half its own height so its tip -- not its middle --
/// lands on the map centre, which is the coordinate this widget actually
/// reports. Centring the glyph itself, as this used to, put the visible
/// point about twenty pixels south of the one being published: at street
/// zoom that is the wrong side of a building entrance.
class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, -_kPinSize / 2),
          child: const Icon(
            Icons.location_pin,
            color: TakhiColors.gold,
            size: _kPinSize,
          ),
        ),
        Container(
          width: _kAnchorDotSize,
          height: _kAnchorDotSize,
          decoration: BoxDecoration(
            color: surfaces.onSheet,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
