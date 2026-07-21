// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'call_engine.dart';
import 'call_signal_service.dart';
import 'fallback_decision.dart';
import 'helper_directory_service.dart';
import 'phone_share_settings.dart';
import '../ride/ride_dm_payload.dart';

/// Where a call attempt currently stands, as the UI (`CallScreen`, Step 4
/// below) renders it. `CallStateFallbackPhone`/`CallStateFallbackVoiceNote`
/// are terminal for the WebRTC attempt but not for the call itself -- the
/// UI offers the next rung, it doesn't auto-dial or auto-record.
sealed class CallState {
  const CallState();
}

class CallStateDialing extends CallState {
  const CallStateDialing();
}

class CallStateRinging extends CallState {
  const CallStateRinging();
}

class CallStateConnecting extends CallState {
  const CallStateConnecting();
}

class CallStateConnected extends CallState {
  const CallStateConnected();
}

class CallStateFallbackPhone extends CallState {
  final String phone;
  const CallStateFallbackPhone(this.phone);
}

class CallStateFallbackVoiceNote extends CallState {
  const CallStateFallbackVoiceNote();
}

class CallStateEnded extends CallState {
  final String reason;
  const CallStateEnded(this.reason);
}

/// Orchestrates one call attempt for [tripId] between this device
/// ([myPubHex]/[myPrivHex]) and [counterpartyPubHex]: drives [CallEngine]
/// (WebRTC), exchanges signaling over [signal] (NIP-17 DM, Task 2), and --
/// if the whole WebRTC attempt does not connect within [connectTimeout] --
/// applies [decideFallbackAction] (Task 5) to decide between offering a
/// phone call (only if [counterpartyPhone] is non-null and
/// [phoneShareSettings] currently has sharing enabled) or a voice note.
/// [helperDirectory]'s TURN list is not consulted here: it is already
/// snapshotted into [CallEngine]'s fixed ICE server config by
/// `CallScreen`'s call to `buildIceServers()` before this class is
/// constructed (Task 3) -- there is no live TURN list to keep flowing
/// once a [CallEngine] exists. One instance is exactly one call attempt;
/// call [dispose] when the call (or the fallback UI built on top of it)
/// is done.
class CallService {
  final CallEngine _engine;
  final CallSignalService _signal;
  // ignore: unused_field
  final HelperDirectoryService _helperDirectory;
  final PhoneShareSettingsStore _phoneShareSettings;
  final String myPubHex;
  final String myPrivHex;
  final String counterpartyPubHex;
  final String tripId;
  final String? counterpartyPhone;
  final Duration connectTimeout;

  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get state => _stateController.stream;

  StreamSubscription<void>? _signalSub;
  StreamSubscription<void>? _iceSub;
  StreamSubscription<void>? _connSub;
  Timer? _timeoutTimer;
  int Function() _now = () => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  bool _webrtcConnected = false;
  bool _disposed = false;

  CallService({
    required CallEngine engine,
    required CallSignalService signal,
    required HelperDirectoryService helperDirectory,
    required PhoneShareSettingsStore phoneShareSettings,
    required this.myPubHex,
    required this.myPrivHex,
    required this.counterpartyPubHex,
    required this.tripId,
    this.counterpartyPhone,
    this.connectTimeout = const Duration(seconds: 15),
  }) : _engine = engine,
       _signal = signal,
       _helperDirectory = helperDirectory,
       _phoneShareSettings = phoneShareSettings;

  Future<void> startAsCaller({required int Function() now}) async {
    _now = now;
    _wireCommon();
    _stateController.add(const CallStateDialing());
    final offer = await _engine.createOffer();
    await _signal.sendOffer(
      privHex: myPrivHex,
      recipientPubHex: counterpartyPubHex,
      tripId: tripId,
      sdp: offer.sdp,
      now: now(),
    );
    _startTimeout();
  }

  Future<void> acceptIncomingOffer(
    String offerSdp, {
    required int Function() now,
  }) async {
    _now = now;
    _wireCommon();
    _stateController.add(const CallStateConnecting());
    final answer = await _engine.createAnswer(offerSdp);
    await _signal.sendAnswer(
      privHex: myPrivHex,
      recipientPubHex: counterpartyPubHex,
      tripId: tripId,
      sdp: answer.sdp,
      now: now(),
    );
    _startTimeout();
  }

  void _wireCommon() {
    _signalSub = _signal
        .watchSignals(myPubHex, myPrivHex, tripId)
        .listen(_onSignal);
    _iceSub = _engine.localIceCandidates.listen((c) {
      unawaited(
        _signal.sendIceCandidate(
          privHex: myPrivHex,
          recipientPubHex: counterpartyPubHex,
          tripId: tripId,
          candidate: c.candidate,
          sdpMid: c.sdpMid,
          sdpMLineIndex: c.sdpMLineIndex,
          now: _now(),
        ),
      );
    });
    _connSub = _engine.connectionState.listen(_onConnectionState);
  }

  void _onSignal(ReceivedCallSignal received) {
    switch (received.payload) {
      case CallAnswerPayload(:final sdp):
        unawaited(_engine.acceptAnswer(sdp));
      case CallIceCandidatePayload(
        :final candidate,
        :final sdpMid,
        :final sdpMLineIndex,
      ):
        unawaited(
          _engine.addRemoteIceCandidate(
            IceCandidateData(candidate, sdpMid, sdpMLineIndex),
          ),
        );
      case CallHangupPayload(:final reason):
        _stateController.add(CallStateEnded(reason));
      default:
        break; // CallOfferPayload: handled by IncomingCallListener, not here.
    }
  }

  void _onConnectionState(CallConnectionState s) {
    if (s == CallConnectionState.connected) {
      _webrtcConnected = true;
      _timeoutTimer?.cancel();
      _stateController.add(const CallStateConnected());
    } else if (s == CallConnectionState.failed) {
      unawaited(_applyFallback(webrtcTimedOut: true));
    }
  }

  void _startTimeout() {
    _timeoutTimer = Timer(
      connectTimeout,
      () => unawaited(_applyFallback(webrtcTimedOut: true)),
    );
  }

  Future<void> _applyFallback({required bool webrtcTimedOut}) async {
    if (_disposed || _webrtcConnected) return;
    final action = decideFallbackAction(
      webrtcConnected: _webrtcConnected,
      webrtcTimedOut: webrtcTimedOut,
      counterpartyPhoneKnown: counterpartyPhone != null,
      phoneShareEnabled: await _phoneShareSettings.isEnabled(),
    );
    switch (action) {
      case CallFallbackAction.keepTryingWebrtc:
        return;
      case CallFallbackAction.offerPhoneCall:
        _stateController.add(CallStateFallbackPhone(counterpartyPhone!));
      case CallFallbackAction.offerVoiceMessage:
        _stateController.add(const CallStateFallbackVoiceNote());
    }
  }

  Future<void> setMuted(bool muted) => _engine.setMuted(muted);

  Future<void> hangUp({required int Function() now}) async {
    await _signal.sendHangup(
      privHex: myPrivHex,
      recipientPubHex: counterpartyPubHex,
      tripId: tripId,
      now: now(),
    );
    _stateController.add(const CallStateEnded('local'));
    await dispose();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timeoutTimer?.cancel();
    await _signalSub?.cancel();
    await _iceSub?.cancel();
    await _connSub?.cancel();
    await _engine.dispose();
    await _stateController.close();
  }
}
