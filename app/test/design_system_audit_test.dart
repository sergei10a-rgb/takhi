// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `<marker>...)` expression in [source], sliced out by matching
/// parentheses from the constructor name. Parenthesis counting is enough
/// here because nothing this scans puts an unbalanced `(` inside a string
/// literal -- if something ever does, this test is where it will show up.
Iterable<String> _constructorBodies(String source, String marker) sync* {
  var from = 0;
  while (true) {
    final start = source.indexOf(marker, from);
    if (start < 0) return;
    var depth = 0;
    var i = start + marker.length - 1;
    for (; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') depth--;
      if (depth == 0) break;
    }
    yield source.substring(start, i.clamp(start, source.length));
    from = i + 1;
  }
}

/// Every `AlertDialog(...)` expression in [source].
Iterable<String> _alertDialogBodies(String source) =>
    _constructorBodies(source, 'AlertDialog(');

// ---------------------------------------------------------------------------
// Screenshot coverage
// ---------------------------------------------------------------------------
//
// Two bugs this session were found *only* by looking at a picture, with the
// whole suite green both times: «12443₮» with the currency mark drawn on top
// of a digit (552 tests green), and «Түр зогсоох» rendered as ▯▯▯ ▯▯▯▯▯▯▯
// (565 tests green). A widget test proves a widget is *there*; it cannot
// prove it is *legible*. The screenshots are the only thing that can, so the
// question stops being "did someone remember to take one" and becomes a
// check: add a route, and this file goes red until a picture exists for it.
//
// See docs/design/SCREENSHOT_RULE.md for the human-facing version.

/// Where the design screenshots live, relative to the package root --
/// `flutter test` runs with `app/` as its working directory.
const _screenshotDir = 'test/golden/images';

/// The one file allowed to declare routes. [_routeCoverageProblems] fails if
/// a `GoRoute(` appears anywhere else under `lib/`, because a router this
/// test does not read is a router whose screens it cannot demand pictures of.
const _routerFile = 'lib/router.dart';

/// A prefix has to be long enough to name a screen. Nothing stops a future
/// edit from "covering" a new route with `''` or `'_'`, which would match
/// every picture in the directory and make the whole table vacuous; this
/// floor is what stops it.
const _minPrefixLength = 4;

/// Which pictures stand for which route.
///
/// **The matching rule:** a screenshot belongs to a route when its file name
/// starts with one of that route's prefixes. `/home` claims `home_*.png`,
/// `/meter` claims `meter_*.png`.
///
/// A written-out table rather than a prefix derived from the path, because
/// the two vocabularies genuinely differ and always will. A route is named
/// after *who is driving* (`/ride/passenger`); a screenshot is named after
/// *what is on screen* (`trip_fare_confirm_light`). The same active-trip
/// pictures hang off both ride routes, and `/home` also owns the SOS sheet,
/// which is a bottom sheet rather than a destination. Deriving names would
/// mean either renaming production routes to suit a test or renaming the
/// pictures away from what they show.
///
/// Both directions are checked, so the table cannot rot quietly:
///  * every route must appear here or in [_routesWithoutScreenshots];
///  * every prefix here must match at least one real file (no dead entries);
///  * every file in the directory must be claimed by some prefix (no
///    orphans left behind by a rename).
const _routeScreenshotPrefixes = <String, List<String>>{
  // `/` builds StartupGate, which either holds the splash (excluded below,
  // see S33) or falls through to OnboardingPage.
  '/': ['onboarding_'],
  '/seed': ['seed_'],
  '/restore': ['restore_'],
  // The SOS sheet opens from the home top bar, so it is home's picture.
  '/home': ['home_', 'sos_'],
  '/ride/passenger': ['passenger_', 'trip_', 'call_'],
  // The driver reaches the QR-capture page from this page's AppBar, and
  // hosts the same active-trip and call surfaces as the passenger.
  '/ride/driver': [
    'driver_inbox_',
    'driver_offer_',
    'driver_awarded_',
    'qr_capture_',
    'trip_',
    'call_',
  ],
  '/meter': ['meter_'],
  '/settings': ['settings_menu_'],
  '/settings/phone-share': ['phone_share_'],
  '/settings/driver-profile': ['driver_profile_'],
  '/settings/legal': ['legal_notice_'],
};

/// Routes deliberately left without a picture, and why. Exact paths, never
/// patterns: a rule broad enough to cover `/settings/*` would also cover the
/// next `/settings/...` screen somebody adds, which is precisely the failure
/// this file exists to make impossible.
const _routesWithoutScreenshots = <String, String>{
  '/settings/emergency-contact':
      'S29. Almost pixel-identical to phone_share_settings_light: the same '
      'SectionHeading, the same LabeledField and the same anchored '
      'PrimaryButton, minus that screen\'s sharing MenuRow and its Switch '
      '(call/phone_share_settings_page.dart). The covered screen is the '
      'wider of the two.',
};

/// A screen *state* that is deliberately not photographed.
///
/// [absentImage] is the file name the picture would have had. The test
/// asserts that file does not exist: the day somebody photographs the state
/// anyway, this entry is stale and has to be deleted rather than left to
/// contradict the directory. That is best-effort -- a picture filed under a
/// different name slips past -- but it costs nothing and never fires falsely.
class _UnphotographedState {
  const _UnphotographedState(this.what, this.absentImage, this.why);

  /// Where the state lives, as `path/to/file.dart` plus the widget.
  final String what;

  /// The `images/` basename (no `.png`) this state would occupy.
  final String absentImage;

  /// Why a picture of it would tell a reviewer nothing new.
  final String why;
}

/// The judgement calls, written down. Every one of these is "the picture
/// would be a near-duplicate, an empty rectangle, or unreachable" -- never
/// "it was hard to stage".
const _unphotographedStates = <_UnphotographedState>[
  _UnphotographedState(
    'onboarding/startup_gate.dart _StartupSplash (no indicator)',
    'splash_idle_light',
    'S33. A completely empty coloured screen -- no text, no element. The '
        'picture would be a single-colour rectangle, and splash_parity_test '
        'already checks that colour mechanically.',
  ),
  _UnphotographedState(
    'onboarding/startup_gate.dart _StartupSplash (indicator shown)',
    'splash_waiting_light',
    'S33. Differs from the above by a 3px LinearProgressIndicator -- all '
        'but indistinguishable in pixels, so a second picture is pointless.',
  ),
  // Two entries used to sit here, and both were wrong in the same way. They
  // reasoned that a map screen is "thin on information" because
  // `flutter_test` never fetches tiles, and excluded the destination picker
  // and the driver's nearby-calls map on that basis -- which withdrew the
  // one check that looks at a picture from precisely the screens whose
  // content IS the picture. The bugs that followed were exactly the kind a
  // photograph catches and an assertion cannot: a map with no mark for the
  // rider's own position, a destination picked with no sight of the pickup,
  // two points chosen and no line between them. Tiles or no tiles, the
  // MARKS paint -- so both states are now photographed
  // (passenger_dropoff_light, driver_inbox_markers_light).
  _UnphotographedState(
    'ride/driver_inbox_page.dart nearby-orders map, empty',
    'driver_inbox_empty_light',
    'S14. Differs from driver_inbox_markers_light by the absence of one '
        'person_pin_circle and by the count chip reading 0 -- and that same '
        'sheet is also in frame, unobscured, behind the dialog in '
        'driver_offer_dialog_light. Two pictures already cover it.',
  ),
  _UnphotographedState(
    'ride/active_trip_view.dart _TrackingView, driver, tripInProgress',
    'trip_tracking_driver_inprogress_light',
    'S16. Differs from trip_tracking_driver_light by the phase label and '
        'the bottom button LABEL only; the layout is identical. A pixel '
        'duplicate.',
  ),
  _UnphotographedState(
    'ride/active_trip_view.dart _TrackingView, passenger, fixed price',
    'trip_tracking_fixed_light',
    'S10. A subset of trip_tracking_metered_light: the live-fare row and '
        'the waiting row drop out, everything else is the same.',
  ),
  _UnphotographedState(
    'ride/active_trip_view.dart _TrackingView, arrived phase',
    'trip_tracking_arrived_light',
    'S10. A momentary transition -- the bottom button becomes '
        'SizedBox.shrink and the view moves straight on to fareConfirm or '
        'rating. Users barely see it and it is nearly identical to enRoute.',
  ),
  _UnphotographedState(
    'ride/active_trip_view.dart _FareConfirmView, no waiting time',
    'trip_fare_confirm_nowait_light',
    'S11. A subset of trip_fare_confirm_light: with waitingFareMnt = 0 the '
        'whole breakdown block disappears and one total remains. The '
        'photographed variant is the wider one.',
  ),
  _UnphotographedState(
    'ride/active_trip_view.dart _RatingView, star chosen / submitting',
    'trip_rating_filled_light',
    'S12. Differs from trip_rating_empty_light only by star fill and button '
        'enablement. The disabled variant is the riskier one, so that is the '
        'one photographed.',
  ),
  _UnphotographedState(
    'meter/taximeter_page.dart destination-picker modal sheet',
    'meter_destination_sheet_light',
    'S20. Its content is LocationPickerField, already covered by '
        'passenger_pickup_light, inside a TakhiSheet frame already visible '
        'in meter_running_light and meter_idle_light.',
  ),
  _UnphotographedState(
    'meter/taximeter_page.dart pause-confirmation dialog',
    'meter_pause_confirm_dialog_light',
    'S32. A neutral+primary DialogActionBar pairing, structurally identical '
        'in tone to passenger_confirm_offer_dialog_light. All three tones '
        '(destructive / caution / primary) are covered by other pictures.',
  ),
  _UnphotographedState(
    'meter/taximeter_page.dart _TariffStep, edit mode with values',
    'meter_tariff_edit_light',
    'S19. Adds no new pixels beyond meter_tariff_first_light (structure) '
        'plus meter_tariff_invalid_light (the variant with a cancel button).',
  ),
  _UnphotographedState(
    'meter/taximeter_page.dart _TariffStep, only the waiting tariff invalid',
    'meter_tariff_wait_invalid_light',
    'S19. A subset of meter_tariff_invalid_light, where both fields are '
        'invalid at once.',
  ),
  _UnphotographedState(
    'meter/taximeter_page.dart idle, location permission refused',
    'meter_location_denied_light',
    'S31. Literally the same widget as trip_location_denied_light '
        '(LocationPermissionDeniedView); a second picture adds nothing.',
  ),
  // The filled state used to be excluded here as "differs by field text and
  // button enablement only". That stopped being true the moment the screen
  // grew a portrait: filled now means a face inside the circle and a GREEN
  // readiness notice where the empty form carries a clay warning, which is
  // a different picture rather than the same one with words in the boxes.
  // It is photographed as driver_profile_photo_ready_light.
  _UnphotographedState(
    'profile/driver_profile_page.dart, photo refused for a reason other than '
        'a missing face',
    'driver_profile_photo_permission_light',
    'S17. Every refusal -- no face, two faces, too small, unreadable file, '
        'denied permission, checker unavailable -- is the same clay '
        'NoticeCard in the same slot with a different sentence in it. '
        'driver_profile_photo_refused_light photographs that slot; the other '
        'five would differ from it by the string alone, and l10n_test plus '
        'font_coverage_test already hold the strings.',
  ),
  _UnphotographedState(
    'profile/driver_profile_page.dart, face check running',
    'driver_profile_photo_checking_light',
    'S17. A one-line muted label under two dimmed picker buttons, on screen '
        'for as long as one 512px JPEG takes to encode. Identical to '
        'driver_profile_empty_light apart from that line and the button '
        'opacity.',
  ),
  _UnphotographedState(
    'payment/driver_qr_capture_page.dart, image chosen',
    'qr_capture_picked_light',
    "S18. The middle of the screen becomes the user's own photo "
        '(Image.memory) -- live media; the rest matches '
        'qr_capture_empty_light.',
  ),
  _UnphotographedState(
    'call/call_screen.dart CallStateEnded',
    'call_ended',
    'S23. One gold line on an otherwise empty ink screen, dismissed '
        'automatically after two seconds. Nearly blank, and a duplicate of '
        'call_connecting minus the label.',
  ),
  _UnphotographedState(
    'onboarding/onboarding_page.dart, driver mode selected',
    'onboarding_driver_light',
    'S1. Only the fill of one SegmentedButton segment moves -- all but '
        'indistinguishable in pixels.',
  ),
  _UnphotographedState(
    'ride/driver_inbox_page.dart _OfferDialog with no km-tariff behind it',
    'driver_offer_dialog_no_tariff_light',
    'S14a. Unreachable. This dialog is only opened by _sendOffer, which '
        'now returns early unless driverOfferBlock passes -- and that needs '
        'a saved DriverProfile, whose kmTariffMnt is non-nullable. So the '
        'dialog cannot exist without a tariff behind it, and the '
        '_NoTariffHint branch that used to be photographed here is dead on '
        'that path. The picture was taken until the portrait gate landed; '
        'it was deleted rather than left to show a state the app can no '
        'longer produce.',
  ),
  _UnphotographedState(
    'ride/passenger_ride_page.dart _PassengerStep.activeTrip fallback '
        'SizedBox.shrink()',
    'passenger_activetrip_fallback_light',
    'Unreachable branch, documented in the code as a guard. No user ever '
        'sees it.',
  ),
  _UnphotographedState(
    'ride/active_trip_view.dart _DoneView with onFinished == null',
    'trip_done_nofinish_light',
    'Unreachable: both production hosts (PassengerRidePage and '
        'DriverInboxPage) pass onFinished.',
  ),
  _UnphotographedState(
    'SnackBars: qrSavedConfirmation, driverProfileSavedConfirmation, '
        'voiceNoteReceivedLabel, voiceNoteTooLongHint, qrSaveError',
    'snackbars_light',
    'Transient Material layer over screens that are themselves already '
        'photographed; the SnackBar is theme default and gone in seconds.',
  ),
  _UnphotographedState(
    'safety/share_link.dart -> Share.share() system share sheet',
    'share_sheet_light',
    'S25. Operating-system UI -- the app does not draw it and it never '
        'appears under flutter_test.',
  ),
  _UnphotographedState(
    'docs/share/index.html trip-sharing WEB page',
    'share_web_light',
    'S26. Not a Flutter screen but a web page; matchesGoldenFile cannot '
        'render it.',
  ),
  _UnphotographedState(
    'map/ride_map.dart itself (the tile layer)',
    'ride_map_light',
    "flutter_test blocks HTTP tile fetches, so only flutter_map's empty "
        'canvas would be drawn. The map POSITION and SIZE are already '
        'visible in the home, meter_running and tracking pictures.',
  ),
  _UnphotographedState(
    'meter/taximeter_page.dart _MeterModeBadge, moving mode',
    'meter_mode_badge_light',
    'Already visible inside meter_running_light; it does not need a frame '
        'of its own.',
  ),
];

/// The screenshot file names currently on disk, without extension.
List<String> _screenshotNames() =>
    Directory(_screenshotDir)
        .listSync()
        .whereType<File>()
        .map((file) {
          return file.path.replaceAll('\\', '/').split('/').last;
        })
        .where((name) => name.endsWith('.png'))
        .map((name) {
          return name.substring(0, name.length - '.png'.length);
        })
        .toList()
      ..sort();

/// Path literals of every `GoRoute(` in [source], in declaration order.
///
/// A `GoRoute` without a literal `path:` yields a sentinel rather than being
/// skipped, so an unreadable declaration fails the coverage check instead of
/// vanishing from it.
List<String> _declaredRoutePaths(String source) {
  final pattern = RegExp('''path:\\s*(?:'([^']*)'|"([^"]*)")''');
  final paths = <String>[];
  for (final body in _constructorBodies(source, 'GoRoute(')) {
    final match = pattern.firstMatch(body);
    paths.add(
      match == null
          ? '<GoRoute with no literal path:>'
          : match.group(1) ?? match.group(2)!,
    );
  }
  return paths;
}

/// Everything wrong with the route/screenshot mapping right now, as
/// human-readable lines. Empty means covered.
List<String> _routeCoverageProblems() {
  final problems = <String>[];

  // A router this test does not read is a router whose screens it cannot
  // demand pictures of, so a second one has to fail loudly rather than
  // silently widen the blind spot.
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final posix = entity.path.replaceAll('\\', '/');
    if (posix.endsWith(_routerFile)) continue;
    if (entity.readAsStringSync().contains('GoRoute(')) {
      problems.add(
        '$posix declares routes, but this check only reads $_routerFile',
      );
    }
  }

  final source = File(_routerFile).readAsStringSync();
  final routes = _declaredRoutePaths(source);
  if (routes.isEmpty) {
    problems.add('parsed no GoRoute out of $_routerFile -- parser is broken');
  }
  // Nested routes would make a child's `path:` relative to its parent, which
  // this flat parser would report as an absolute path. None exist today;
  // this is what says so out loud if one appears.
  for (final body in _constructorBodies(source, 'GoRoute(')) {
    if (body.indexOf('GoRoute(', 1) >= 0) {
      problems.add(
        'nested GoRoute in $_routerFile -- _declaredRoutePaths reads paths '
        'as absolute and must be taught about sub-routes first',
      );
      break;
    }
  }

  final screenshots = _screenshotNames();
  if (screenshots.isEmpty) {
    problems.add('no screenshots at all in $_screenshotDir');
  }

  final claimed = <String>{};
  for (final route in routes) {
    if (_routesWithoutScreenshots.containsKey(route)) continue;
    final prefixes = _routeScreenshotPrefixes[route];
    if (prefixes == null) {
      problems.add(
        "route '$route' has no screenshot: add one and list its file-name "
        'prefix in _routeScreenshotPrefixes, or -- if a picture of it would '
        'genuinely show nothing new -- add it to _routesWithoutScreenshots '
        'with the reason spelled out',
      );
      continue;
    }
    for (final prefix in prefixes) {
      if (prefix.length < _minPrefixLength) {
        problems.add(
          "route '$route' declares prefix '$prefix', shorter than "
          '$_minPrefixLength characters -- too broad to name a screen',
        );
        continue;
      }
      final matches = screenshots.where((n) => n.startsWith(prefix));
      if (matches.isEmpty) {
        problems.add(
          "route '$route' declares prefix '$prefix' but no file in "
          '$_screenshotDir starts with it',
        );
      }
      claimed.addAll(matches);
    }
  }

  // Stale table rows: a route that was renamed or deleted leaves an entry
  // that now covers nothing and quietly stops meaning anything.
  final declared = {
    ..._routeScreenshotPrefixes.keys,
    ..._routesWithoutScreenshots.keys,
  };
  for (final path in declared) {
    if (!routes.contains(path)) {
      problems.add(
        "'$path' is listed in the screenshot tables but is no longer a route "
        'in $_routerFile',
      );
    }
  }

  for (final name in screenshots) {
    if (!claimed.contains(name)) {
      problems.add(
        '$_screenshotDir/$name.png belongs to no route -- either it was '
        'renamed out of its prefix, or its route is missing from '
        '_routeScreenshotPrefixes',
      );
    }
  }

  return problems;
}

void main() {
  // The dialog-button audit found brand gold on paper at 2.28:1 across
  // seven dialogs at once, because each one had hand-rolled its own action
  // buttons and inherited Material's defaults. Centralising them in
  // `DialogActionBar` fixed all seven; this check is what stops the eighth
  // dialog from starting the cycle again. A raw button inside an
  // `AlertDialog` is the exact shape of that regression.
  test('every AlertDialog builds its actions with DialogActionBar, never '
      'bare Material buttons', () {
    const bareButtons = [
      'TextButton(',
      'FilledButton(',
      'ElevatedButton(',
      'OutlinedButton(',
      'PrimaryButton(',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final body in _alertDialogBodies(entity.readAsStringSync())) {
        if (!body.contains('DialogActionBar(')) {
          offenders.add('${entity.path}: dialog has no DialogActionBar');
        }
        for (final button in bareButtons) {
          if (body.contains(button)) {
            offenders.add('${entity.path}: dialog builds a bare $button)');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Dialog actions must go through widgets/dialog_action_bar.dart, '
          'which owns the readable-on-the-sheet colours and the '
          'row-or-stack fitting rule for long Cyrillic labels:\n'
          '${offenders.join('\n')}',
    );
  });

  test('no widget file hardcodes a raw Color(0x... outside the theme file', () {
    final libDir = Directory('lib');
    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path
          .replaceAll('\\', '/')
          .endsWith('theme/takhi_theme.dart')) {
        continue; // the one file allowed to define raw palette values
      }
      final content = entity.readAsStringSync();
      if (RegExp(r'Color\(0x').hasMatch(content)) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Hardcoded Color(0x...) outside theme/takhi_theme.dart -- use '
          'TakhiColors.* or Theme.of(context).colorScheme instead:\n'
          '${offenders.join('\n')}',
    );
  });

  // `ButtonStyle.textStyle` replaces the inherited text style instead of
  // merging onto it, so a bare family-less token there loses the app font.
  // It is invisible on a phone, where the platform fallback also has
  // Cyrillic; it took a rendered screenshot -- «Түр зогсоох» drawn as
  // ▯▯▯ ▯▯▯▯▯▯▯ next to correct text -- to catch the two call sites that had
  // it. A grep is the only guard that scales: nothing about the expression
  // looks wrong at the call site.
  test('no button style passes a bare TakhiType token as its textStyle', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'textStyle:\s*(const\s+)?TakhiType\.').hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A ButtonStyle textStyle must go through '
          'takhiButtonTextStyle(context, TakhiType.x) so it keeps the app '
          'font family:\n${offenders.join('\n')}',
    );
  });

  // Sixty-three hand-typed sizes had accumulated across fifteen files before
  // this check existed -- gaps of 18 where the scale says 16 or 20, a font at
  // 15 beside the role that is already 15, four radii for the same kind of
  // box. None of it was visible on its own; together it was why no two
  // screens quite matched, and why "make every gap a little wider" would have
  // meant hunting sixty-three call sites and missing some.
  //
  // A number is allowed in exactly two places: theme/takhi_theme.dart, which
  // defines the scale, and a named file-level constant, which is how a
  // genuinely one-off measurement (a safety gap between "answer" and
  // "decline", the width of a route line on a map) says so out loud.
  test('no widget file hardcodes a raw size -- spacing, radius, font and '
      'stroke all come from tokens', () {
    // `0` is not a magic number: it means "none", it has no alternative
    // value, and a token named zero would add indirection without preventing
    // any drift. Everything else has to justify itself.
    const zero = r'0(\.0)?';
    final banned = <String, RegExp>{
      'SizedBox spacing': RegExp(
        r'SizedBox\((height|width): (?!'
        '$zero'
        r'\b)\d',
      ),
      'EdgeInsets.all': RegExp(
        r'EdgeInsets\.all\((?!'
        '$zero'
        r'\))\d',
      ),
      'EdgeInsets edge': RegExp(
        r'\b(horizontal|vertical|left|right|top|bottom): (?!'
        '$zero'
        r'\b)\d',
      ),
      'fontSize': RegExp(r'fontSize: \d'),
      'radius': RegExp(
        r'(BorderRadius|Radius)\.circular\((?!'
        '$zero'
        r'\))\d',
      ),
      'strokeWidth': RegExp(
        r'strokeWidth: (?!'
        '$zero'
        r'\b)\d',
      ),
      'spacing/dimension': RegExp(
        r'\b(spacing|dimension): (?!'
        '$zero'
        r'\b)\d',
      ),
    };

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final posix = entity.path.replaceAll('\\', '/');
      // The scale itself, and generated localisations nobody edits by hand.
      if (posix.endsWith('theme/takhi_theme.dart')) continue;
      if (posix.contains('/l10n/')) continue;
      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // A named constant is the sanctioned escape hatch, so its own
        // declaration is not an offence -- only using a bare number where a
        // token belongs is.
        //
        // The right-hand side must be a *number* and nothing else. Exempting
        // every `const x = ...` line, as the first version of this did, let
        // `const _probe = SizedBox(height: 13);` through -- which is not a
        // named measurement, it is a raw literal wearing a name. That version
        // passed its own mutation probe, i.e. it was a hollow guard.
        if (RegExp(
          r'^\s*(static )?const \w+ = -?\d+(\.\d+)?;',
        ).hasMatch(line)) {
          continue;
        }
        for (final entry in banned.entries) {
          if (entry.value.hasMatch(line)) {
            offenders.add(
              '${entity.path}:${i + 1} (${entry.key}): '
              '${line.trim()}',
            );
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Raw sizes outside theme/takhi_theme.dart. Use TakhiSpace / '
          'TakhiRadius / TakhiType / TakhiStroke -- or, for a genuinely '
          'one-off measurement, a named file-level constant that says why. '
          'See docs/design/TOKENS.md:\n${offenders.join('\n')}',
    );
  });

  // The mechanical half of the screenshot rule: a route with no picture is
  // a screen nobody has looked at, and «12443₮» is what that costs. Adding
  // a GoRoute without adding a screenshot turns this red.
  test('every route in router.dart has at least one design screenshot', () {
    final problems = _routeCoverageProblems();
    expect(
      problems,
      isEmpty,
      reason:
          'Screenshot coverage is broken. Regenerate the pictures with\n'
          '  cd app && flutter test --update-goldens --run-skipped '
          'test/golden/ --concurrency=1\n'
          'and LOOK at the new ones -- see docs/design/SCREENSHOT_RULE.md.\n'
          '${problems.join('\n')}',
    );
  });

  // The exclusion list is the part of this rule that runs on judgement, so
  // it is the part that rots. Each excluded state names the file it would
  // have occupied; if that file turns up, the exclusion has been overtaken
  // by events and has to go, rather than sit there contradicting the
  // directory it is meant to explain.
  test(
    'no deliberately-unphotographed state has quietly been photographed',
    () {
      final screenshots = _screenshotNames().toSet();
      final stale = <String>[];
      final malformed = <String>[];
      for (final state in _unphotographedStates) {
        if (state.why.trim().isEmpty || state.absentImage.trim().isEmpty) {
          malformed.add('${state.what}: needs both a file name and a reason');
        }
        if (screenshots.contains(state.absentImage)) {
          stale.add(
            '${state.what}: ${state.absentImage}.png now exists, so this '
            'exclusion is out of date',
          );
        }
      }
      expect(
        [...malformed, ...stale],
        isEmpty,
        reason:
            'Delete the stale entries from _unphotographedStates -- a covered '
            'screen must not also be listed as skipped:\n'
            '${[...malformed, ...stale].join('\n')}',
      );
    },
  );
}
