// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/takhi_theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/notice_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_heading.dart';
import '../widgets/takhi_sheet.dart';
import 'driver_offer_eligibility.dart';
import 'driver_photo_preview.dart';
import 'driver_photo_rules.dart';
import 'profile_providers.dart';

/// The longest edge the image picker is asked to hand back.
///
/// Well above [kDriverPhotoMaxEdgePx], so nothing this app's own pipeline
/// needs is thrown away before it gets there -- but bounded, because the
/// pipeline decodes in pure Dart. A modern phone camera produces 50-megapixel
/// files, and decoding one of those into an uncompressed bitmap costs
/// hundreds of megabytes on a device with far less to spare. The platform
/// downsample is native, cheap, and happens before any of that; asking for it
/// is the difference between "the profile screen is slow for a second" and
/// "the app was killed while the driver was setting up".
const _kPickerMaxEdgePx = 1600.0;

/// Why the last attempt never reached the face check at all.
///
/// Kept apart from [DriverPhotoRejection] because these say nothing about
/// the photograph -- in every one of them no picture was ever looked at.
/// Folding them together would let the screen tell a driver whose camera
/// permission is switched off to "hold the phone closer", which is advice
/// about a photo that does not exist.
enum _PhotoPickFailure {
  /// The OS refused: camera or photo-library permission is not granted.
  permissionDenied,

  /// The picker itself failed for some other reason -- another request
  /// already in flight, a plugin error, an unreadable temp file.
  pickFailed,

  /// The photo passed every check and then could not be written to disk.
  saveFailed,
}

/// One answer the profile cannot be saved without.
///
/// A named thing rather than a bare label string, because the same list has
/// to do two jobs that must never disagree: decide whether the save button
/// is live, and say out loud which boxes are keeping it grey. Naming the
/// answers keeps the rule in one place and leaves the wording to
/// [_DriverProfilePageState._requiredAnswerLabel].
///
/// The three optional things on this form are absent by design: the portrait
/// (it is not what saving publishes), the stopped-time rate and the
/// trip-duration rate (an empty rate box is a driver saying that part of the
/// price is free, which is an answer).
enum _RequiredAnswer {
  familyName,
  givenName,
  car,
  color,
  plate,

  /// The distance rate. The one rate that *is* required: a metered offer is
  /// built out of it, so a profile without it cannot price a trip at all.
  kmTariff,
}

/// Whether this driver can send offers, and if not, what the next action is.
///
/// Four states rather than [DriverOfferBlock]'s two, because the page knows
/// something the core cannot: what is currently *typed* as opposed to
/// stored. `OfferService.sendOffer` reads the saved profile
/// (`driver_inbox_page.dart` builds the payload out of
/// `DriverProfileService.loadLocalProfile`), so a name sitting in a text
/// box that has never been saved does not reach an offer at all -- and a
/// notice built on the text boxes would cheerfully say "ready" about a
/// driver whose very next offer is refused.
enum _Readiness {
  /// The saved name and the stored photo are both there.
  ready,

  /// Nothing usable is even typed in the two name boxes.
  needsName,

  /// The name is saved; there is no portrait.
  needsPhoto,

  /// A usable name is typed but has not been saved, so it is not yet part
  /// of any offer. This is the state a notice built on the text fields
  /// would have got wrong, and the one whose wording matters most: telling
  /// a driver to "fill in your name" while their name is on screen in front
  /// of them reads as a bug in the app.
  needsSave,
}

/// Lets a driver fill in and publish their public takhi profile (spec §6):
/// portrait, name, car, color, plate, and the three rates a metered price is
/// made of -- the km-tariff, the §7.4 stopped-time rate, and the rate
/// charged on the whole trip's duration. Saving publishes the signed
/// kind-0 event to every connected relay *and* caches it locally
/// (`DriverProfileService.publishAndSave`) so all three rates are available
/// instantly to the §7.2 GPS-taximeter offer flow without a relay round
/// trip. They travel together everywhere downstream: a trip can never end
/// up running on this driver's distance rate and nobody's stopped-time one.
/// Reached from `SettingsPage`, which pushes it -- so the `AppBar` carries
/// the usual back arrow.
///
/// **The portrait and the two name parts are never published.** They are
/// held on this device and travel to one passenger at a time inside the
/// NIP-17 gift-wrapped offer. A kind-0 event is world-readable and
/// replicated forever; a face published there is a face anyone can harvest
/// against a pubkey that also carries a plate number and, while the driver
/// is working, a live geohash. Only the car, the colour, the plate and the
/// rates go to a relay.
///
/// The portrait is saved the moment it is accepted, not when the form is
/// saved. It goes to a different store (`DriverPhotoStore`, a private file)
/// through a different check, and the two have no reason to be atomic: a
/// driver who sets a photo and then leaves without touching the rates has
/// still gained a portrait, and one whose face check fails has not lost the
/// car details they had already typed.
///
/// That back is deliberately left unguarded (no `ConfirmLeaveScope`,
/// unlike a running trip or meter): leaving with a half-filled form costs
/// only re-typing it, since nothing is published or cached until
/// `publishAndSave` runs, and the previously saved profile stays intact.
///
/// The form is in named parts, and that is the point of the layout rather
/// than decoration. Identical outlined boxes with floating labels gave no
/// clue that some describe a car a rider has to recognise at the kerb and
/// others are a price, and Material's floating labels slid away the moment a
/// field was filled -- so a driver checking whether `1500` was the
/// per-kilometre or the per-minute rate had to clear the box to find out.
/// Standing labels and headings answer both at a glance.
class DriverProfilePage extends ConsumerStatefulWidget {
  const DriverProfilePage({super.key});

  @override
  ConsumerState<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends ConsumerState<DriverProfilePage> {
  /// Овог and нэр. Two boxes rather than one, because a passenger reading
  /// «Б. Батбаяр» at a car window is reading two different things -- and
  /// because the offer carries them as two fields, so joining and
  /// re-splitting a single box would have to guess where the split was.
  ///
  /// Neither is ever published: `DriverProfileService.publishAndSave`
  /// writes them to the local store only.
  final _familyName = TextEditingController();
  final _givenName = TextEditingController();
  final _car = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  final _kmTariff = TextEditingController();

  /// The §7.4 stopped-time rate. Deliberately *not* part of
  /// [_missingForSave]: a
  /// driver who never fills it in is saying stopped time is free, which is a
  /// complete price, not an incomplete form -- and is exactly how every
  /// profile saved before this field existed already reads.
  final _waitTariff = TextEditingController();

  /// The rate charged on every minute of the trip, moving or stopped, from
  /// the first GPS fix to the last. Out of [_missingForSave] for exactly the
  /// argument [_waitTariff] makes: a blank box is a driver saying this rate
  /// is not part of their price, which is a finished answer rather than a
  /// half-filled form -- and it is how every profile saved before this field
  /// existed already reads, so gating the button on it would lock a driver
  /// out of their own saved profile the first time they opened this screen
  /// after an update.
  ///
  /// Nothing here or in [_save] looks at what [_waitTariff] holds. The two
  /// rates are independent numbers a driver sets independently, and the app
  /// does not have an opinion about which combination is right.
  final _durationTariff = TextEditingController();
  bool _saving = false;

  /// Whether the driver has typed in each name box since the page opened.
  ///
  /// A verdict is only shown for a box that has been touched. A form that
  /// opens with two red "this cannot be empty" lines is scolding somebody
  /// for not having filled in a form they have just been handed; the
  /// readiness notice at the top of the page is what states the requirement
  /// up front, calmly, without pointing at any particular box. Pre-filling
  /// from a saved profile does not count as touching -- the driver did not
  /// type it.
  bool _familyTouched = false;
  bool _givenTouched = false;

  /// The two name parts as the *store* holds them, which is what an offer
  /// is built out of. Kept beside the controllers rather than derived from
  /// them: the difference between "typed" and "saved" is exactly the
  /// distinction [_readiness] exists to make.
  String? _savedFamilyName;
  String? _savedGivenName;

  /// The accepted portrait, or null while there is none.
  Uint8List? _photo;

  /// Why the last picked photo was refused, or null.
  DriverPhotoRejection? _rejection;

  /// Why the last attempt never produced a photo to check, or null.
  _PhotoPickFailure? _pickFailure;

  /// True from the moment a picked image is handed to the pipeline until it
  /// has been compressed, checked and either stored or refused. Both picker
  /// buttons go dead for that span: the work is synchronous image decoding,
  /// and a second pick started on top of the first would race it to the
  /// store.
  bool _checkingPhoto = false;

  @override
  void initState() {
    super.initState();
    ref.read(driverProfileServiceProvider).loadLocalProfile().then((profile) {
      if (profile == null || !mounted) return;
      _familyName.text = profile.familyName ?? '';
      _givenName.text = profile.givenName ?? '';
      _car.text = profile.car;
      _color.text = profile.color;
      _plate.text = profile.plate;
      _kmTariff.text = profile.kmTariffMnt.toString();
      // An unset minute rate reopens as an empty box rather than as a 0, the
      // same rule the taximeter's tariff form states and for the same
      // reason: an unasked-for zero in a price box reads as a rate somebody
      // set deliberately, and a driver reopening this page cannot otherwise
      // tell a rate they priced at nothing from one they never touched.
      //
      // The km-tariff keeps its number even at zero, because there a 0 is
      // not a price at all -- it is the one rate `_missingForSave` requires,
      // so blanking it would silently disarm the save button on a profile
      // the driver had already saved.
      _waitTariff.text = profile.waitTariffMntPerMinute == 0
          ? ''
          : profile.waitTariffMntPerMinute.toString();
      _durationTariff.text = profile.durationTariffMntPerMinute == 0
          ? ''
          : profile.durationTariffMntPerMinute.toString();
      // The readiness notice reads these, and filling controllers does not
      // itself rebuild anything.
      setState(() {
        _savedFamilyName = profile.familyName;
        _savedGivenName = profile.givenName;
      });
    });
    ref.read(driverPhotoServiceProvider).load().then(
      (bytes) {
        if (bytes == null || !mounted) return;
        setState(() => _photo = bytes);
      },
      // A portrait that cannot be read leaves the page in exactly the
      // state a driver who never set one is in: empty circle, "add a
      // photo before you can send offers". That is the honest reading --
      // as far as this app is now concerned there is no usable portrait
      // -- and it is recoverable by picking another, which a crashed
      // settings screen would not be.
      //
      // Caught broadly for the same reason `checkDriverPhotoFace` is:
      // the thrower is a platform plugin resolving a documents
      // directory, and this layer cannot enumerate the ways an OS
      // refuses that. What it must never do is take the page down.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _familyName.dispose();
    _givenName.dispose();
    _car.dispose();
    _color.dispose();
    _plate.dispose();
    _kmTariff.dispose();
    _waitTariff.dispose();
    _durationTariff.dispose();
    super.dispose();
  }

  /// Which of the required answers are still not there, in the order their
  /// boxes appear on the page -- so the line under the save button reads in
  /// the same order the driver would scroll to fix them.
  ///
  /// Both name parts must be present *and* be usable names -- the same rule
  /// `driverOfferBlock` applies at the point an offer is sent. Checking only
  /// for non-emptiness here would let a driver save «Бат1», feel finished,
  /// and then find every offer refused with no idea why.
  ///
  /// The portrait is deliberately *not* part of this. Saving publishes the
  /// car and the rates, which are useful on their own and are what the
  /// taximeter needs; gating them on a photo would leave a driver whose face
  /// check keeps failing unable to record their own tariff either. The
  /// stopped-time and trip-duration rates are not part of it either, for the
  /// reason their own fields document: a blank one is a price, not a gap.
  List<_RequiredAnswer> get _missingForSave => [
    if (!isValidDriverNamePart(_familyName.text)) _RequiredAnswer.familyName,
    if (!isValidDriverNamePart(_givenName.text)) _RequiredAnswer.givenName,
    if (_car.text.trim().isEmpty) _RequiredAnswer.car,
    if (_color.text.trim().isEmpty) _RequiredAnswer.color,
    if (_plate.text.trim().isEmpty) _RequiredAnswer.plate,
    if (_parsePrice(_kmTariff.text) == null) _RequiredAnswer.kmTariff,
  ];

  /// A price box's contents as a non-negative number of tögrög, or `null`
  /// when the box does not hold one. The taximeter's own tariff form has had
  /// this rule since it was written (`TaximeterPage._parsePrice`); this form
  /// was still using a bare `int.tryParse`, which accepts a minus sign.
  ///
  /// A negative rate is not a curiosity here. `TextInputType.number` makes
  /// one awkward to type but does nothing about a paste, and these three
  /// numbers are published in a kind-0 and then multiplied by kilometres and
  /// by minutes: a negative per-minute rate subtracts money for as long as
  /// the trip lasts, unbounded by how far the car actually went, and can
  /// carry a whole fare below zero. Refusing it at the box is the only place
  /// the refusal is cheap -- past here it is on a relay, replicated, and
  /// already inside somebody's offer.
  ///
  /// Whitespace is stripped rather than rejected, matching the meter for the
  /// reason it gives: «15 000» is simply how a price gets written by hand.
  static int? _parsePrice(String text) {
    final value = int.tryParse(text.replaceAll(RegExp(r'\s'), ''));
    return value == null || value < 0 ? null : value;
  }

  /// Whether this driver can send offers right now, and if not, what to do
  /// about it.
  ///
  /// The ready/not-ready half is decided by [driverOfferBlock] -- the same
  /// core function `OfferService.sendOffer` enforces -- asked about the same
  /// values an offer would actually carry: the *saved* name parts and the
  /// stored portrait, never the text boxes. That is what makes "ready"
  /// impossible to say about a driver the send path would refuse, and it
  /// cannot drift, because there is only one rule and both callers ask it.
  ///
  /// The text boxes are consulted only to choose between two wordings for
  /// the same refusal.
  _Readiness get _readiness {
    final block = driverOfferBlock(
      familyName: _savedFamilyName,
      givenName: _savedGivenName,
      photoJpeg: _photo,
    );
    if (block == null) return _Readiness.ready;
    if (!isValidDriverNamePart(_familyName.text) ||
        !isValidDriverNamePart(_givenName.text)) {
      return _Readiness.needsName;
    }
    // A usable name is on screen. Either it is already saved and the
    // portrait is what is missing, or saving it is the next step.
    return block == DriverOfferBlock.missingPhoto
        ? _Readiness.needsPhoto
        : _Readiness.needsSave;
  }

  Future<void> _save() async {
    final identity = ref.read(currentIdentityProvider).valueOrNull;
    final kmTariffMnt = _parsePrice(_kmTariff.text);
    if (identity == null || kmTariffMnt == null) return;
    final familyName = normalizeDriverNamePart(_familyName.text);
    final givenName = normalizeDriverNamePart(_givenName.text);
    setState(() => _saving = true);
    try {
      await ref
          .read(driverProfileServiceProvider)
          .publishAndSave(
            privHex: identity.privHex,
            now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            // Normalized, not raw: a name pasted with a double space or a
            // line break in it is stored the way it will be drawn.
            familyName: familyName,
            givenName: givenName,
            car: _car.text.trim(),
            color: _color.text.trim(),
            plate: _plate.text.trim(),
            kmTariffMnt: kmTariffMnt,
            // Blank or unparseable reads as zero -- "stopping is free" --
            // rather than blocking the save. Unlike the km-tariff, which a
            // metered offer cannot be built without, a missing stopped-time
            // rate still describes a complete price.
            waitTariffMntPerMinute: _parsePrice(_waitTariff.text) ?? 0,
            // Same reading, same reason: an empty box means this driver does
            // not charge for the trip's duration, and that is an answer.
            // Written on every save, including the zero, so a driver who
            // clears a rate they used to charge actually stops charging it
            // -- omitting it would leave the previous number in the store.
            durationTariffMntPerMinute: _parsePrice(_durationTariff.text) ?? 0,
          );
      // Only after the store has actually taken them. Setting these
      // optimistically would put the page back into the state this whole
      // distinction exists to prevent: claiming a name is part of an offer
      // when the write that would have made it so has failed.
      if (mounted) {
        setState(() {
          _savedFamilyName = familyName;
          _savedGivenName = givenName;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.driverProfileSavedConfirmation)));
    Navigator.of(context).pop();
  }

  /// Picks an image from [source], runs it through the portrait pipeline,
  /// and either stores it or explains why not.
  ///
  /// Nothing here throws at the user. A photograph a driver picked is
  /// untrusted input that arrives from a camera, a share sheet, a downloads
  /// folder or a messaging app, and every way it can go wrong -- an
  /// unreadable file, a refused permission, a full disk, a checker that
  /// cannot start -- has to become a sentence on this screen rather than a
  /// red crash page in the middle of setting up an account.
  Future<void> _pickPhoto(ImageSource source) async {
    setState(() {
      _rejection = null;
      _pickFailure = null;
    });

    final Uint8List raw;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: _kPickerMaxEdgePx,
        maxHeight: _kPickerMaxEdgePx,
      );
      // Backing out of the picker is a decision, not a failure. Saying
      // anything here would be answering a question the driver withdrew.
      if (picked == null) return;
      raw = await picked.readAsBytes();
    } on PlatformException catch (e) {
      // `camera_access_denied` / `photo_access_denied` are the two the
      // plugin raises for a refused permission; everything else is the
      // plugin or the OS failing at something the driver cannot fix by
      // visiting settings, so it must not be reported as a permission.
      _reportPickFailure(
        e.code.contains('access_denied')
            ? _PhotoPickFailure.permissionDenied
            : _PhotoPickFailure.pickFailed,
      );
      return;
    } on FileSystemException {
      // The picker handed back a path whose temp file has already gone.
      _reportPickFailure(_PhotoPickFailure.pickFailed);
      return;
    }

    if (!mounted) return;
    setState(() => _checkingPhoto = true);

    final DriverPhotoRejection? rejection;
    Uint8List? stored;
    try {
      final service = ref.read(driverPhotoServiceProvider);
      rejection = await service.replacePhoto(raw);
      // Read back rather than reusing the bytes handed in: what the profile
      // draws must be what was actually stored and what an offer will
      // carry, not the original the driver picked.
      if (rejection == null) stored = await service.load();
    } on FileSystemException {
      _reportPickFailure(_PhotoPickFailure.saveFailed);
      return;
    }

    if (!mounted) return;
    setState(() {
      _checkingPhoto = false;
      _rejection = rejection;
      // A refusal leaves the previous portrait exactly where it was.
      // Clearing it would strand a driver who had a working photo and
      // picked a blurry one by mistake: no photo means no offers.
      if (stored != null) _photo = stored;
    });
  }

  void _reportPickFailure(_PhotoPickFailure failure) {
    if (!mounted) return;
    setState(() {
      _checkingPhoto = false;
      _pickFailure = failure;
    });
  }

  /// The one sentence to show under the picker buttons, or null when the
  /// last attempt went fine.
  ///
  /// A failure that stopped the attempt before any pixel was examined wins
  /// over a stale rejection, because it is the thing that just happened.
  String? _photoProblemMessage(AppLocalizations l) {
    final failure = _pickFailure;
    if (failure != null) {
      return switch (failure) {
        _PhotoPickFailure.permissionDenied =>
          l.driverProfilePhotoPermissionDeniedHint,
        _PhotoPickFailure.pickFailed => l.driverProfilePhotoPickFailedHint,
        _PhotoPickFailure.saveFailed => l.driverProfilePhotoSaveFailedHint,
      };
    }
    final rejection = _rejection;
    if (rejection == null) return null;
    return switch (rejection) {
      DriverPhotoRejection.undecodable => l.driverPhotoRejectedUndecodable,
      DriverPhotoRejection.tooLargeAfterCompression =>
        l.driverPhotoRejectedTooLarge,
      DriverPhotoRejection.noFaceFound => l.driverPhotoRejectedNoFace,
      DriverPhotoRejection.multipleFaces => l.driverPhotoRejectedMultipleFaces,
      DriverPhotoRejection.faceTooSmall => l.driverPhotoRejectedFaceTooSmall,
      DriverPhotoRejection.faceCheckUnavailable =>
        l.driverPhotoRejectedCheckUnavailable,
    };
  }

  /// What to call one still-missing answer in the line under the save
  /// button.
  ///
  /// Deliberately the very same label that stands above the box, unit
  /// brackets and all. A prompt that renames things -- "your tariff" for a
  /// box captioned «Км-тариф (₮/км)» -- makes the driver translate before
  /// they can start looking, and this line's whole job is to point at a box.
  String _requiredAnswerLabel(AppLocalizations l, _RequiredAnswer answer) =>
      switch (answer) {
        _RequiredAnswer.familyName => l.driverProfileFamilyNameFieldLabel,
        _RequiredAnswer.givenName => l.driverProfileNameFieldLabel,
        _RequiredAnswer.car => l.driverProfileCarFieldLabel,
        _RequiredAnswer.color => l.driverProfileColorFieldLabel,
        _RequiredAnswer.plate => l.driverProfilePlateFieldLabel,
        _RequiredAnswer.kmTariff => l.driverProfileKmTariffFieldLabel,
      };

  /// The verdict under one name box, or null while there is nothing to say.
  String? _nameProblem(
    AppLocalizations l,
    TextEditingController controller,
    bool touched,
  ) {
    if (!touched) return null;
    final problem = driverNamePartProblem(controller.text);
    if (problem == null) return null;
    return switch (problem) {
      DriverNameProblem.empty => l.driverNameProblemEmpty,
      DriverNameProblem.tooLong => l.driverNameProblemTooLong,
      DriverNameProblem.disallowedCharacter =>
        l.driverNameProblemDisallowedCharacter,
      DriverNameProblem.notCyrillic => l.driverNameProblemNotCyrillic,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    // `initState` already awaits the local store read to pre-fill the
    // fields; watching here just keeps this widget subscribed for
    // rebuilds if identity state ever changes later, matching every other
    // identity-dependent page's convention (e.g. `PassengerRidePage`).
    ref.watch(currentIdentityProvider);

    final readiness = _readiness;
    final photoProblem = _photoProblemMessage(l);
    // Read once and reused by both the line and the button below it, so the
    // two are answering the same question about the same frame.
    final missingForSave = _missingForSave;

    return Scaffold(
      backgroundColor: surfaces.canvas,
      appBar: AppBar(
        backgroundColor: surfaces.canvas,
        foregroundColor: surfaces.onSheet,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  TakhiSpace.md,
                  TakhiSpace.lg,
                  TakhiSpace.md,
                  TakhiSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeading(
                      title: l.driverProfileTitle,
                      subtitle: l.driverProfileSubtitle,
                    ),
                    const SizedBox(height: TakhiSpace.lg),
                    // First thing on the page, before any field. A driver
                    // who cannot send offers has to learn that here, while
                    // they are on the screen that fixes it -- not at the
                    // moment they tap "send offer" on a request that is
                    // about to expire.
                    _ReadinessNotice(readiness: readiness),
                    const SizedBox(height: TakhiSpace.xl),

                    SectionHeading(
                      title: l.driverProfilePhotoSectionTitle,
                      subtitle: l.driverProfilePhotoRequiredHint,
                      compact: true,
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    Center(child: DriverPhotoPreview(jpegBytes: _photo)),
                    const SizedBox(height: TakhiSpace.md),
                    _PickPhotoButton(
                      key: const Key('driverProfileTakePhotoButton'),
                      label: l.driverProfileTakePhotoAction,
                      icon: Icons.photo_camera_outlined,
                      onPressed: _checkingPhoto
                          ? null
                          : () => _pickPhoto(ImageSource.camera),
                    ),
                    const SizedBox(height: TakhiSpace.xs),
                    _PickPhotoButton(
                      key: const Key('driverProfileChoosePhotoButton'),
                      label: l.driverProfileChoosePhotoAction,
                      icon: Icons.photo_library_outlined,
                      onPressed: _checkingPhoto
                          ? null
                          : () => _pickPhoto(ImageSource.gallery),
                    ),
                    if (_checkingPhoto) ...[
                      const SizedBox(height: TakhiSpace.sm),
                      Text(
                        l.driverProfilePhotoCheckingLabel,
                        textAlign: TextAlign.center,
                        style: TakhiType.support.copyWith(
                          color: surfaces.muted,
                        ),
                      ),
                    ],
                    if (photoProblem != null) ...[
                      const SizedBox(height: TakhiSpace.md),
                      // Clay, not error red: none of these is a fault of
                      // the driver's, and all of them are fixed by the next
                      // tap. Most of the time «no face found» is an honest
                      // driver standing too far from the camera.
                      NoticeCard(
                        icon: Icons.info_outline,
                        text: photoProblem,
                        accent: TakhiAccent.clay,
                      ),
                    ],
                    const SizedBox(height: TakhiSpace.md),
                    // The honest limit, in the driver's own view, where the
                    // promise is being made. The check can say "there is one
                    // human face here" and nothing more: a friend's photo, a
                    // stranger's photo off the internet, or a photograph of
                    // another phone's screen all pass it. Leaving that
                    // unsaid would let both sides believe in a verification
                    // that does not exist -- and a passenger who trusts a
                    // badge that means nothing stops applying the judgement
                    // that actually protects them.
                    NoticeCard(
                      icon: Icons.shield_outlined,
                      text: l.driverProfilePhotoNotProofDisclaimer,
                      accent: TakhiAccent.sky,
                    ),
                    const SizedBox(height: TakhiSpace.xl),

                    SectionHeading(
                      title: l.driverProfileNameSectionTitle,
                      compact: true,
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileFamilyNameField'),
                      label: l.driverProfileFamilyNameFieldLabel,
                      icon: Icons.badge,
                      accent: TakhiAccent.steppe,
                      controller: _familyName,
                      errorText: _nameProblem(l, _familyName, _familyTouched),
                      onChanged: (_) => setState(() => _familyTouched = true),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileNameField'),
                      label: l.driverProfileNameFieldLabel,
                      icon: Icons.person,
                      accent: TakhiAccent.steppe,
                      controller: _givenName,
                      errorText: _nameProblem(l, _givenName, _givenTouched),
                      onChanged: (_) => setState(() => _givenTouched = true),
                    ),
                    const SizedBox(height: TakhiSpace.xl),

                    SectionHeading(
                      title: l.driverProfileVehicleSectionTitle,
                      compact: true,
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileCarField'),
                      label: l.driverProfileCarFieldLabel,
                      icon: Icons.directions_car,
                      accent: TakhiAccent.steppe,
                      controller: _car,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileColorField'),
                      label: l.driverProfileColorFieldLabel,
                      icon: Icons.palette,
                      accent: TakhiAccent.steppe,
                      controller: _color,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfilePlateField'),
                      label: l.driverProfilePlateFieldLabel,
                      icon: Icons.confirmation_number,
                      accent: TakhiAccent.steppe,
                      controller: _plate,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.xl),

                    SectionHeading(
                      title: l.driverProfilePriceSectionTitle,
                      compact: true,
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileKmTariffField'),
                      label: l.driverProfileKmTariffFieldLabel,
                      icon: Icons.payments,
                      controller: _kmTariff,
                      keyboardType: TextInputType.number,
                      // What the number actually decides. Without it the
                      // rate reads as a suggestion rather than as the
                      // figure a metered trip is billed on.
                      hint: l.driverProfileKmTariffHint,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    LabeledField(
                      key: const Key('driverProfileWaitTariffField'),
                      label: l.driverProfileWaitTariffFieldLabel,
                      icon: Icons.hourglass_bottom,
                      controller: _waitTariff,
                      keyboardType: TextInputType.number,
                      // A driver pricing a jam should not have to guess
                      // whether an empty box means "free" or "not set yet".
                      hint: l.driverProfileWaitTariffHint,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: TakhiSpace.md),
                    // Third and last, under the two rates it is easiest to
                    // confuse it with. The hint carries the whole
                    // distinction -- this one runs from the first GPS fix
                    // to the last whatever the car is doing -- because the
                    // label alone («Аяллын хугацаа») could just as easily
                    // be read as the one above it.
                    LabeledField(
                      key: const Key('driverProfileDurationTariffField'),
                      label: l.driverProfileDurationTariffFieldLabel,
                      icon: Icons.timer,
                      controller: _durationTariff,
                      keyboardType: TextInputType.number,
                      hint: l.driverProfileDurationTariffHint,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
            TakhiSheet(
              showHandle: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Above the button rather than below it. The sheet's lower
                  // padding is the system gesture inset, so a line put under
                  // the button would sit on the home indicator -- and the
                  // button stays the last thing on the sheet, as it is on
                  // every other sheet in this app.
                  if (missingForSave.isNotEmpty) ...[
                    Text(
                      key: const Key('driverProfileSaveBlockedHint'),
                      l.driverProfileSaveBlockedHint(
                        // A bare comma-space join rather than a localised
                        // list format: Mongolian and English punctuate a
                        // short enumeration the same way, and the names
                        // themselves are already localised.
                        missingForSave
                            .map((answer) => _requiredAnswerLabel(l, answer))
                            .join(', '),
                      ),
                      style: TakhiType.support.copyWith(color: surfaces.muted),
                    ),
                    const SizedBox(height: TakhiSpace.sm),
                  ],
                  PrimaryButton(
                    label: l.saveDriverProfileAction,
                    loading: _saving,
                    // The list read above, not a second call to `_canSave`.
                    // Both answer identically inside one synchronous build,
                    // so this fixes nothing today -- it makes the claim the
                    // comment on `missingForSave` already makes actually
                    // true, which is the only thing keeping the hint and the
                    // button from ever disagreeing about the same frame.
                    onPressed: missingForSave.isEmpty ? _save : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether this driver can send offers at all, stated on the page that fixes
/// it.
///
/// Always present, in both of its forms, rather than appearing only when
/// something is wrong. A notice that shows up only on failure leaves a
/// driver who has just finished setting up with no confirmation that they
/// have -- and the whole reason this block exists is that the requirement is
/// otherwise invisible until a passenger is already waiting.
class _ReadinessNotice extends StatelessWidget {
  final _Readiness readiness;

  const _ReadinessNotice({required this.readiness});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return switch (readiness) {
      // Steppe is this app's "confirmed, in order" family.
      _Readiness.ready => NoticeCard(
        icon: Icons.check_circle_outline,
        text: l.driverProfileOfferReadyNotice,
        accent: TakhiAccent.steppe,
      ),
      // One missing thing at a time, name first -- the same order
      // `driverOfferBlock` reports them in, and the cheaper of the two to
      // fix. A driver told to add a photo who then discovers they also need
      // a name has been sent back twice.
      _Readiness.needsName => NoticeCard(
        icon: Icons.error_outline,
        text: l.driverProfileOfferBlockedNameNotice,
        accent: TakhiAccent.clay,
      ),
      _Readiness.needsPhoto => NoticeCard(
        icon: Icons.error_outline,
        text: l.driverProfileOfferBlockedPhotoNotice,
        accent: TakhiAccent.clay,
      ),
      // Gold, not clay: nothing is wrong and nothing is missing -- the work
      // is done and one tap away from counting. Clay here would read as a
      // problem with the name the driver just typed correctly.
      _Readiness.needsSave => NoticeCard(
        icon: Icons.save_outlined,
        text: l.driverProfileOfferBlockedUnsavedNotice,
        accent: TakhiAccent.gold,
      ),
    };
  }
}

/// One of the two ways to get a photograph in.
///
/// Both are outlined rather than solid: neither is the action the driver
/// came to this screen to take (that is "save", on the anchored sheet), but
/// both are the only way to make the profile usable, so they keep a visible
/// edge instead of becoming plain text -- the same reasoning as
/// `DriverQrCapturePage`'s picker button.
///
/// Stacked full-width rather than side by side. «Галерейгаас сонгох» does
/// not fit half a 390dp phone, and a pair of buttons where one label wraps
/// to two lines and the other does not looks like a mistake.
class _PickPhotoButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _PickPhotoButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: surfaces.onSheet,
        side: BorderSide(color: surfaces.muted),
        minimumSize: const Size.fromHeight(TakhiTouch.minTarget),
        shape: const RoundedRectangleBorder(borderRadius: TakhiRadius.pillAll),
        // Never the bare token: `ButtonStyle.textStyle` replaces the
        // inherited style rather than merging onto it, and the bundled
        // Cyrillic family would go with it.
        textStyle: takhiButtonTextStyle(context, TakhiType.title),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
