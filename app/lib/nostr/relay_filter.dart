// SPDX-License-Identifier: AGPL-3.0-or-later

/// A NIP-01 subscription filter, serializable to the JSON shape relays
/// expect inside a `["REQ", subId, filter]` frame.
class RelayFilter {
  final List<int>? kinds;
  final List<String>? authors;

  /// NIP-01 tag filters, e.g. `{'#g': ['u9huf6']}`.
  final Map<String, List<String>> tagFilters;
  final int? since;
  final int? limit;

  const RelayFilter({
    this.kinds,
    this.authors,
    this.tagFilters = const {},
    this.since,
    this.limit,
  });

  Map<String, dynamic> toJson() => {
    if (kinds != null) 'kinds': kinds,
    if (authors != null) 'authors': authors,
    for (final e in tagFilters.entries) e.key: e.value,
    if (since != null) 'since': since,
    if (limit != null) 'limit': limit,
  };
}
