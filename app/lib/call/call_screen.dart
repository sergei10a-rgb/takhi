// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../identity/identity_service.dart' show Identity;
import '../identity/identity_state.dart';
import '../l10n/app_localizations.dart';
import '../ride/ride_dm_payload.dart';
import '../theme/takhi_theme.dart';
import 'call_providers.dart';
import 'call_service.dart';
import 'call_signal_service.dart';
import 'ice_servers.dart';
import 'voice_note_service.dart';

int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// The full-screen call UI (spec §7.3): drives one [CallService] attempt
/// end to end -- dialing/ringing/connecting, connected with an elapsed-time
/// display and mute toggle, and either fallback rung (phone or voice note)
/// once [CallService] itself decides WebRTC did not connect in time. One
/// [CallScreen] is exactly one [CallService] attempt; both are disposed
/// together in [dispose].
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
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: TakhiColors.ink,
      body: SafeArea(
        child: Center(
          child: switch (_uiState) {
            CallStateDialing() ||
            CallStateRinging() ||
            CallStateConnecting() => _ConnectingBody(
              label: l.callConnectingLabel,
              onHangUp: () => unawaited(_hangUp()),
            ),
            CallStateConnected() => _ConnectedBody(
              elapsedSeconds: _elapsedSeconds,
              muted: _muted,
              onToggleMuted: () => unawaited(_toggleMuted()),
              onHangUp: () => unawaited(_hangUp()),
            ),
            CallStateFallbackPhone(:final phone) => _FallbackPhoneBody(
              label: l.callFailedOfferPhoneLabel,
              actionLabel: l.callViaPhoneAction,
              onCall: () => unawaited(_callByPhone(phone)),
            ),
            CallStateFallbackVoiceNote() => _FallbackVoiceNoteBody(
              recording: _recording,
              hint: l.holdToRecordVoiceNoteHint,
              onStart: () => unawaited(_startRecording()),
              onStop: () => unawaited(_stopRecordingAndSend()),
            ),
            CallStateEnded() => Text(
              l.callEndedLabel,
              style: const TextStyle(
                color: TakhiColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
          },
        ),
      ),
    );
  }
}

class _ConnectingBody extends StatelessWidget {
  final String label;
  final VoidCallback onHangUp;
  const _ConnectingBody({required this.label, required this.onHangUp});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(color: TakhiColors.gold),
      const SizedBox(height: 16),
      Text(label, style: const TextStyle(color: TakhiColors.gold)),
      const SizedBox(height: 32),
      _HangUpButton(onPressed: onHangUp),
    ],
  );
}

class _ConnectedBody extends StatelessWidget {
  final int elapsedSeconds;
  final bool muted;
  final VoidCallback onToggleMuted;
  final VoidCallback onHangUp;

  const _ConnectedBody({
    required this.elapsedSeconds,
    required this.muted,
    required this.onToggleMuted,
    required this.onHangUp,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        _formatElapsed(elapsedSeconds),
        style: const TextStyle(
          color: TakhiColors.gold,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 32),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 40,
            icon: Icon(
              muted ? Icons.mic_off : Icons.mic,
              color: TakhiColors.gold,
            ),
            onPressed: onToggleMuted,
          ),
          const SizedBox(width: 24),
          _HangUpButton(onPressed: onHangUp),
        ],
      ),
    ],
  );

  static String _formatElapsed(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _FallbackPhoneBody extends StatelessWidget {
  final String label;
  final String actionLabel;
  final VoidCallback onCall;

  const _FallbackPhoneBody({
    required this.label,
    required this.actionLabel,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: TakhiColors.gold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onCall,
          icon: const Icon(Icons.call),
          label: Text(actionLabel),
        ),
      ],
    ),
  );
}

class _FallbackVoiceNoteBody extends StatelessWidget {
  final bool recording;
  final String hint;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _FallbackVoiceNoteBody({
    required this.recording,
    required this.hint,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GestureDetector(
        onLongPressStart: (_) => onStart(),
        onLongPressEnd: (_) => onStop(),
        child: IconButton(
          iconSize: 64,
          icon: Icon(
            recording ? Icons.fiber_manual_record : Icons.mic,
            color: recording ? Colors.redAccent : TakhiColors.gold,
          ),
          onPressed: null,
        ),
      ),
      const SizedBox(height: 16),
      Text(hint, style: const TextStyle(color: TakhiColors.gold)),
    ],
  );
}

class _HangUpButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _HangUpButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    iconSize: 48,
    icon: const Icon(Icons.call_end, color: Colors.redAccent),
    onPressed: onPressed,
  );
}

/// Wraps [child] with a live subscription for an incoming
/// `CallOfferPayload` addressed to this device for [tripId]
/// (`CallSignalService.watchSignals`, Task 2) -- shows a full-screen
/// accept/decline overlay the moment one arrives, without requiring any
/// local button tap first.
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
          });
    });
  }

  Future<void> _accept() async {
    final offer = _incomingOffer;
    if (offer == null) return;
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Stack(
      children: [
        widget.child,
        if (_incomingOffer != null)
          _IncomingCallOverlay(
            label: l.incomingCallLabel,
            acceptLabel: l.acceptCallAction,
            declineLabel: l.declineCallAction,
            onAccept: () => unawaited(_accept()),
            onDecline: () => unawaited(_decline()),
          ),
      ],
    );
  }
}

/// An icon + label combined into one tappable unit -- `IconButton` alone
/// only makes the icon itself tappable, which would leave the label text
/// beside it inert (and hard to hit in a real tap-based test/UI).
class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onPressed;

  const _CallActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: iconColor),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: TakhiColors.gold)),
        ],
      ),
    ),
  );
}

class _IncomingCallOverlay extends StatelessWidget {
  final String label;
  final String acceptLabel;
  final String declineLabel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _IncomingCallOverlay({
    required this.label,
    required this.acceptLabel,
    required this.declineLabel,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: TakhiColors.ink.withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: TakhiColors.gold,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CallActionButton(
                  icon: Icons.call,
                  iconColor: Colors.greenAccent,
                  label: acceptLabel,
                  onPressed: onAccept,
                ),
                const SizedBox(width: 48),
                _CallActionButton(
                  icon: Icons.call_end,
                  iconColor: Colors.redAccent,
                  label: declineLabel,
                  onPressed: onDecline,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
