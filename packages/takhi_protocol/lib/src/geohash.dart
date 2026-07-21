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

({double lat, double lon}) geohashDecodeCenter(String hash) {
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
  return (lat: (latMin + latMax) / 2, lon: (lonMin + lonMax) / 2);
}

List<String> geohashNeighbors(String hash) {
  final c = geohashDecodeCenter(hash);
  final p = hash.length;
  // cell size in degrees for precision p
  final latErr = 180.0 / _pow2((5 * p) ~/ 2);
  final lonErr = 360.0 / _pow2((5 * p + 1) ~/ 2);
  final out = <String>[];
  for (final dLat in [1, 0, -1]) {
    for (final dLon in [-1, 0, 1]) {
      if (dLat == 0 && dLon == 0) continue;
      out.add(geohashEncode(
          c.lat + dLat * latErr * 2, c.lon + dLon * lonErr * 2,
          precision: p));
    }
  }
  return out.toSet().toList();
}

int _pow2(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 2;
  }
  return r;
}
