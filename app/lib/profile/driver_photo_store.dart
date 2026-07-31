// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

/// Local-only storage for the driver's own portrait.
///
/// Deliberately the same shape as `payment/driver_qr_store.dart`, and for
/// the same reason: like the bank QR, this image never goes into a public
/// profile. A kind-0 event is world-readable and replicated forever, so a
/// face published there is a face anyone can harvest against a pubkey that
/// also carries a plate number and a live geohash. The portrait leaves this
/// device only inside a NIP-17 gift-wrapped offer, addressed to the one
/// passenger who published the request the driver chose to answer.
///
/// Behind an interface (mirroring `KeyStore` and `DriverQrStore`) so that
/// tests never touch the real filesystem.
abstract interface class DriverPhotoStore {
  Future<void> save(Uint8List jpegBytes);
  Future<Uint8List?> load();
  Future<void> clear();
}

/// Persists the portrait as a single file in the app's private documents
/// directory. Never `flutter_secure_storage`: a photograph is bytes, not a
/// key, and the platform keystore backends are not built for binary blobs
/// of this size.
///
/// [documentsDirectoryPath] is injected (typically
/// `() async => (await getApplicationDocumentsDirectory()).path`) rather
/// than called here, so tests can point it at a temp directory instead of
/// mocking a platform channel -- the same "keep the untestable plugin call
/// at the edge" shape as `FileDriverQrStore` and `GeolocatorLocationSource`.
class FileDriverPhotoStore implements DriverPhotoStore {
  final Future<String> Function() _documentsDirectoryPath;
  static const _fileName = 'driver_photo.jpg';

  const FileDriverPhotoStore(this._documentsDirectoryPath);

  Future<File> _file() async {
    final dir = await _documentsDirectoryPath();
    return File('$dir/$_fileName');
  }

  @override
  Future<void> save(Uint8List jpegBytes) async {
    final f = await _file();
    await f.writeAsBytes(jpegBytes, flush: true);
  }

  @override
  Future<Uint8List?> load() async {
    final f = await _file();
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

/// Test double, mirroring `InMemoryDriverProfileStore`.
class InMemoryDriverPhotoStore implements DriverPhotoStore {
  Uint8List? _value;

  @override
  Future<void> save(Uint8List jpegBytes) async => _value = jpegBytes;

  @override
  Future<Uint8List?> load() async => _value;

  @override
  Future<void> clear() async => _value = null;
}
