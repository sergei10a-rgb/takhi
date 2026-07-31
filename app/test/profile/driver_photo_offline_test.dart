// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/driver_photo_service.dart';
import 'package:takhi/profile/driver_photo_store.dart';

/// The files that make up the portrait pipeline. Scoped to these rather
/// than to `lib/profile/` as a whole, because `driver_profile_service.dart`
/// legitimately talks to relays -- it publishes the *public* half of the
/// profile (car, colour, plate, tariffs). The photo half must never join it.
const _pipelineFiles = <String>[
  'lib/profile/driver_photo_rules.dart',
  'lib/profile/driver_photo_codec.dart',
  'lib/profile/driver_photo_face_check.dart',
  'lib/profile/driver_photo_service.dart',
  'lib/profile/driver_photo_store.dart',
];

/// Ways out of the process, by name. `dart:io` itself is not on the list --
/// `driver_photo_store.dart` needs `File` -- so the ban names the escape
/// routes rather than the library.
const _networkTokens = <String>[
  'HttpClient',
  'package:http',
  'WebSocket',
  'RawDatagramSocket',
  'InternetAddress',
  'dart:html',
  'RelayPool',
  'relay_pool',
  'http://',
  'https://',
];

Uint8List _photo() {
  final rng = math.Random(11);
  var image = img.Image(width: 600, height: 600);
  for (var y = 0; y < 600; y++) {
    for (var x = 0; x < 600; x++) {
      image.setPixelRgb(
        x,
        y,
        rng.nextInt(256),
        rng.nextInt(256),
        rng.nextInt(256),
      );
    }
  }
  image = img.gaussianBlur(image, radius: 6);
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

class _PassingDetector implements FaceDetector {
  @override
  Future<List<DetectedFace>> detect(Uint8List jpegBytes) async => const [
    DetectedFace(score: 0.95, left: 0.25, top: 0.2, width: 0.5, height: 0.5),
  ];
}

void main() {
  // A driver's face is the most sensitive thing this app ever handles, and
  // "it is all on-device" is the claim the whole design rests on. A claim
  // that lives only in a doc comment is a claim somebody eventually breaks
  // by adding one convenient upload, so it is asserted here instead.
  test('no file in the portrait pipeline mentions a way onto the network', () {
    final offenders = <String>[];
    for (final path in _pipelineFiles) {
      final file = File(path);
      // A pipeline file that was renamed away is a hole in this check, so
      // a missing file is a failure rather than a silently skipped loop.
      expect(file.existsSync(), isTrue, reason: '$path no longer exists');
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final token in _networkTokens) {
          if (lines[i].contains(token)) {
            offenders.add(
              '$path:${i + 1} mentions «$token»: ${lines[i].trim()}',
            );
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'The driver-photo pipeline must never leave the device. A face '
          'sent anywhere for checking is a face somebody else now has:\n'
          '${offenders.join('\n')}',
    );
  });

  // The grep above reads the source; this runs it. Between them they cover
  // both "somebody imported a client" and "somebody called through a
  // dependency that has one".
  test('a full accept-and-store run never opens an HTTP client', () async {
    var attempted = false;
    await HttpOverrides.runZoned(
      () async {
        final service = DriverPhotoService(
          _PassingDetector(),
          InMemoryDriverPhotoStore(),
        );
        expect(await service.replacePhoto(_photo()), isNull);
      },
      createHttpClient: (context) {
        attempted = true;
        throw StateError('the portrait pipeline opened an HTTP client');
      },
    );
    expect(attempted, isFalse);
  });
}
