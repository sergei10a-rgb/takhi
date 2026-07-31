// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../identity/identity_service.dart' show Identity;
import '../identity/identity_state.dart';
import '../identity/short_pubkey.dart';
import '../l10n/app_localizations.dart';
import '../ride/ride_dm_payload.dart';
import '../theme/takhi_theme.dart';
import '../widgets/accent_dot.dart';
import '../widgets/info_chip.dart';
import '../widgets/notice_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/takhi_sheet.dart';
import 'call_providers.dart';
import 'call_service.dart';
import 'call_signal_service.dart';
import 'ice_servers.dart';
import 'voice_note_service.dart';

int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// Gap between "answer" and "decline" on an incoming call.
///
/// Wider than any spacing token on purpose, and therefore its own named
/// constant rather than a token snapped to 32: these two buttons do opposite,
/// unrecoverable things, and the distance between them is a safety margin for
/// a thumb reaching across a ringing phone -- not part of the layout rhythm.
const _kCallActionGap = 48.0;

/// Diameter of the disc standing in for the other person.
///
/// Larger than `PersonRow`'s 44 avatar: on a screen with nothing else on it
/// this mark *is* the other person, and it is looked at from the length of
/// an arm while the phone rings.
const _kPeerAvatarSize = 76.0;

/// Diameter of the round call controls (hang up, mute, answer, decline).
const _kCallControlSize = 64.0;

/// Glyph inside one of those controls.
const _kCallControlGlyphSize = 30.0;

/// Side of the press-and-hold voice-note button. It is the whole control of
/// its screen and is held down rather than tapped, so it is sized to be
/// found and kept under a thumb without looking.
const _kVoiceNoteButtonSize = 88.0;

/// Diameter of the connecting spinner.
const _kConnectingSpinnerSize = 28.0;

/// The full-screen call UI (spec §7.3): drives one [CallService] attempt
/// end to end -- dialing/ringing/connecting, connected with an elapsed-time
/// display and mute toggle, and either fallback rung (phone or voice note)
/// once [CallService] itself decides WebRTC did not connect in time. One
/// [CallScreen] is exactly one [CallService] attempt; both are disposed
/// together in [dispose].
///
/// **It is the dark theme in both brightnesses, deliberately.** A call is
/// not a page of the app, it is a state the phone is in, and every phone
/// draws that state dark. The screen used to reach that by painting
/// [TakhiColors.ink] behind hand-set gold text, which is why it had no
/// surfaces, no rows and no cards on it -- the design system was simply not
/// in scope on this file. Swapping the *theme* instead of the background
/// colour puts the whole surface ladder back in reach (`sheet`, `field`,
/// `onSheet`, `muted`, the accent pairs), so the call screen is built out
/// of the same pieces as every other screen and still looks like a call.
class CallScreen extends ConsumerStatefulWidget {
  final String tripId;
  final String counterpartyPubHex;
  final bool isCaller;

  /// The remote SDP offer this device is answering. Required (and only
  /// meaningful) when [isCaller] is `false` -- `IncomingCallListener`
  /// always supplies it when pushing this screen for an accepted incoming
  /// call.
  final String? incomingOfferSdp;
  final String? counterpartyPhone;

  const CallScreen({
    super.key,
    required this.tripId,
    required this.counterpartyPubHex,
    required this.isCaller,
    this.incomingOfferSdp,
    this.counterpartyPhone,
  }) : assert(
         isCaller || incomingOfferSdp != null,
         'incomingOfferSdp is required when isCaller is false',
       );

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  CallService? _service;
  StreamSubscription<CallState>? _stateSub;
  Timer? _elapsedTimer;
  CallState _uiState = const CallStateDialing();
  int _elapsedSeconds = 0;
  bool _muted = false;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    ref.read(currentIdentityProvider.future).then((identity) {
      if (identity == null || !mounted) return;
      unawaited(_startCall(identity));
    });
  }

  Future<void> _startCall(Identity identity) async {
    final engineFactory = ref.read(callEngineFactoryProvider);
    // The live snapshot `helperDirectoryProvider` has accumulated so far
    // (real kind-30178 announcements, relayed in by
    // `HelperDirectoryService.watchHelpers` -- see that provider's doc
    // comment) is baked into `buildIceServers`'s fixed ICE server list
    // right here, once, before `CallEngine` is even constructed: there is
    // no live TURN list to keep flowing once a `CallEngine` exists (see
    // `ice_servers.dart`'s doc comment).
    final helpers = ref.read(helperDirectoryProvider).current();
    final service = CallService(
      engine: engineFactory(buildIceServers(helpers: helpers)),
      signal: ref.read(callSignalServiceProvider),
      phoneShareSettings: ref.read(phoneShareSettingsStoreProvider),
      myPubHex: identity.pubHex,
      myPrivHex: identity.privHex,
      counterpartyPubHex: widget.counterpartyPubHex,
      tripId: widget.tripId,
      counterpartyPhone: widget.counterpartyPhone,
    );
    if (!mounted) {
      unawaited(service.dispose());
      return;
    }
    setState(() => _service = service);
    _stateSub = service.state.listen(_onState);
    if (widget.isCaller) {
      await service.startAsCaller(now: _nowSeconds);
    } else {
      await service.acceptIncomingOffer(
        widget.incomingOfferSdp!,
        now: _nowSeconds,
      );
    }
  }

  void _onState(CallState s) {
    if (!mounted) return;
    setState(() => _uiState = s);
    if (s is CallStateConnected) _startElapsedTimer();
    if (s is CallStateEnded) _scheduleAutoPop();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedSeconds = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  void _scheduleAutoPop() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _hangUp() async {
    await _service?.hangUp(now: _nowSeconds);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleMuted() async {
    final next = !_muted;
    setState(() => _muted = next);
    await _service?.setMuted(next);
  }

  Future<void> _callByPhone(String phone) async {
    await launchUrl(Uri(scheme: 'tel', path: phone));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _startRecording() async {
    setState(() => _recording = true);
    await ref.read(voiceNoteRecorderProvider).start();
  }

  Future<void> _stopRecordingAndSend() async {
    final (bytes, durationSeconds) = await ref
        .read(voiceNoteRecorderProvider)
        .stop();
    if (mounted) setState(() => _recording = false);
    final service = _service;
    if (service == null) return;
    try {
      await ref
          .read(voiceNoteServiceProvider)
          .send(
            senderPrivHex: service.myPrivHex,
            recipientPubHex: service.counterpartyPubHex,
            tripId: service.tripId,
            audioBytes: bytes,
            durationSeconds: durationSeconds,
            now: _nowSeconds(),
          );
      if (mounted) Navigator.of(context).pop();
    } on VoiceNoteTooLongException {
      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.voiceNoteTooLongHint)));
    }
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    _elapsedTimer?.cancel();
    unawaited(_service?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Back has to mean exactly what the red hang-up button means. Without
    // this the route popped straight to `dispose`, which only tears down
    // the local `CallService` -- `CallService.dispose` sends no hangup (only
    // `hangUp` does), so the other side sat on `CallStateConnected` with its
    // mic open and its timer running, waiting for a call nobody was on.
    // No confirmation dialog: ending a call needs no second thought, the
    // signal just has to actually go out. `_hangUp` pops the route itself,
    // and `Navigator.pop` is not intercepted by `PopScope`, so this cannot
    // recurse.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_hangUp());
      },
      // Fixed dark, whatever the device is set to -- see the class comment.
      // `Builder` so everything below reads the *call* theme rather than the
      // app's, which is what puts `TakhiSurfaces.dark` and the dark accent
      // pairs in scope for the pieces this screen is built from.
      child: Theme(
        data: takhiTheme(Brightness.dark),
        child: Builder(builder: _buildBody),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final (status, actions) = _statusAndActions(context, l);

    return Scaffold(
      backgroundColor: surfaces.canvas,
      body: SafeArea(
        // Not the bottom: the action sheet adds the gesture inset itself.
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TakhiSpace.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CallPeer(counterpartyPubHex: widget.counterpartyPubHex),
                      const SizedBox(height: TakhiSpace.xxl),
                      status,
                    ],
                  ),
                ),
              ),
            ),
            // Every state that has a control puts it on the same sheet, in
            // the same place, at the bottom -- the shape the rest of the app
            // uses for "the answer to this screen". Before this the controls
            // were bare `IconButton`s floating in the middle of the ink.
            if (actions != null) TakhiSheet(showHandle: false, child: actions),
          ],
        ),
      ),
    );
  }

  /// What this call state shows in the middle of the screen, and what it
  /// offers on the sheet. `null` actions means the state has no control at
  /// all -- only [CallStateEnded], which dismisses itself.
  (Widget, Widget?) _statusAndActions(
    BuildContext context,
    AppLocalizations l,
  ) {
    final surfaces = TakhiSurfaces.of(context);
    switch (_uiState) {
      case CallStateDialing():
      case CallStateRinging():
      case CallStateConnecting():
        return (
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: _kConnectingSpinnerSize,
                width: _kConnectingSpinnerSize,
                child: CircularProgressIndicator(
                  strokeWidth: TakhiStroke.indicator,
                  color: TakhiColors.gold,
                ),
              ),
              const SizedBox(height: TakhiSpace.md),
              Text(
                l.callConnectingLabel,
                textAlign: TextAlign.center,
                style: TakhiType.title.copyWith(color: surfaces.onSheet),
              ),
            ],
          ),
          _CallControlBar(
            children: [
              _CallControl(
                icon: Icons.call_end,
                accent: TakhiAccent.clay,
                semanticLabel: l.hangUpCallAction,
                onPressed: () => unawaited(_hangUp()),
              ),
            ],
          ),
        );
      case CallStateConnected():
        return (
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoChip(
                icon: Icons.graphic_eq,
                label: l.connected,
                accent: TakhiAccent.steppe,
              ),
              const SizedBox(height: TakhiSpace.md),
              Text(
                _formatElapsed(_elapsedSeconds),
                // A numeric role, not a hand-set size: this figure ticks
                // once a second and only those roles carry tabular figures.
                // Without them every digit change shifts the ones beside it
                // and the clock visibly jitters for the whole call.
                style: TakhiType.numericDisplay.copyWith(
                  color: surfaces.onSheet,
                ),
              ),
            ],
          ),
          _CallControlBar(
            children: [
              _CallControl(
                icon: _muted ? Icons.mic_off : Icons.mic,
                accent: _muted ? TakhiAccent.clay : TakhiAccent.gold,
                semanticLabel: l.muteCallAction,
                onPressed: () => unawaited(_toggleMuted()),
              ),
              const SizedBox(width: _kCallActionGap),
              _CallControl(
                icon: Icons.call_end,
                accent: TakhiAccent.clay,
                semanticLabel: l.hangUpCallAction,
                onPressed: () => unawaited(_hangUp()),
              ),
            ],
          ),
        );
      case CallStateFallbackPhone(:final phone):
        return (
          NoticeCard(
            icon: Icons.wifi_off_outlined,
            text: l.callFailedOfferPhoneLabel,
            accent: TakhiAccent.clay,
          ),
          PrimaryButton(
            label: l.callViaPhoneAction,
            onPressed: () => unawaited(_callByPhone(phone)),
          ),
        );
      case CallStateFallbackVoiceNote():
        return (
          NoticeCard(
            icon: Icons.wifi_off_outlined,
            text: l.callFailedOfferPhoneLabel,
            accent: TakhiAccent.clay,
          ),
          _VoiceNoteControl(
            recording: _recording,
            hint: l.holdToRecordVoiceNoteHint,
            onStart: () => unawaited(_startRecording()),
            onStop: () => unawaited(_stopRecordingAndSend()),
          ),
        );
      case CallStateEnded():
        return (
          InfoChip(
            icon: Icons.call_end,
            label: l.callEndedLabel,
            accent: TakhiAccent.neutral,
          ),
          null,
        );
    }
  }

  static String _formatElapsed(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

/// Who is on the other end, as far as this app can ever know.
///
/// There are no accounts and no names here, so the abbreviated `npub` is the
/// identity -- the same string the trip screen puts under the counterparty
/// row, so the two can be compared. The call screen used to state nothing at
/// all about the other side, which on a screen whose entire subject is *that
/// person* is the one omission that matters.
class _CallPeer extends StatelessWidget {
  final String counterpartyPubHex;

  const _CallPeer({required this.counterpartyPubHex});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final surfaces = TakhiSurfaces.of(context);
    final key = shortPubkeyLabel(counterpartyPubHex);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AccentDot(
          icon: Icons.person_outline,
          accent: TakhiAccent.gold,
          size: _kPeerAvatarSize,
        ),
        const SizedBox(height: TakhiSpace.md),
        Text(
          l.callCounterpartyLabel,
          style: TakhiType.micro.copyWith(color: surfaces.muted),
        ),
        if (key != null) ...[
          const SizedBox(height: TakhiSpace.xxs),
          Text(
            key,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TakhiType.title.copyWith(color: surfaces.onSheet),
          ),
        ],
      ],
    );
  }
}

/// The row of round controls on the call sheet, centred.
class _CallControlBar extends StatelessWidget {
  final List<Widget> children;

  const _CallControlBar({required this.children});

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.center, children: children);
}

/// One round call control.
///
/// A tinted disc with the accent's own deep foreground on it, the same pair
/// [AccentDot] and [InfoChip] read, so a glyph on a call control clears WCAG
/// AA exactly like every other glyph in the app. `Colors.redAccent` on ink
/// -- what the hang-up button used to be -- clears nothing anybody measured.
class _CallControl extends StatelessWidget {
  final IconData icon;
  final TakhiAccent accent;

  /// Announced by a screen reader. User-visible: pass a localised string.
  final String semanticLabel;
  final VoidCallback onPressed;

  const _CallControl({
    required this.icon,
    required this.accent,
    required this.semanticLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = takhiAccentColors(accent, Theme.of(context).brightness);
    return Material(
      color: colors.tint,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: semanticLabel,
          child: SizedBox(
            height: _kCallControlSize,
            width: _kCallControlSize,
            child: Icon(
              icon,
              size: _kCallControlGlyphSize,
              color: colors.onTint,
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}

/// The press-and-hold voice-note control, plus the line that says so.
class _VoiceNoteControl extends StatelessWidget {
  final bool recording;
  final String hint;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _VoiceNoteControl({
    required this.recording,
    required this.hint,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    // Clay while recording, gold at rest: the same two families the meter's
    // mode badge uses to say "running" versus "not".
    final colors = takhiAccentColors(
      recording ? TakhiAccent.clay : TakhiAccent.gold,
      Theme.of(context).brightness,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: GestureDetector(
            onLongPressStart: (_) => onStart(),
            onLongPressEnd: (_) => onStop(),
            child: Container(
              height: _kVoiceNoteButtonSize,
              width: _kVoiceNoteButtonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.tint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                recording ? Icons.fiber_manual_record : Icons.mic,
                size: _kCallControlGlyphSize,
                color: colors.onTint,
                semanticLabel: hint,
              ),
            ),
          ),
        ),
        const SizedBox(height: TakhiSpace.sm),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: TakhiType.support.copyWith(color: surfaces.muted),
        ),
      ],
    );
  }
}

/// Wraps [child] with a live subscription for an incoming
/// `CallOfferPayload` addressed to this device for [tripId]
/// (`CallSignalService.watchSignals`, Task 2) -- shows a full-screen
/// accept/decline overlay the moment one arrives, without requiring any
/// local button tap first.
///
/// The overlay goes into the **root overlay**, not into a `Stack` around
/// [child]. It used to be the latter, and a `Positioned.fill` inside the
/// body of a `Scaffold` covers exactly the body: the `AppBar` above it
/// stayed at full brightness while everything under it went dark, which
/// reads as a rendering fault rather than as a ringing phone. `OverlayPortal`
/// reaches past the whole page without touching the `Navigator`, so the
/// scrim covers the screen and the back gesture still belongs to the trip
/// underneath.
///
/// **iOS limitation, stated once here in full:** this subscription (and
/// everything above it) only exists while the widget tree it wraps is
/// mounted and the app is in the foreground. On Android this is a real
/// limitation but a survivable one -- the OS keeps background sockets
/// alive long enough in most cases, and the driver-mode limitation (spec
/// §13) is already accepted. On iOS, backgrounding kills the socket
/// outright, so no incoming call can ever ring unless Тахь is already open
/// on the active-trip screen -- there is no CallKit/PushKit integration in
/// this plan, and building one would require a server to hold push tokens
/// and trigger wake-ups, directly violating this project's "no author-run
/// server" invariant. This plan does not build a workaround; it is stated
/// here, plainly, exactly as directly as spec §13 already states the
/// parallel driver-mode limitation. (`app/ios/` does not exist in this
/// repository yet regardless.)
class IncomingCallListener extends ConsumerStatefulWidget {
  final String tripId;
  final String counterpartyPubHex;
  final String? counterpartyPhone;
  final Widget child;

  const IncomingCallListener({
    super.key,
    required this.tripId,
    required this.counterpartyPubHex,
    this.counterpartyPhone,
    required this.child,
  });

  @override
  ConsumerState<IncomingCallListener> createState() =>
      _IncomingCallListenerState();
}

class _IncomingCallListenerState extends ConsumerState<IncomingCallListener> {
  StreamSubscription<ReceivedCallSignal>? _sub;
  Identity? _identity;
  CallOfferPayload? _incomingOffer;
  bool _callInProgress = false;
  final _overlay = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    ref.read(currentIdentityProvider.future).then((identity) {
      if (identity == null || !mounted) return;
      _identity = identity;
      _sub = ref
          .read(callSignalServiceProvider)
          .watchSignals(identity.pubHex, identity.privHex, widget.tripId)
          .where((s) => s.payload is CallOfferPayload)
          .listen((s) {
            if (!mounted || _callInProgress) return;
            setState(() => _incomingOffer = s.payload as CallOfferPayload);
            _overlay.show();
          });
    });
  }

  Future<void> _accept() async {
    final offer = _incomingOffer;
    if (offer == null) return;
    _overlay.hide();
    setState(() {
      _callInProgress = true;
      _incomingOffer = null;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          tripId: widget.tripId,
          counterpartyPubHex: widget.counterpartyPubHex,
          isCaller: false,
          incomingOfferSdp: offer.sdp,
          counterpartyPhone: widget.counterpartyPhone,
        ),
      ),
    );
    if (mounted) setState(() => _callInProgress = false);
  }

  Future<void> _decline() async {
    final identity = _identity;
    _overlay.hide();
    setState(() => _incomingOffer = null);
    if (identity == null) return;
    await ref
        .read(callSignalServiceProvider)
        .sendHangup(
          privHex: identity.privHex,
          recipientPubHex: widget.counterpartyPubHex,
          tripId: widget.tripId,
          now: _nowSeconds(),
        );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _overlay,
    // The *root* overlay, not the nearest one: the nearest is whatever the
    // host page happens to sit in, and the whole point is to reach past the
    // page (see the class comment).
    overlayLocation: OverlayChildLocation.rootOverlay,
    overlayChildBuilder: (overlayContext) => _IncomingCallOverlay(
      counterpartyPubHex: widget.counterpartyPubHex,
      onAccept: () => unawaited(_accept()),
      onDecline: () => unawaited(_decline()),
    ),
    child: widget.child,
  );
}

/// The ringing phone, over everything.
class _IncomingCallOverlay extends StatelessWidget {
  final String counterpartyPubHex;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _IncomingCallOverlay({
    required this.counterpartyPubHex,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) => Theme(
    // Same reasoning as `CallScreen`'s: a ringing phone is dark whatever
    // the app is, and switching the theme rather than the fill keeps the
    // surface ladder available to what is drawn on it.
    data: takhiTheme(Brightness.dark),
    child: Builder(
      builder: (context) {
        final l = AppLocalizations.of(context)!;
        final surfaces = TakhiSurfaces.of(context);
        final key = shortPubkeyLabel(counterpartyPubHex);
        return ColoredBox(
          color: surfaces.canvas.withValues(alpha: 0.96),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AccentDot(
                          icon: Icons.person_outline,
                          accent: TakhiAccent.gold,
                          size: _kPeerAvatarSize,
                        ),
                        const SizedBox(height: TakhiSpace.md),
                        Text(
                          l.incomingCallLabel,
                          style: TakhiType.heading.copyWith(
                            color: surfaces.onSheet,
                          ),
                        ),
                        if (key != null) ...[
                          const SizedBox(height: TakhiSpace.xxs),
                          Text(
                            key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TakhiType.support.copyWith(
                              color: surfaces.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                TakhiSheet(
                  showHandle: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CallActionButton(
                        icon: Icons.call,
                        accent: TakhiAccent.steppe,
                        label: l.acceptCallAction,
                        onPressed: onAccept,
                      ),
                      const SizedBox(width: _kCallActionGap),
                      _CallActionButton(
                        icon: Icons.call_end,
                        accent: TakhiAccent.clay,
                        label: l.declineCallAction,
                        onPressed: onDecline,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// A round control with its label under it, combined into one tappable
/// unit -- an `IconButton` alone only makes the icon itself tappable, which
/// would leave the word beside it inert (and hard to hit in a real
/// tap-based test/UI).
class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final TakhiAccent accent;
  final String label;
  final VoidCallback onPressed;

  const _CallActionButton({
    required this.icon,
    required this.accent,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final colors = takhiAccentColors(accent, Theme.of(context).brightness);
    return InkWell(
      onTap: onPressed,
      borderRadius: TakhiRadius.cardAll,
      child: Padding(
        padding: const EdgeInsets.all(TakhiSpace.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: _kCallControlSize,
              width: _kCallControlSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.tint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: _kCallControlGlyphSize,
                color: colors.onTint,
              ),
            ),
            const SizedBox(height: TakhiSpace.xs),
            Text(
              label,
              style: TakhiType.label.copyWith(color: surfaces.onSheet),
            ),
          ],
        ),
      ),
    );
  }
}
