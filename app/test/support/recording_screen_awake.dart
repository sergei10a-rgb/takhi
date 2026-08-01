// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:takhi/device/screen_awake.dart';

/// Records every request to hold or release the display.
///
/// The real wakelock cannot be observed from `flutter test`, and the way it
/// fails is invisible either way: a lock that is taken and never given back
/// looks exactly like a working app until a driver's phone is flat by
/// lunchtime. So the balance is asserted here instead.
class RecordingScreenAwake implements ScreenAwake {
  int keepOnCount = 0;
  int releaseCount = 0;

  /// Whether the display is currently being held, by this double's own
  /// bookkeeping.
  bool get isHeld => keepOnCount > releaseCount;

  @override
  Future<void> keepOn() async => keepOnCount++;

  @override
  Future<void> release() async => releaseCount++;
}
