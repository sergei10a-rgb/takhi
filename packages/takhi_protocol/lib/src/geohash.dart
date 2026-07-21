// SPDX-License-Identifier: AGPL-3.0-or-later
const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

String geohashEncode(double lat, double lon, {int precision = 6}) {
  var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
  final buf = StringBuffer();
  var bit = 0, ch = 0;
  var even = true;
  while (buf.length < precision) {
    if (even) {
      final mid = (lonMin + lonMax) / 2;
      if (lon >= mid) {
        ch = (ch << 1) | 1;
        lonMin = mid;
      } else {
        ch = ch << 1;
        lonMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latMin = mid;
      } else {
        ch = ch << 1;
        latMax = mid;
      }
    }
    even = !even;
    if (++bit == 5) {
      buf.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return buf.toString();
}

/// Decodes [hash] to its exact bounding box (`latMin/latMax/lonMin/lonMax`)
/// on the same bit-bisection grid that [geohashEncode] used to produce it.
///
/// This is the shared decode loop behind [geohashDecodeCenter] and
/// [geohashNeighbors] -- keeping a single source of truth here is what lets
/// [geohashNeighbors] step by the *exact* cell width instead of an
/// approximated one (see that function's doc comment for why the previous
/// approximation was unsound).
({double latMin, double latMax, double lonMin, double lonMax}) _decodeBounds(
    String hash) {
  var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
  var even = true;
  for (final c in hash.split('')) {
    final cd = _base32.indexOf(c);
    for (var i = 4; i >= 0; i--) {
      final bit = (cd >> i) & 1;
      if (even) {
        final mid = (lonMin + lonMax) / 2;
        if (bit == 1) {
          lonMin = mid;
        } else {
          lonMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (bit == 1) {
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
      even = !even;
    }
  }
  return (latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax);
}

({double lat, double lon}) geohashDecodeCenter(String hash) {
  final b = _decodeBounds(hash);
  return (
    lat: (b.latMin + b.latMax) / 2,
    lon: (b.lonMin + b.lonMax) / 2,
  );
}

/// Returns the (up to) 8 geohashes adjacent to [hash] at the same
/// precision, excluding [hash] itself.
///
/// Neighbors are found by stepping the decoded center by the *exact*
/// cell width/height of [hash]'s bounding box (from [_decodeBounds]) and
/// re-encoding at the same precision. Because the bit-bisection grid is
/// uniform for a given precision, offsetting by exactly one cell width
/// always lands in the center of the adjacent cell -- this holds at every
/// precision, including low ones (1-4), where an earlier implementation
/// that approximated cell width from `precision * 5` bits (rather than
/// decoding the actual bounds) would round-trip to the wrong cell -- or
/// back into the same cell -- because the lat/lon bit split for coarse
/// hashes doesn't divide evenly by the approximation.
///
/// Longitude wraps around the antimeridian (stepping past +-180 does not
/// produce a fewer-than-8 or self-including result -- see below), but
/// latitude does not wrap at the poles, since there is no well-defined
/// "cell north of the north pole". A hash whose cell touches +-90 (i.e. any
/// hash at precision 1, or a precision-2+ hash within one cell of a pole)
/// therefore has no valid neighbor in that direction, and the result may
/// contain fewer than 8 distinct, self-excluding entries. takhi only
/// operates within Mongolia, nowhere near a pole, so this is not currently
/// reachable in practice -- but callers outside that constraint should not
/// treat the 8-entry/self-exclusion guarantee as absolute near the poles.
List<String> geohashNeighbors(String hash) {
  final b = _decodeBounds(hash);
  final p = hash.length;
  final lat = (b.latMin + b.latMax) / 2;
  final lon = (b.lonMin + b.lonMax) / 2;
  final latWidth = b.latMax - b.latMin;
  final lonWidth = b.lonMax - b.lonMin;
  final out = <String>[];
  for (final dLat in [1, 0, -1]) {
    for (final dLon in [-1, 0, 1]) {
      if (dLat == 0 && dLon == 0) continue;
      final nLat = lat + dLat * latWidth;
      // Wrap longitude into [-180, 180) so antimeridian-adjacent cells
      // (e.g. lon ~179.99) resolve to the real neighbor on the other side
      // instead of clipping back into the same cell.
      var nLon = (lon + dLon * lonWidth + 180.0) % 360.0 - 180.0;
      if (nLon < -180.0) nLon += 360.0;
      out.add(geohashEncode(nLat, nLon, precision: p));
    }
  }
  return out.toSet().toList();
}
