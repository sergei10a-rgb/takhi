// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Zoom used when everything the camera has to hold is one and the same
/// point, where there is no extent to fit.
///
/// Street level -- the same scale the location pickers settle at, so the
/// first thing a user sees is the neighbourhood they know rather than a
/// continent or a doorstep. `CameraFit.coordinates` on a zero-size bound
/// resolves to a meaningless zoom, which is why this case is answered with
/// a plain `move` instead.
const kSinglePointZoom = 16.0;

/// The one camera-following behaviour in this app: "keep these points in
/// frame, and keep doing it as they move".
///
/// It exists because the same bug was written three times. `MapOptions
/// .initialCenter` is honoured on exactly one frame -- the frame the map is
/// created -- so any screen that centres on a position it does not yet have,
/// or on the first of a series of positions, ends up with a camera pointed
/// at wherever the phone happened to be when the screen opened. The rider
/// then watches their own dot walk off the edge and never come back, on the
/// one screen whose entire job is answering "where am I".
///
/// Three rules, all of them learned from that failure:
///
/// 1. **Nothing may touch the camera before the map says it is ready.**
///    [MapController] has no state attached until `onMapReady` fires, and
///    every camera call on it throws until then. [markMapReady] is that
///    signal; [fitMapCamera] is silent (not throwing, not queueing) before
///    it.
/// 2. **The fit happens after the frame, never during it.** `build` may not
///    touch the render tree, and on the very first pass the map has not
///    finished laying out, so every fit is scheduled with
///    `addPostFrameCallback` and re-checks `mounted` when it lands.
/// 3. **One point is not a bounding box.** A degenerate fit is a `move` at
///    [kSinglePointZoom]; anything else is a real `fitCamera`. A screen with
///    a single known position -- which is what every trip looks like until
///    the other side's first location arrives -- is the *common* case here,
///    not an exotic one.
mixin MapCameraFit<T extends StatefulWidget> on State<T> {
  /// The controller handed to the `RideMap` this state owns.
  MapController get mapCameraController;

  bool _mapReady = false;
  bool _followSuspended = false;

  /// Whether the map has laid out and attached itself to
  /// [mapCameraController] -- i.e. whether the camera can be driven at all.
  bool get isMapCameraReady => _mapReady;

  /// Wire to `RideMap.onMapReady`.
  ///
  /// Deliberately not a `setState`: nothing painted depends on the flag, and
  /// callers issue their fit from the same callback.
  void markMapCameraReady() => _mapReady = true;

  /// Call when the controller is swapped for a different one.
  ///
  /// A different controller is a different, not-yet-laid-out map: it has no
  /// state attached, so every camera call on it throws until this widget's
  /// `onMapReady` fires again. Leaving the flag set is what turns a
  /// controller swap into a crash on the very next fit.
  void forgetMapCamera() {
    _mapReady = false;
    _followSuspended = false;
  }

  /// Whether the camera has been handed to the user.
  ///
  /// Screens show a "back to me" control while this is true — a map that
  /// has stopped following with nothing saying so is a map that looks
  /// broken the moment the car drives off the edge.
  bool get isMapFollowingSuspended => _followSuspended;

  /// Stops the camera following. Wire to `RideMap.onUserPanned`.
  ///
  /// A driver who drags the map is asking to look somewhere else — up the
  /// road, at the turn after next — and the app has no business dragging it
  /// back half a second later. This was the field report: the map could not
  /// be panned at all, because every fix snapped it home.
  ///
  /// `setState` because a control appears: this is one of the few flags
  /// here that something painted depends on.
  void suspendMapFollowing() {
    if (_followSuspended) return;
    setState(() => _followSuspended = true);
  }

  /// Gives the camera back to the app, and re-frames immediately.
  void resumeMapFollowing() {
    if (!_followSuspended) return;
    setState(() => _followSuspended = false);
  }

  /// Frames [points], after the frame currently being built.
  ///
  /// [padding] is the margin kept clear around them. It is never zero at any
  /// real call site: a marker is drawn *above* its coordinate, so a fit that
  /// put the coordinate exactly on an edge would push the glyph off screen
  /// and leave the user looking at a route that ends in nothing -- and any
  /// sheet anchored over the map hides a band of it that the fit has to be
  /// told about.
  void fitMapCamera(
    List<ll.LatLng> points, {
    required EdgeInsets padding,
    double singlePointZoom = kSinglePointZoom,
  }) {
    if (!_mapReady || _followSuspended || points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      if (points.every((point) => point == points.first)) {
        mapCameraController.move(points.first, singlePointZoom);
        return;
      }
      mapCameraController.fitCamera(
        CameraFit.coordinates(coordinates: points, padding: padding),
      );
    });
  }
}
