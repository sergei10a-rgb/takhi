// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The version a bug report claims must be the version that was built.
//
// This is a mechanical guard rather than a discipline. `kAppVersion` is
// stamped onto every GPS diagnostic a driver sends; if it lags a release,
// every report arrives labelled with the wrong build and the labelling is
// worse than none, because it is believed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/config/app_version.dart';

void main() {
  test('kAppVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(
      match,
      isNotNull,
      reason: 'pubspec.yaml has no top-level `version:` line to compare '
          'against, so this guard cannot do its job.',
    );
    expect(
      kAppVersion,
      match!.group(1),
      reason: 'lib/config/app_version.dart was not bumped with pubspec.yaml. '
          'Every diagnostic report a driver sends is stamped with '
          '`kAppVersion`, so a stale value mislabels the build that produced '
          'the evidence.',
    );
  });
}
