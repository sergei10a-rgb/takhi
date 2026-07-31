// SPDX-License-Identifier: AGPL-3.0-or-later

/// The driver-facing half of the portrait rule: everything a driver does to
/// get a usable face on their profile, and everything the screen has to say
/// back when it refuses.
///
/// The refusals get one test each rather than one shared "shows an error"
/// test on purpose. Each of the six is fixed by a *different* physical
/// action -- stand closer, get the other person out of the frame, pick a
/// different file, update the app -- so a screen that answered all six with
/// one sentence would be telling a driver nothing they can act on, and a
/// test that only asserted "some error appeared" would not notice.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/l10n/app_localizations.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi/nostr/relay_pool_provider.dart';
import 'package:takhi/profile/driver_photo_face_check.dart';
import 'package:takhi/profile/driver_photo_preview.dart';
import 'package:takhi/profile/driver_photo_store.dart';
import 'package:takhi/profile/driver_profile_page.dart';
import 'package:takhi/profile/driver_profile_store.dart';
import 'package:takhi/profile/profile_providers.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../support/fake_relay_socket.dart';

/// A real 1x1 PNG. `compressDriverPhoto` genuinely decodes whatever the
/// picker returns and `Image.memory` genuinely decodes what is stored, so
/// arbitrary bytes would fail these tests inside the image codec for reasons
/// that have nothing to do with what is being tested.
final _realImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

/// Bytes no decoder recognises -- the truncated download / renamed file case.
final _notAnImage = Uint8List.fromList(List<int>.filled(64, 7));

/// A face big enough and confident enough to pass every rule.
const _goodFace = DetectedFace(
  score: 0.95,
  left: 0.2,
  top: 0.2,
  width: 0.6,
  height: 0.6,
);

/// A confident face occupying well under [kMinFaceAreaFraction] of the frame
/// -- someone photographed standing next to their car.
const _distantFace = DetectedFace(
  score: 0.95,
  left: 0.45,
  top: 0.45,
  width: 0.1,
  height: 0.1,
);

/// A [FaceDetector] whose answer each test dictates, so every branch of
/// `faceCheckProblem` is reachable without a model, a native library or a
/// device.
class _ScriptedFaceDetector implements FaceDetector {
  List<DetectedFace> detections;
  Object? throwsInstead;

  _ScriptedFaceDetector() : detections = const [_goodFace];

  @override
  Future<List<DetectedFace>> detect(Uint8List jpegBytes) async {
    final failure = throwsInstead;
    if (failure != null) throw failure;
    return detections;
  }
}

/// Records what was asked for, so a test can tell "opened the camera" from
/// "opened the gallery" -- the two buttons are otherwise indistinguishable
/// from the outside, and swapping them would be invisible.
class _FakeImagePickerPlatform extends ImagePickerPlatform {
  Uint8List? nextPick;
  Object? throwsInstead;
  ImageSource? lastSource;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    lastSource = source;
    final failure = throwsInstead;
    if (failure != null) throw failure;
    final bytes = nextPick;
    if (bytes == null) return null;
    return XFile.fromData(bytes, name: 'portrait.png');
  }
}

/// A photo store whose `save` can be told to fail, for the "the disk said no"
/// branch -- the same shape as `_FakeDriverQrStore` in
/// `test/payment/driver_qr_capture_page_test.dart`.
class _FailingDriverPhotoStore implements DriverPhotoStore {
  Uint8List? _value;
  bool failNextSave = false;

  @override
  Future<void> save(Uint8List jpegBytes) async {
    if (failNextSave) {
      throw const FileSystemException('disk full', 'driver_photo.jpg');
    }
    _value = jpegBytes;
  }

  @override
  Future<Uint8List?> load() async => _value;

  @override
  Future<void> clear() async => _value = null;
}

void main() {
  late _FakeImagePickerPlatform picker;
  late _ScriptedFaceDetector detector;
  late InMemoryDriverProfileStore profileStore;
  late DriverPhotoStore photoStore;

  setUp(() {
    picker = _FakeImagePickerPlatform();
    ImagePickerPlatform.instance = picker;
    detector = _ScriptedFaceDetector();
    profileStore = InMemoryDriverProfileStore();
    photoStore = InMemoryDriverPhotoStore();
  });

  /// Pushes the page onto a route, mirroring how `SettingsPage` reaches it.
  Future<void> pump(WidgetTester tester) async {
    final keyStore = InMemoryKeyStore();
    await IdentityService(keyStore).createNew();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyStoreProvider.overrideWithValue(keyStore),
          relayPoolProvider.overrideWithValue(
            RelayPool([], connect: (_) => FakeRelaySocket()),
          ),
          driverProfileStoreProvider.overrideWithValue(profileStore),
          driverPhotoStoreProvider.overrideWithValue(photoStore),
          faceDetectorProvider.overrideWithValue(detector),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('mn'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DriverProfilePage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Taps a button that may be below the fold on this long form.
  ///
  /// `ensureVisible` rather than `scrollUntilVisible`: the latter insists on
  /// finding exactly one `Scrollable`, and every `TextField` on this form
  /// carries one of its own.
  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> pickFromGallery(WidgetTester tester) =>
      tapText(tester, 'Галерейгаас сонгох');

  // -------------------------------------------------------------------
  // The photo itself
  // -------------------------------------------------------------------

  testWidgets(
    'opens with an empty portrait, says a face is required, and says in as '
    'many words that the app cannot prove the face is yours',
    (tester) async {
      await pump(tester);

      expect(find.byType(DriverPhotoPreview), findsOneWidget);
      expect(
        tester
            .widget<DriverPhotoPreview>(find.byType(DriverPhotoPreview))
            .jpegBytes,
        isNull,
      );
      expect(
        find.text('Царай тань тод харагдсан зураг заавал хэрэгтэй.'),
        findsOneWidget,
      );
      // The honest half. A rider who believes a verification that does not
      // exist is worse off than one who knows the picture is unverified,
      // because they stop applying the judgement that actually protects
      // them -- so this sentence is load-bearing, not decoration.
      expect(find.textContaining('батлахгүй'), findsOneWidget);
    },
  );

  testWidgets(
    'a gallery photo with one clear face is compressed, stored and drawn in '
    'the portrait',
    (tester) async {
      picker.nextPick = _realImageBytes;
      await pump(tester);

      await pickFromGallery(tester);

      expect(picker.lastSource, ImageSource.gallery);
      final stored = await photoStore.load();
      expect(stored, isNotNull);
      // Stored as this app's own JPEG, never the picked bytes verbatim: the
      // whole point of the pipeline is that what is shown, what is stored
      // and what an offer carries are the same 512px, metadata-free image.
      expect(stored, isNot(_realImageBytes));
      expect(
        tester
            .widget<DriverPhotoPreview>(find.byType(DriverPhotoPreview))
            .jpegBytes,
        stored,
      );
    },
  );

  testWidgets('the camera button opens the camera, not the gallery', (
    tester,
  ) async {
    picker.nextPick = _realImageBytes;
    await pump(tester);

    await tapText(tester, 'Камераар авах');

    expect(picker.lastSource, ImageSource.camera);
    expect(await photoStore.load(), isNotNull);
  });

  testWidgets(
    'no face is answered with instructions to move closer -- never with an '
    'accusation, because the commonest cause is a real driver standing too '
    'far away',
    (tester) async {
      picker.nextPick = _realImageBytes;
      detector.detections = const [];
      await pump(tester);

      await pickFromGallery(tester);

      expect(find.textContaining('Царай олдсонгүй'), findsOneWidget);
      expect(await photoStore.load(), isNull);
    },
  );

  testWidgets('two people in the frame are refused as two people', (
    tester,
  ) async {
    picker.nextPick = _realImageBytes;
    detector.detections = const [_goodFace, _goodFace];
    await pump(tester);

    await pickFromGallery(tester);

    expect(find.textContaining('нэгээс олон хүн'), findsOneWidget);
    expect(await photoStore.load(), isNull);
  });

  testWidgets('a face too small in the frame is refused as too small', (
    tester,
  ) async {
    picker.nextPick = _realImageBytes;
    detector.detections = const [_distantFace];
    await pump(tester);

    await pickFromGallery(tester);

    expect(find.textContaining('хэтэрхий жижиг'), findsOneWidget);
    expect(await photoStore.load(), isNull);
  });

  testWidgets('a file that is not an image at all says so, rather than '
      'blaming the face', (tester) async {
    picker.nextPick = _notAnImage;
    await pump(tester);

    await pickFromGallery(tester);

    expect(find.textContaining('уншиж чадсангүй'), findsOneWidget);
    expect(await photoStore.load(), isNull);
  });

  testWidgets(
    'a checker that cannot run says the checker is broken, not that the '
    'photo is -- and stores nothing, because failing open would leave the '
    'promise on screen with the mechanism gone',
    (tester) async {
      picker.nextPick = _realImageBytes;
      detector.throwsInstead = const FaceDetectorUnavailableException(
        'no model bundled',
      );
      await pump(tester);

      await pickFromGallery(tester);

      expect(find.textContaining('шалгагч'), findsOneWidget);
      expect(await photoStore.load(), isNull);
    },
  );

  testWidgets(
    'a rejected photo leaves the previously accepted one in place -- picking '
    'a bad photo by mistake must not strand a working driver',
    (tester) async {
      picker.nextPick = _realImageBytes;
      await pump(tester);
      await pickFromGallery(tester);
      final good = await photoStore.load();
      expect(good, isNotNull);

      detector.detections = const [];
      await pickFromGallery(tester);

      expect(find.textContaining('Царай олдсонгүй'), findsOneWidget);
      expect(await photoStore.load(), good);
      expect(
        tester
            .widget<DriverPhotoPreview>(find.byType(DriverPhotoPreview))
            .jpegBytes,
        good,
      );
    },
  );

  testWidgets(
    'a denied camera permission is shown as a permission problem with a way '
    'out, instead of the button silently doing nothing',
    (tester) async {
      picker.throwsInstead = PlatformException(code: 'camera_access_denied');
      await pump(tester);

      await tapText(tester, 'Камераар авах');

      expect(find.textContaining('зөвшөөрөл'), findsOneWidget);
      // Not mistaken for a bad photograph: nothing about the picture was
      // ever seen.
      expect(find.textContaining('Царай олдсонгүй'), findsNothing);
    },
  );

  testWidgets('a picker that fails for any other reason says so plainly', (
    tester,
  ) async {
    picker.throwsInstead = PlatformException(code: 'multiple_request');
    await pump(tester);

    await pickFromGallery(tester);

    expect(find.textContaining('авч чадсангүй'), findsOneWidget);
  });

  testWidgets(
    'a photo that passes every check but cannot be written to disk reports '
    'the save, not the photo',
    (tester) async {
      final failing = _FailingDriverPhotoStore()..failNextSave = true;
      photoStore = failing;
      picker.nextPick = _realImageBytes;
      await pump(tester);

      await pickFromGallery(tester);

      expect(find.textContaining('хадгалж чадсангүй'), findsOneWidget);
    },
  );

  testWidgets('backing out of the picker changes nothing and says nothing', (
    tester,
  ) async {
    picker.nextPick = null;
    await pump(tester);

    await pickFromGallery(tester);

    expect(find.textContaining('Царай олдсонгүй'), findsNothing);
    expect(find.textContaining('зөвшөөрөл'), findsNothing);
    expect(await photoStore.load(), isNull);
  });

  testWidgets('a portrait saved earlier is loaded and shown when the page '
      'opens', (tester) async {
    await photoStore.save(_realImageBytes);
    await pump(tester);

    expect(
      tester
          .widget<DriverPhotoPreview>(find.byType(DriverPhotoPreview))
          .jpegBytes,
      _realImageBytes,
    );
  });

  // -------------------------------------------------------------------
  // Offer readiness, stated on the page rather than discovered at the
  // moment an offer is refused
  // -------------------------------------------------------------------

  testWidgets(
    'an empty profile says outright that no offer can be sent, and names the '
    'name as the missing half first',
    (tester) async {
      await pump(tester);

      expect(
        find.text('Овог, нэрээ бөглөтөл та зорчигчид санал илгээх боломжгүй.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a name typed but never saved must not be reported as ready: an offer is '
    'built out of the SAVED profile, so the notice asks for a save rather '
    'than claiming the driver is good to go',
    (tester) async {
      picker.nextPick = _realImageBytes;
      await pump(tester);

      await tester.enterText(
        find.byKey(const Key('driverProfileFamilyNameField')),
        'Б.',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Батбаяр',
      );
      await tester.pumpAndSettle();
      await pickFromGallery(tester);

      expect(find.textContaining('Нэрээ хадгалаагүй'), findsOneWidget);
      expect(
        find.text('Бэлэн. Та зорчигчдод санал илгээж чадна.'),
        findsNothing,
      );
      // And it does not ask them to fill in a name that is on screen in
      // front of them, which would read as a bug rather than as an
      // instruction.
      expect(
        find.text('Овог, нэрээ бөглөтөл та зорчигчид санал илгээх боломжгүй.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'with the name saved but no portrait, the notice moves on to the photo',
    (tester) async {
      await profileStore.save(
        const DriverProfile(
          familyName: 'Б.',
          givenName: 'Батбаяр',
          car: 'Prius 30',
          color: 'цагаан',
          plate: '1234УБА',
          kmTariffMnt: 1500,
        ),
      );
      await pump(tester);

      expect(
        find.text('Зургаа оруултал та зорчигчид санал илгээх боломжгүй.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a saved name plus a stored portrait -- exactly what an offer carries -- '
    'turns the warning into a plain statement that offers can now be sent',
    (tester) async {
      await profileStore.save(
        const DriverProfile(
          familyName: 'Б.',
          givenName: 'Батбаяр',
          car: 'Prius 30',
          color: 'цагаан',
          plate: '1234УБА',
          kmTariffMnt: 1500,
        ),
      );
      await photoStore.save(_realImageBytes);
      await pump(tester);

      expect(
        find.text('Бэлэн. Та зорчигчдод санал илгээж чадна.'),
        findsOneWidget,
      );
      expect(find.textContaining('санал илгээх боломжгүй'), findsNothing);
    },
  );

  testWidgets(
    'saving a typed name flips the notice off "not saved yet" without the '
    'driver having to reopen the page',
    (tester) async {
      await photoStore.save(_realImageBytes);
      await pump(tester);

      await tester.enterText(
        find.byKey(const Key('driverProfileFamilyNameField')),
        'Б.',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Батбаяр',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileCarField')),
        'Prius 30',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileColorField')),
        'цагаан',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfilePlateField')),
        '1234УБА',
      );
      await tester.enterText(
        find.byKey(const Key('driverProfileKmTariffField')),
        '1500',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Нэрээ хадгалаагүй'), findsOneWidget);

      await tapText(tester, 'Хадгалах');

      // The page pops on save, so what this proves is the store, not the
      // notice: the name that was typed is now the name an offer is built
      // from.
      final saved = await profileStore.load();
      expect(saved!.fullName, 'Б. Батбаяр');
    },
  );

  // -------------------------------------------------------------------
  // Name fields
  // -------------------------------------------------------------------

  testWidgets(
    'a name carrying a digit is refused under the field that carries it, '
    'naming what is allowed',
    (tester) async {
      await pump(tester);

      await tester.enterText(
        find.byKey(const Key('driverProfileNameField')),
        'Бат1',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Зөвхөн үсэг'), findsOneWidget);
    },
  );

  testWidgets('a name typed and then cleared says it cannot be left empty', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(
      find.byKey(const Key('driverProfileNameField')),
      'Бат',
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('driverProfileNameField')), '');
    await tester.pumpAndSettle();

    expect(find.text('Заавал бөглөнө.'), findsOneWidget);
  });

  testWidgets(
    'a form nobody has touched yet does not shout: no empty-name verdict '
    'before a single keystroke',
    (tester) async {
      await pump(tester);

      expect(find.text('Заавал бөглөнө.'), findsNothing);
    },
  );

  testWidgets(
    'a name pre-filled from a saved profile is not marked as touched either',
    (tester) async {
      await profileStore.save(
        const DriverProfile(
          familyName: 'Ц.',
          givenName: 'Сараа',
          car: 'Sonata',
          color: 'улаан',
          plate: '4321ЭЖӨ',
          kmTariffMnt: 2200,
        ),
      );
      await pump(tester);

      expect(find.text('Заавал бөглөнө.'), findsNothing);
      expect(find.textContaining('Зөвхөн үсэг'), findsNothing);
    },
  );
}
