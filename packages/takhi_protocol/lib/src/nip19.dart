// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:bech32/bech32.dart';
import 'package:convert/convert.dart';

String _encode(String hrp, String dataHex) {
  final bytes = hex.decode(dataHex);
  final words = _convertBits(bytes, 8, 5, true);
  return bech32.encode(Bech32(hrp, words), 1000);
}

String _decode(String hrp, String value) {
  final Bech32 d;
  try {
    d = bech32.decode(value, 1000);
  } on Exception catch (e) {
    throw ArgumentError('invalid bech32 value for $hrp: $e');
  }
  if (d.hrp != hrp) {
    throw ArgumentError('expected $hrp, got ${d.hrp}');
  }
  final bytes = _convertBits(d.data, 5, 8, false);
  return hex.encode(bytes);
}

String hexToNpub(String pubkeyHex) => _encode('npub', pubkeyHex);
String hexToNsec(String privkeyHex) => _encode('nsec', privkeyHex);
String npubToHex(String npub) => _decode('npub', npub);

/// Decodes a bech32 `nsec1...` value back to its hex-encoded private key.
/// Throws [ArgumentError] if the value isn't valid bech32, or if its human
/// readable part isn't `nsec` (e.g. an `npub` value was passed by mistake).
String nsecToHex(String nsec) => _decode('nsec', nsec);

List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  var acc = 0, bits = 0;
  final out = <int>[];
  final maxv = (1 << to) - 1;
  for (final v in data) {
    acc = (acc << from) | v;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.add((acc >> bits) & maxv);
    }
  }
  if (pad && bits > 0) out.add((acc << (to - bits)) & maxv);
  return out;
}
