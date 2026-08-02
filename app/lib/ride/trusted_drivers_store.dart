// SPDX-License-Identifier: AGPL-3.0-or-later

/// The drivers a passenger has personally vouched for.
///
/// `computeReputation` has taken a `viewerTrusted` set since it was
/// written, and it is the part of the design that answers the question a
/// paired-receipt count cannot: *who says so*. A receipt from a stranger
/// counts once; a receipt from somebody this passenger has ridden with and
/// chose to trust counts for more, because inventing the first is cheap and
/// inventing the second means fooling a specific real person.
///
/// Until now nothing filled the set. It was passed as `const {}` at every
/// call site, so the whole trust half of the ranking sat there doing
/// nothing — an algorithm with no input is not a feature, it is a plan.
///
/// **Local only, never published.** Who somebody trusts is a map of who
/// they ride with, and that belongs on their phone. The set is read when
/// ranking offers and at no other time.
library;

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class TrustedDriversStore {
  Future<Set<String>> load();

  /// Adds [pubHex]. Idempotent — a passenger who taps twice has said the
  /// same thing twice.
  Future<void> trust(String pubHex);

  Future<void> untrust(String pubHex);
}

class SharedPreferencesTrustedDriversStore implements TrustedDriversStore {
  static const _key = 'takhi_trusted_driver_pubkeys';

  final Future<SharedPreferences> Function() _prefs;
  const SharedPreferencesTrustedDriversStore(this._prefs);

  @override
  Future<Set<String>> load() async {
    final prefs = await _prefs();
    return (prefs.getStringList(_key) ?? const <String>[]).toSet();
  }

  @override
  Future<void> trust(String pubHex) async {
    if (pubHex.isEmpty) return;
    final prefs = await _prefs();
    final current = (prefs.getStringList(_key) ?? const <String>[]).toSet()
      ..add(pubHex);
    await prefs.setStringList(_key, current.toList());
  }

  @override
  Future<void> untrust(String pubHex) async {
    final prefs = await _prefs();
    final current = (prefs.getStringList(_key) ?? const <String>[]).toSet()
      ..remove(pubHex);
    await prefs.setStringList(_key, current.toList());
  }
}

class InMemoryTrustedDriversStore implements TrustedDriversStore {
  final Set<String> _trusted = {};

  @override
  Future<Set<String>> load() async => Set.of(_trusted);

  @override
  Future<void> trust(String pubHex) async {
    if (pubHex.isNotEmpty) _trusted.add(pubHex);
  }

  @override
  Future<void> untrust(String pubHex) async => _trusted.remove(pubHex);
}
