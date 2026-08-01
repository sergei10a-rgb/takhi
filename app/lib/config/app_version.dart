// SPDX-License-Identifier: AGPL-3.0-or-later

/// The version this build calls itself, as it appears in bug reports.
///
/// A plain constant rather than `package_info_plus`, for two reasons: it
/// works in `flutter test` without a platform channel, so the guard below
/// can actually run; and reading it costs nothing at the moment it is
/// needed, which is while a driver is holding a report they want to send.
///
/// **Must match `pubspec.yaml`.** `test/config/app_version_test.dart` reads
/// the pubspec and fails if it does not, because a version string that
/// silently lags a release turns every bug report into a guess about which
/// build produced it — and the reports this constant exists to stamp are
/// exactly the ones where that matters.
const String kAppVersion = '0.3.0+3';
