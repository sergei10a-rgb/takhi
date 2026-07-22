// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

/// Local-only storage for the driver's own bank QR image (spec §8: "QR
/// зураг зөвхөн утсан дээрээ локал хадгалагдана" — never published to any
/// public profile, never leaves the device except when the driver
/// deliberately shows their own screen or, in a later plan, sends it
/// DM-encrypted to one specific rider). Abstracted behind an interface
/// (mirrors `KeyStore` in `identity/identity_service.dart`) so trip-
/// completion UI tests never touch the real filesystem directly.
abstract interface class DriverQrStore {
  Future<void> save(Uint8List pngBytes);
  Future<Uint8List?> load();
  Future<void> clear();
}

/// Persists the QR image as a single file in the app's private documents
/// directory. Never touches `flutter_secure_storage` — a bank QR image is
/// bytes, not a secret key, and secure storage's platform keystore
/// backends are not designed for arbitrary-sized binary blobs.
///
/// [documentsDirectoryPath] is injected (typically
/// `() async => (await getApplicationDocumentsDirectory()).path` from
/// `path_provider`) rather than called directly here, so tests can point
/// this at a real temp directory instead of mocking a platform channel —
/// the same "keep the untestable plugin call at the edge" shape as
/// `LocationSource`/`GeolocatorLocationSource` (Task 1).
class FileDriverQrStore implements DriverQrStore {
  final Future<String> Function() _documentsDirectoryPath;
  static const _fileName = 'driver_qr.bin';

  const FileDriverQrStore(this._documentsDirectoryPath);

  Future<File> _file() async {
    final dir = await _documentsDirectoryPath();
    return File('$dir/$_fileName');
  }

  @override
  Future<void> save(Uint8List pngBytes) async {
    final f = await _file();
    await f.writeAsBytes(pngBytes, flush: true);
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
