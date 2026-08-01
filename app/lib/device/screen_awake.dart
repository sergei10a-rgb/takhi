// SPDX-License-Identifier: AGPL-3.0-or-later

/// Keeps the display on while something on it must stay readable.
///
/// Behind an interface for the same reason `LocationSource` is: the real
/// implementation is a thin wrapper over a platform channel that cannot run
/// in `flutter test`, and everything that decides *when* to hold the screen
/// on is worth testing without a device.
///
/// Asked for by the driver who field-tested v0.3.0 — the screen went dark
/// mid-run. On this screen that is not cosmetic: a driver who cannot see
/// the meter cannot tell a passenger what they owe, and reaching over to
/// wake a phone while driving is the wrong thing to make anyone do.
library;

import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

abstract interface class ScreenAwake {
  /// Asks the system not to sleep the display.
  Future<void> keepOn();

  /// Gives the screen back to the system's normal timeout.
  ///
  /// Must be called on every path out of the state that wanted it — a
  /// wakelock leaked past the end of a run is a flat battery by lunchtime,
  /// and a driver whose phone dies mid-shift does not file a bug report,
  /// they uninstall.
  Future<void> release();
}

class WakelockScreenAwake implements ScreenAwake {
  const WakelockScreenAwake();

  @override
  Future<void> keepOn() => _tolerate(WakelockPlus.enable);

  @override
  Future<void> release() => _tolerate(WakelockPlus.disable);

  /// Runs [work], absorbing a platform that has no wakelock to give.
  ///
  /// The display staying lit is a comfort; the fare is the product. A
  /// platform channel that is missing (a desktop build, a test binding, a
  /// device whose OEM stripped the API) must not be able to throw out of an
  /// unawaited call and take a running meter down with it — which is
  /// exactly what it did the first time this was wired up.
  ///
  /// Deliberately narrow: only [MissingPluginException] and
  /// [PlatformException] are absorbed, so a programming error here still
  /// surfaces as one.
  static Future<void> _tolerate(Future<void> Function() work) async {
    try {
      await work();
    } on MissingPluginException {
      // No wakelock on this platform. Nothing to do and nothing to say.
    } on PlatformException {
      // The OS refused. Same bargain.
    }
  }
}

/// Does nothing, successfully.
///
/// The default outside a real device, and what every widget test gets: a
/// platform channel with no platform behind it throws, and a screen that
/// crashed because it asked the display to stay on would be a worse bug
/// than the one this fixes.
class NoopScreenAwake implements ScreenAwake {
  const NoopScreenAwake();

  @override
  Future<void> keepOn() async {}

  @override
  Future<void> release() async {}
}
